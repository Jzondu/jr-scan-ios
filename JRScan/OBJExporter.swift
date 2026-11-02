import Foundation
import ModelIO
import simd

enum ExportUnits: String, CaseIterable, Identifiable {
    case meters, millimeters
    var id: String { rawValue }
    var multiplier: Float { self == .meters ? 1 : 1000 }
}

enum ScanFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

/// Uses Model I/O for import and OBJ encoding. All hierarchy transforms are baked
/// into new triangle buffers, so export does not depend on an OBJ reader's scene support.
enum OBJExporter {
    struct Summary {
        let vertices: Int
        let triangles: Int
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
    }

    static func convert(source: URL, destination: URL, units: ExportUnits) throws -> Summary {
        guard MDLAsset.canImportFileExtension(source.pathExtension), MDLAsset.canExportFileExtension("obj") else {
            throw ScanFailure.message("Model I/O cannot convert this model to OBJ on this OS. The original is retained.")
        }
        let input = MDLAsset(url: source)
        let output = try flattened(input, units: units)
        try output.export(to: destination)
        return try validate(destination)
    }

    static func flattened(_ input: MDLAsset, units: ExportUnits) throws -> MDLAsset {
        let output = MDLAsset()
        let meshes = input.childObjects(of: MDLMesh.self).compactMap { $0 as? MDLMesh }
        var totalTriangles = 0
        for (meshNumber, mesh) in meshes.enumerated() {
            guard mesh.vertexCount > 0,
                  let positions = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3),
                  let submeshes = mesh.submeshes as? [MDLSubmesh], !submeshes.isEmpty else {
                throw ScanFailure.message("A model mesh has missing geometry; export was stopped to avoid dropping it.")
            }
            let transform = MDLTransform.globalTransform(with: mesh, atTime: input.startTime)
            let linear = simd_float3x3(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
                                      SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
                                      SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            let determinant = simd_determinant(linear)
            guard determinant.isFinite, abs(determinant) > 1e-12 else {
                throw ScanFailure.message("A model transform is singular. Original retained; OBJ was not exported.")
            }
            let normalMatrix = simd_transpose(simd_inverse(linear))
            let sourceNormals = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3)
            var vertices: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            for index in 0..<mesh.vertexCount {
                let p = readVector(positions, index: index)
                let world = transform * SIMD4(p.x, p.y, p.z, 1)
                guard world.w.isFinite, abs(world.w) > 1e-12 else { throw ScanFailure.message("Invalid vertex transform.") }
                let v = SIMD3(world.x, world.y, world.z) / world.w * units.multiplier
                guard finite(v) else { throw ScanFailure.message("Nonfinite vertex in reconstructed model.") }
                vertices.append(v)
                if let sourceNormals {
                    let n = normalMatrix * readVector(sourceNormals, index: index)
                    normals.append(finite(n) && simd_length_squared(n) > 1e-15 ? simd_normalize(n) : .zero)
                }
            }
            var triangles: [UInt32] = []
            for submesh in submeshes {
                let buffer = submesh.indexBuffer(asIndexType: .uInt32)
                guard buffer.length >= submesh.indexCount * MemoryLayout<UInt32>.size else {
                    throw ScanFailure.message("Model index buffer is truncated.")
                }
                let map = buffer.map()
                let indices = map.bytes.assumingMemoryBound(to: UInt32.self)
                func append(_ a: UInt32, _ b: UInt32, _ c: UInt32) throws {
                    guard [a,b,c].allSatisfy({ Int($0) < vertices.count }) else {
                        throw ScanFailure.message("Model contains invalid triangle indices.")
                    }
                    // Reflection changes handedness; reverse face winding with transformed normals.
                    triangles.append(contentsOf: determinant < 0 ? [a,c,b] : [a,b,c])
                }
                switch submesh.geometryType {
                case .triangles:
                    guard submesh.indexCount.isMultiple(of: 3) else { throw ScanFailure.message("Incomplete triangle indices.") }
                    for i in stride(from: 0, to: submesh.indexCount, by: 3) {
                        try append(indices[i], indices[i+1], indices[i+2])
                    }
                case .quads:
                    guard submesh.indexCount.isMultiple(of: 4) else { throw ScanFailure.message("Incomplete quad indices.") }
                    for i in stride(from: 0, to: submesh.indexCount, by: 4) {
                        try append(indices[i], indices[i+1], indices[i+2])
                        try append(indices[i], indices[i+2], indices[i+3])
                    }
                case .triangleStrips:
                    if submesh.indexCount >= 3 {
                        for i in 2..<submesh.indexCount {
                            let a = indices[i-2], b = indices[i-1], c = indices[i]
                            if a != b && b != c && a != c {
                                try append(i.isMultiple(of: 2) ? a : b, i.isMultiple(of: 2) ? b : a, c)
                            }
                        }
                    }
                default:
                    throw ScanFailure.message("Unsupported mesh topology. Original retained; no partial OBJ substituted.")
                }
            }
            guard !triangles.isEmpty else { throw ScanFailure.message("A model mesh has no triangles.") }
            if normals.count != vertices.count || normals.contains(where: { simd_length_squared($0) < 1e-15 }) {
                normals = Array(repeating: .zero, count: vertices.count)
                for i in stride(from: 0, to: triangles.count, by: 3) {
                    let a = Int(triangles[i]), b = Int(triangles[i+1]), c = Int(triangles[i+2])
                    let n = simd_cross(vertices[b]-vertices[a], vertices[c]-vertices[a])
                    normals[a] += n; normals[b] += n; normals[c] += n
                }
                normals = normals.map { simd_length_squared($0) > 1e-15 ? simd_normalize($0) : SIMD3(0,1,0) }
            }
            var packed: [Float] = []
            for i in vertices.indices {
                packed.append(contentsOf: [vertices[i].x,vertices[i].y,vertices[i].z,normals[i].x,normals[i].y,normals[i].z])
            }
            let vertexData = packed.withUnsafeBytes { Data($0) }
            let indexData = triangles.withUnsafeBytes { Data($0) }
            let descriptor = MDLVertexDescriptor()
            descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
            descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
            descriptor.layouts[0] = MDLVertexBufferLayout(stride: 24)
            let submesh = MDLSubmesh(indexBuffer: MDLMeshBufferData(type: .index, data: indexData),
                                    indexCount: triangles.count, indexType: .uInt32, geometryType: .triangles, material: nil)
            let flattened = MDLMesh(vertexBuffer: MDLMeshBufferData(type: .vertex, data: vertexData),
                                    vertexCount: vertices.count, descriptor: descriptor, submeshes: [submesh])
            flattened.name = "mesh_\(meshNumber)"
            output.add(flattened)
            totalTriangles += triangles.count / 3
        }
        guard totalTriangles > 0 else { throw ScanFailure.message("No triangle mesh was found. Original model retained.") }
        return output
    }

    static func validate(_ url: URL) throws -> Summary {
        let text = try String(contentsOf: url, encoding: .utf8)
        var vertices: [SIMD3<Float>] = []
        var normals = 0
        var faces: [[(Int, Int?)]] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard let first = parts.first else { continue }
            if first == "v" {
                guard parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]),
                      finite(SIMD3(x,y,z)) else { throw ScanFailure.message("OBJ contains an invalid vertex.") }
                vertices.append(SIMD3(x,y,z))
            } else if first == "vn" {
                guard parts.count >= 4, let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]),
                      finite(SIMD3(x,y,z)) else { throw ScanFailure.message("OBJ contains an invalid normal.") }
                normals += 1
            } else if first == "f" {
                guard parts.count == 4 else { throw ScanFailure.message("OBJ output is not triangulated.") }
                var face: [(Int,Int?)] = []
                for component in parts.dropFirst() {
                    let fields = component.split(separator: "/", omittingEmptySubsequences: false)
                    guard let index = Int(fields[0]) else { throw ScanFailure.message("Invalid OBJ index.") }
                    let normal = fields.count >= 3 ? Int(fields[2]) : nil
                    face.append((index,normal))
                }
                faces.append(face)
            }
        }
        guard !vertices.isEmpty, !faces.isEmpty else { throw ScanFailure.message("OBJ conversion produced empty geometry.") }
        for face in faces {
            for (v,n) in face {
                guard v > 0, v <= vertices.count, let n, n > 0, n <= normals else {
                    throw ScanFailure.message("OBJ contains missing normals or invalid indices.")
                }
            }
        }
        let minimum = vertices.reduce(SIMD3<Float>(repeating: .infinity), simd_min)
        let maximum = vertices.reduce(SIMD3<Float>(repeating: -.infinity), simd_max)
        return Summary(vertices: vertices.count, triangles: faces.count, minimum: minimum, maximum: maximum)
    }

    private static func readVector(_ attribute: MDLVertexAttributeData, index: Int) -> SIMD3<Float> {
        let p = attribute.dataStart.advanced(by: index * attribute.stride)
        return SIMD3(p.loadUnaligned(as: Float.self), p.advanced(by: 4).loadUnaligned(as: Float.self),
                     p.advanced(by: 8).loadUnaligned(as: Float.self))
    }
    private static func finite(_ v: SIMD3<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
}
