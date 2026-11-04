import Foundation
import simd

struct LidarMeshPatch: Codable, Sendable {
    let id: UUID
    let revision: UUID
    let transform: [Float] // Column-major anchor-to-world matrix; coordinates in meters.
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
}

enum LidarMeshAssembly {
    static func vectors(_ data: Data, count: Int, offset: Int, stride: Int, requireFinite: Bool = true) throws -> [SIMD3<Float>] {
        guard count > 0, count <= 1_000_000, offset >= 0, stride >= 12, stride <= 4096,
              offset <= data.count, count <= (data.count-offset+stride-12)/stride else {
            throw ScanFailure.message("LiDAR vertex buffer is empty or truncated.")
        }
        return try data.withUnsafeBytes { bytes in
            try (0..<count).map { i in
                let start = offset + i * stride
                let v = SIMD3(bytes.loadUnaligned(fromByteOffset: start, as: Float.self),
                              bytes.loadUnaligned(fromByteOffset: start+4, as: Float.self),
                              bytes.loadUnaligned(fromByteOffset: start+8, as: Float.self))
                guard !requireFinite || finite(v) else { throw ScanFailure.message("LiDAR returned a nonfinite vertex or normal.") }
                return v
            }
        }
    }

    struct SanitizedPatch {
        let patch: LidarMeshPatch?
        let removedFaces: Int
        let invalidVertices: Int
    }

    /// Filter faces before touching a renderer or archive. Do not replace unknown
    /// positions with zero: that would invent spikes/geometry. Derive normals from
    /// retained triangles rather than depending on provisional ARKit normal buffers.
    static func sanitize(id: UUID, transform: [Float], vertices: [SIMD3<Float>], indices: [UInt32]) throws -> SanitizedPatch {
        guard transform.count == 16, transform.allSatisfy(\.isFinite), indices.count.isMultiple(of: 3),
              indices.allSatisfy({ Int($0) < vertices.count }) else {
            throw ScanFailure.message("Invalid LiDAR transform or triangle indices; update skipped.")
        }
        let linear = simd_float3x3(SIMD3(transform[0],transform[1],transform[2]),
                                  SIMD3(transform[4],transform[5],transform[6]), SIMD3(transform[8],transform[9],transform[10]))
        let determinant = simd_determinant(linear)
        guard determinant.isFinite, abs(determinant) > 1e-12 else {
            throw ScanFailure.message("Singular LiDAR anchor transform; update skipped.")
        }
        var points: [SIMD3<Float>] = []
        var faces: [UInt32] = []
        var mapping: [UInt32: UInt32] = [:]
        var removed = 0
        for i in stride(from: 0, to: indices.count, by: 3) {
            let ids = Array(indices[i..<(i+3)])
            let p = ids.map { vertices[Int($0)] }
            guard p.allSatisfy(finite), Set(ids).count == 3 else { removed += 1; continue }
            let cross = simd_cross(p[1]-p[0],p[2]-p[0])
            let length = simd_length(cross)
            guard finite(cross), length.isFinite, length > 1e-15 else { removed += 1; continue }
            for old in ids {
                if let index = mapping[old] { faces.append(index) }
                else {
                    let index = UInt32(points.count)
                    mapping[old] = index; points.append(vertices[Int(old)]); faces.append(index)
                }
            }
        }
        let invalid = vertices.filter { !finite($0) }.count
        guard !faces.isEmpty else { return SanitizedPatch(patch: nil, removedFaces: removed, invalidVertices: invalid) }
        var normals = Array(repeating: SIMD3<Float>.zero, count: points.count)
        for i in stride(from: 0, to: faces.count, by: 3) {
            let a = Int(faces[i]), b = Int(faces[i+1]), c = Int(faces[i+2])
            let n = simd_normalize(simd_cross(points[b]-points[a], points[c]-points[a]))
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        normals = normals.map {
            let length = simd_length($0)
            return length.isFinite && length > 1e-15 ? $0/length : SIMD3(0,1,0)
        }
        return SanitizedPatch(patch: LidarMeshPatch(id: id, revision: UUID(), transform: transform,
                                                   vertices: points, normals: normals, indices: faces),
                              removedFaces: removed, invalidVertices: invalid)
    }

    static func indices(_ data: Data, faceCount: Int, bytesPerIndex: Int, vertexCount: Int) throws -> [UInt32] {
        guard faceCount > 0, faceCount <= 1_000_000, [2,4].contains(bytesPerIndex),
              data.count >= faceCount * 3 * bytesPerIndex else { throw ScanFailure.message("LiDAR triangle buffer is empty or truncated.") }
        return try data.withUnsafeBytes { bytes in
            try (0..<(faceCount*3)).map { i in
                let index = bytesPerIndex == 2
                    ? UInt32(bytes.loadUnaligned(fromByteOffset: i*2, as: UInt16.self))
                    : bytes.loadUnaligned(fromByteOffset: i*4, as: UInt32.self)
                guard Int(index) < vertexCount else { throw ScanFailure.message("LiDAR returned an invalid triangle index.") }
                return index
            }
        }
    }

    static func combine(_ patches: [LidarMeshPatch]) throws -> EditableMesh {
        guard !patches.isEmpty, Set(patches.map(\.id)).count == patches.count else {
            throw ScanFailure.message("No valid saved LiDAR patches, or duplicate anchor IDs. Original files are retained.")
        }
        var result = EditableMesh(vertices: [], normals: [], indices: [])
        for patch in patches.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            try Task.checkCancellation()
            guard patch.transform.count == 16, patch.transform.allSatisfy(\.isFinite),
                  !patch.vertices.isEmpty, patch.normals.count == patch.vertices.count,
                  !patch.indices.isEmpty, patch.indices.count.isMultiple(of: 3),
                  patch.indices.allSatisfy({ Int($0) < patch.vertices.count }) else {
                throw ScanFailure.message("A saved LiDAR patch is invalid. Original files are retained.")
            }
            let m = patch.transform
            let transform = simd_float4x4(SIMD4(m[0],m[1],m[2],m[3]), SIMD4(m[4],m[5],m[6],m[7]),
                                         SIMD4(m[8],m[9],m[10],m[11]), SIMD4(m[12],m[13],m[14],m[15]))
            let linear = simd_float3x3(SIMD3(m[0],m[1],m[2]), SIMD3(m[4],m[5],m[6]), SIMD3(m[8],m[9],m[10]))
            let determinant = simd_determinant(linear)
            guard determinant.isFinite, abs(determinant) > 1e-12 else { throw ScanFailure.message("Invalid LiDAR anchor transform.") }
            let normalTransform = simd_transpose(simd_inverse(linear))
            let base = UInt32(result.vertices.count)
            for i in patch.vertices.indices {
                let v = patch.vertices[i]
                let p = transform * SIMD4(v.x,v.y,v.z,1)
                guard finite(v), p.w.isFinite, abs(p.w) > 1e-12 else { throw ScanFailure.message("Invalid LiDAR position.") }
                let world = SIMD3(p.x,p.y,p.z) / p.w
                let normal = normalTransform * patch.normals[i]
                guard finite(world), finite(normal) else { throw ScanFailure.message("Invalid transformed LiDAR geometry.") }
                result.vertices.append(world)
                result.normals.append(simd_length_squared(normal) > 1e-15 ? simd_normalize(normal) : SIMD3(0,1,0))
            }
            for i in stride(from: 0, to: patch.indices.count, by: 3) {
                let a = patch.indices[i]+base, b = patch.indices[i+1]+base, c = patch.indices[i+2]+base
                result.indices += determinant < 0 ? [a,c,b] : [a,b,c]
            }
        }
        try result.validate()
        return result
    }

