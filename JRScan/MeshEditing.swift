import Foundation
import ModelIO
import simd

enum FragmentPolicy: String, CaseIterable, Identifiable, Sendable {
    case keepAll, removeSmall, largestOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keepAll: return "Keep all pieces"
        case .removeSmall: return "Remove tiny pieces (<1% area)"
        case .largestOnly: return "Keep largest piece only"
        }
    }
}

struct MeshEditOptions: Equatable, Sendable {
    var lower = SIMD3<Float>(repeating: 0)
    var upper = SIMD3<Float>(repeating: 1)
    var fragments = FragmentPolicy.removeSmall
}

struct MeshBounds: Sendable {
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>
    var extent: SIMD3<Float> { maximum - minimum }
    var center: SIMD3<Float> { (minimum + maximum) / 2 }
    var diagonal: Float { simd_length(extent) }
    func cropped(_ options: MeshEditOptions) -> MeshBounds {
        MeshBounds(minimum: minimum + extent * options.lower, maximum: minimum + extent * options.upper)
    }
}

/// Geometry stays in meters. Value buffers cross the background-work boundary;
/// Model I/O objects are created and used only within the operation that owns them.
struct EditableMesh: Sendable {
    let revision = UUID()
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]
    var triangleCount: Int { indices.count / 3 }
    var bounds: MeshBounds {
        MeshBounds(minimum: vertices.reduce(SIMD3(repeating: Float.infinity), simd_min),
                   maximum: vertices.reduce(SIMD3(repeating: -Float.infinity), simd_max))
    }

    static func load(_ source: URL) throws -> EditableMesh {
        let asset = try OBJExporter.flattened(MDLAsset(url: source), units: .meters)
        var result = EditableMesh(vertices: [], normals: [], indices: [])
        for object in asset.childObjects(of: MDLMesh.self) {
            guard let mesh = object as? MDLMesh,
                  let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3),
                  let normalData = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3),
                  let submeshes = mesh.submeshes as? [MDLSubmesh] else {
                throw ScanFailure.message("The model could not be read as editable triangle geometry.")
            }
            let base = UInt32(result.vertices.count)
            for index in 0..<mesh.vertexCount {
                result.vertices.append(vector(positions, index))
                result.normals.append(vector(normalData, index))
            }
            for submesh in submeshes {
                guard submesh.geometryType == .triangles else { throw ScanFailure.message("Expected triangle geometry.") }
                let buffer = submesh.indexBuffer(asIndexType: .uInt32)
                let map = buffer.map()
                let pointer = map.bytes.assumingMemoryBound(to: UInt32.self)
                for index in 0..<submesh.indexCount { result.indices.append(base + pointer[index]) }
            }
        }
        try result.validate()
        return result
    }

    func validate() throws {
        guard !vertices.isEmpty, !indices.isEmpty, indices.count.isMultiple(of: 3),
              vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
              indices.allSatisfy({ Int($0) < vertices.count }), bounds.diagonal.isFinite, bounds.diagonal > 1e-12 else {
            throw ScanFailure.message("The operation produced empty or invalid geometry. Widen the crop box; the saved model is unchanged.")
        }
    }

    func writeOBJ(_ url: URL) throws {
        try validate()
        guard normals.count == vertices.count else { throw ScanFailure.message("Missing edited geometry normals.") }
        var packed: [Float] = []
        packed.reserveCapacity(vertices.count * 6)
        for i in vertices.indices {
            packed += [vertices[i].x, vertices[i].y, vertices[i].z, normals[i].x, normals[i].y, normals[i].z]
        }
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 24)
        let submesh = MDLSubmesh(indexBuffer: MDLMeshBufferData(type: .index, data: indices.withUnsafeBytes { Data($0) }),
                                indexCount: indices.count, indexType: .uInt32, geometryType: .triangles, material: nil)
        let mesh = MDLMesh(vertexBuffer: MDLMeshBufferData(type: .vertex, data: packed.withUnsafeBytes { Data($0) }),
                           vertexCount: vertices.count, descriptor: descriptor, submeshes: [submesh])
        let asset = MDLAsset()
        asset.add(mesh)
        try asset.export(to: url)
        _ = try OBJExporter.validate(url)
    }

    private static func vector(_ data: MDLVertexAttributeData, _ index: Int) -> SIMD3<Float> {
        let p = data.dataStart.advanced(by: index * data.stride)
        return SIMD3(p.loadUnaligned(as: Float.self), p.advanced(by: 4).loadUnaligned(as: Float.self),
                     p.advanced(by: 8).loadUnaligned(as: Float.self))
    }
}

