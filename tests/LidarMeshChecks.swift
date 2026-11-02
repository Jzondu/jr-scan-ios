import Foundation
import simd

enum LidarMeshChecks {
    static func run(in directory: URL) async throws {
        var packed = Data(repeating: 0, count: 8)
        let first: [Float] = [1,2,3], second: [Float] = [4,5,6]
        packed.append(first.withUnsafeBytes { Data($0) })
        packed.append(Data(repeating: 0, count: 4))
        packed.append(second.withUnsafeBytes { Data($0) })
        let decoded = try LidarMeshAssembly.vectors(packed, count: 2, offset: 8, stride: 16)
        try GeometryChecks.require(decoded == [SIMD3(1,2,3),SIMD3(4,5,6)], "LiDAR buffer offset/stride was ignored")
        let shortIndices: [UInt16] = [0,1,2]
        let longIndices: [UInt32] = [0,2,1]
        let short = try LidarMeshAssembly.indices(shortIndices.withUnsafeBytes { Data($0) }, faceCount: 1, bytesPerIndex: 2, vertexCount: 3)
        let long = try LidarMeshAssembly.indices(longIndices.withUnsafeBytes { Data($0) }, faceCount: 1, bytesPerIndex: 4, vertexCount: 3)
        try GeometryChecks.require(short == [0,1,2] && long == [0,2,1], "LiDAR 16/32-bit index decoding failed")
        do {
            _ = try LidarMeshAssembly.vectors(Data(count: 11), count: 1, offset: 0, stride: 12)
            throw ScanFailure.message("TEST FAILED: truncated LiDAR positions accepted")
        } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}
        do {
            _ = try LidarMeshAssembly.indices(longIndices.withUnsafeBytes { Data($0) }, faceCount: 1, bytesPerIndex: 4, vertexCount: 2)
            throw ScanFailure.message("TEST FAILED: invalid LiDAR face index accepted")
        } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}

        var aTransform = matrix_identity_float4x4
        aTransform.columns.3 = SIMD4(1,0,0,1)
        var bTransform = matrix_identity_float4x4
        bTransform.columns.0 = SIMD4(0,1,0,0)
        bTransform.columns.1 = SIMD4(-1,0,0,0)
        bTransform.columns.3 = SIMD4(0,3,0,1)
        let aID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let a = patch(id: aID, transform: aTransform), b = patch(id: bID, transform: bTransform)
        let combined = try LidarMeshAssembly.combine([b,a])
        try GeometryChecks.require(combined.triangleCount == 2 && combined.indices == [0,1,2,3,4,5], "LiDAR anchor combination failed to offset indices")
        try GeometryChecks.require(simd_length(combined.bounds.minimum - SIMD3(-1,0,0)) < 1e-6 &&
                                   simd_length(combined.bounds.maximum - SIMD3(2,4,0)) < 1e-6, "LiDAR anchor-to-world rotation/translation missing")
        var reflection = matrix_identity_float4x4
        reflection.columns.0.x = -2
        reflection.columns.1.y = 3
        let reflected = try LidarMeshAssembly.combine([patch(id: aID, transform: reflection)])
        let i = reflected.indices.map { Int($0) }
        let cross = simd_normalize(simd_cross(reflected.vertices[i[1]]-reflected.vertices[i[0]], reflected.vertices[i[2]]-reflected.vertices[i[0]]))
        try GeometryChecks.require(simd_dot(cross, reflected.normals[i[0]]) > 0.999, "LiDAR reflection winding is inconsistent with normals")
        let output = directory.appendingPathComponent("lidar-meters.obj")
        try combined.writeOBJ(output)
        let summary = try OBJExporter.validate(output)
        try GeometryChecks.require(summary.triangles == 2, "LiDAR OBJ lost an anchor's geometry")

        let archiveDirectory = directory.appendingPathComponent("RawLiDAR")
        let archive = LidarArchive(directory: archiveDirectory)
        try await archive.save([a,b])
        let initial = try await archive.load()
        try GeometryChecks.require(initial.count == 2, "LiDAR checkpoint did not retain both patches")
        aTransform.columns.3.x = 5
        let updated = patch(id: aID, transform: aTransform)
        try await archive.save([updated]) // update A, remove B: no duplicate/stale geometry.
        let recovered = try await LidarArchive(directory: archiveDirectory).load()
        let recoveredMesh = try LidarMeshAssembly.combine(recovered)
        try GeometryChecks.require(recovered.count == 1 && recovered[0].revision == updated.revision && recoveredMesh.bounds.minimum.x == 5,
                                   "LiDAR recovery restored a stale/duplicate anchor")
        let files = try FileManager.default.contentsOfDirectory(at: archiveDirectory, includingPropertiesForKeys: nil)
        try GeometryChecks.require(files.filter { $0.pathExtension == "plist" }.count == 1, "Old LiDAR patch revisions were not retired after index commit")
        print("PASS: LiDAR offset/stride, 16/32-bit indices, truncated-buffer rejection, world transforms, reflected normals/winding, multi-anchor OBJ, checkpoint persistence, anchor replacement/removal and recovery")
    }

    static func patch(id: UUID, transform: simd_float4x4) -> LidarMeshPatch {
        LidarMeshPatch(id: id, revision: UUID(), transform: LidarMeshAssembly.matrixValues(transform),
                       vertices: [SIMD3(0,0,0),SIMD3(1,0,0),SIMD3(0,1,0)],
                       normals: Array(repeating: SIMD3(0,0,1), count: 3), indices: [0,1,2])
    }
}