    static func matrixValues(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in (0..<4).map { row in matrix[column][row] } }
    }

    private static func finite(_ v: SIMD3<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
}

/// Serial background persistence. A new index is committed only after all changed
/// patches are written. Updated anchors replace their previous revision, not append.
actor LidarArchive {
    let directory: URL
    init(directory: URL) { self.directory = directory }

    func save(_ patches: [LidarMeshPatch]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("index.json")
        let previous = manager.fileExists(atPath: indexURL.path)
            ? try JSONDecoder().decode([String: String].self, from: Data(contentsOf: indexURL)) : [:]
        var next: [String: String] = [:]
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        for patch in patches {
            let name = "\(patch.id.uuidString)-\(patch.revision.uuidString).plist"
            let url = directory.appendingPathComponent(name)
            if previous[patch.id.uuidString] != name || !manager.fileExists(atPath: url.path) {
                try encoder.encode(patch).write(to: url, options: .atomic)
            }
            next[patch.id.uuidString] = name
        }
        try JSONEncoder().encode(next).write(to: indexURL, options: .atomic)
        let retained = Set(next.values)
        for name in previous.values where !retained.contains(name) && safeName(name) {
            try? manager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func load() throws -> [LidarMeshPatch] {
        let index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: directory.appendingPathComponent("index.json")))
        return try index.keys.sorted().map { id in
            let name = index[id]!
            guard safeName(name) else { throw ScanFailure.message("Invalid saved LiDAR index path.") }
            let patch = try PropertyListDecoder().decode(LidarMeshPatch.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
            guard patch.id.uuidString == id, name == "\(patch.id.uuidString)-\(patch.revision.uuidString).plist" else {
                throw ScanFailure.message("Saved LiDAR anchor identity mismatch.")
            }
            return patch
        }
    }

    private func safeName(_ name: String) -> Bool {
        !name.contains("/") && !name.contains("\\") && name.hasSuffix(".plist") && !name.contains("..")
    }
}