struct MeshEditResult: Sendable {
    let mesh: EditableMesh
    let summary: String
}

enum MeshEditing {
    private struct Cell: Hashable { let x: Int; let y: Int; let z: Int }
    private struct FaceKey: Hashable { let a: UInt32; let b: UInt32; let c: UInt32 }

    static func apply(_ source: EditableMesh, options: MeshEditOptions) throws -> MeshEditResult {
        try source.validate()
        for axis in 0..<3 {
            guard options.lower[axis].isFinite, options.upper[axis].isFinite,
                  options.lower[axis] >= 0, options.upper[axis] <= 1,
                  options.lower[axis] < options.upper[axis] else { throw ScanFailure.message("Invalid crop bounds.") }
        }
        let originalBounds = source.bounds
        let crop = originalBounds.cropped(options)
        let tolerance = max(originalBounds.diagonal * 1e-7, 1e-9)
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var cells: [Cell: [UInt32]] = [:]
        var faces = Set<FaceKey>()
        var inputFaces = Set<FaceKey>()
        var degenerate = 0, duplicates = 0, outside = 0

        func cell(_ v: SIMD3<Float>) -> Cell {
            let p = (v - originalBounds.minimum) / tolerance
            return Cell(x: Int(floor(p.x)), y: Int(floor(p.y)), z: Int(floor(p.z)))
        }
        func vertex(_ p: SIMD3<Float>) -> UInt32 {
            let key = cell(p)
            for x in -1...1 { for y in -1...1 { for z in -1...1 {
                for index in cells[Cell(x: key.x+x, y: key.y+y, z: key.z+z)] ?? [] {
                    if simd_distance_squared(vertices[Int(index)], p) <= tolerance * tolerance { return index }
                }
            } } }
            let index = UInt32(vertices.count)
            vertices.append(p)
            cells[key, default: []].append(index)
            return index
        }

        for triangle in stride(from: 0, to: source.indices.count, by: 3) {
            if triangle.isMultiple(of: 3000) { try Task.checkCancellation() }
            var polygon = (0..<3).map { source.vertices[Int(source.indices[triangle+$0])] }
            let sourceCross = simd_cross(polygon[1]-polygon[0], polygon[2]-polygon[0])
            guard simd_length_squared(sourceCross) > pow(tolerance, 4) else { degenerate += 1; continue }
            let sourceIDs = polygon.map(vertex).sorted()
            guard Set(sourceIDs).count == 3 else { degenerate += 1; continue }
            guard inputFaces.insert(FaceKey(a: sourceIDs[0], b: sourceIDs[1], c: sourceIDs[2])).inserted else {
                duplicates += 1; continue
            }
            // Sutherland–Hodgman clips intersecting faces, rather than dropping
            // an entire triangle merely because one vertex is outside the box.
            for axis in 0..<3 {
                polygon = clip(polygon, axis: axis, boundary: crop.minimum[axis], keepGreater: true)
                polygon = clip(polygon, axis: axis, boundary: crop.maximum[axis], keepGreater: false)
            }
            guard polygon.count >= 3 else { outside += 1; continue }
            for corner in 1..<(polygon.count-1) {
                let p = [polygon[0], polygon[corner], polygon[corner+1]]
                let cross = simd_cross(p[1]-p[0], p[2]-p[0])
                guard simd_length_squared(cross) > pow(tolerance, 4) else { degenerate += 1; continue }
                let ids = p.map(vertex)
                guard Set(ids).count == 3 else { degenerate += 1; continue }
                let sorted = ids.sorted()
                let key = FaceKey(a: sorted[0], b: sorted[1], c: sorted[2])
                guard faces.insert(key).inserted else { duplicates += 1; continue }
                indices += ids
            }
        }
        guard !indices.isEmpty else { throw ScanFailure.message("The crop removed the whole model. Widen the box; no saved geometry was changed.") }

        // Connect pieces through welded positions, including UV/normal seams.
        var parents = Array(vertices.indices)
        func root(_ value: Int) -> Int {
            var value = value
            while parents[value] != value {
                parents[value] = parents[parents[value]]
                value = parents[value]
            }
            return value
        }
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = root(Int(indices[i]))
            for j in 1...2 { let b = root(Int(indices[i+j])); parents[b] = a }
        }
        var areas: [Int: Double] = [:]
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = vertices[Int(indices[i])], b = vertices[Int(indices[i+1])], c = vertices[Int(indices[i+2])]
            areas[root(Int(indices[i])), default: 0] += Double(simd_length(simd_cross(b-a, c-a))) / 2
        }
        let largest = areas.keys.sorted().max { areas[$0]! < areas[$1]! }!
        let threshold = areas[largest]! * 0.01
        let kept = Set(areas.keys.filter { component in
            switch options.fragments {
            case .keepAll: return true
            case .removeSmall: return areas[component]! >= threshold
            case .largestOnly: return component == largest
            }
        })
        var filtered: [UInt32] = []
        for i in stride(from: 0, to: indices.count, by: 3) where kept.contains(root(Int(indices[i]))) {
            filtered.append(contentsOf: indices[i..<(i+3)])
        }
        // Compact unused vertices after cropping/filtering; recompute area-weighted normals.
        var compact: [SIMD3<Float>] = []
        var mapping: [UInt32: UInt32] = [:]
        let finalIndices = filtered.map { old -> UInt32 in
            if let index = mapping[old] { return index }
            let index = UInt32(compact.count)
            mapping[old] = index
            compact.append(vertices[Int(old)])
            return index
        }
        var normals = Array(repeating: SIMD3<Float>.zero, count: compact.count)
        for i in stride(from: 0, to: finalIndices.count, by: 3) {
            let a = Int(finalIndices[i]), b = Int(finalIndices[i+1]), c = Int(finalIndices[i+2])
            let n = simd_cross(compact[b]-compact[a], compact[c]-compact[a])
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        normals = normals.map { simd_length_squared($0) > 0 ? simd_normalize($0) : SIMD3(0,1,0) }
        let result = EditableMesh(vertices: compact, normals: normals, indices: finalIndices)
        try result.validate()
        let summary = """
        Triangles: \(source.triangleCount) → \(result.triangleCount).
        Removed: \(outside) fully outside faces, \(degenerate) degenerate faces, \(duplicates) duplicate faces, \(areas.count-kept.count) disconnected pieces.
        Crop minimum (meters): \(crop.minimum); maximum: \(crop.maximum).
        Loose pieces: \(options.fragments.title). Normals recalculated; source winding retained.
        Near-identical vertices welded within \(tolerance) meters. No smoothing, hole filling or caps; cut edges may remain open. Geometry only; original USDZ retained.
        """
        return MeshEditResult(mesh: result, summary: summary)
    }

    private static func clip(_ polygon: [SIMD3<Float>], axis: Int, boundary: Float, keepGreater: Bool) -> [SIMD3<Float>] {
        guard var previous = polygon.last else { return [] }
        var result: [SIMD3<Float>] = []
        func inside(_ p: SIMD3<Float>) -> Bool { keepGreater ? p[axis] >= boundary : p[axis] <= boundary }
        var wasInside = inside(previous)
        for current in polygon {
            let isInside = inside(current)
            if isInside != wasInside {
                let fraction = (boundary-previous[axis]) / (current[axis]-previous[axis])
                var p = previous + (current-previous) * fraction
                p[axis] = boundary
                result.append(p)
            }
            if isInside { result.append(current) }
            previous = current; wasInside = isInside
        }
        return result
    }
}
