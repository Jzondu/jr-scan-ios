import Foundation
import simd

enum PartGeometryChecks {
    static func run(in directory: URL) throws {
        let oldManifest = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Saved part","created":0,"updated":0,"stage":"completed","captureFinished":true,"modelName":"part.obj","captureKind":"lidar"}
        """
        let old = try JSONDecoder().decode(ScanRecord.self, from: Data(oldManifest.utf8))
        try GeometryChecks.require(old.modelName == "part.obj" && old.captureKind == "lidar" && old.passesStarted == nil && old.depthSummary == nil, "Old LiDAR manifest no longer decodes")
        let photoManifest = oldManifest.replacingOccurrences(of: ",\"captureKind\":\"lidar\"", with: "")
        let photo = try JSONDecoder().decode(ScanRecord.self, from: Data(photoManifest.utf8))
        try GeometryChecks.require(photo.captureKind == nil, "Legacy photo scan no longer decodes")
        var combined = photo
        combined.captureKind = "combined"; combined.passesStarted = 3; combined.referenceScanID = old.id
        let reloaded = try JSONDecoder().decode(ScanRecord.self, from: JSONEncoder().encode(combined))
        try GeometryChecks.require(reloaded.passesStarted == 3 && reloaded.referenceScanID == old.id, "Combined scan metadata did not persist")
        print("PASS: legacy photo/LiDAR manifests and combined scan metadata round trip")
        // Closed tetrahedron with consistent outward winding, 10 mm edges on axes.
        let mesh = EditableMesh(vertices: [SIMD3(0,0,0),SIMD3(0.01,0,0),SIMD3(0,0.01,0),SIMD3(0,0,0.01)],
            normals: Array(repeating: SIMD3(0,0,1), count: 4), indices: [0,2,1, 0,1,3, 0,3,2, 1,2,3])
        let closed = try PartGeometry.report(mesh)
        try GeometryChecks.require(closed.boundaryEdges == 0 && closed.nonManifoldEdges == 0 && closed.windingConflicts == 0, "Closed tetrahedron edge report failed")
        var open = mesh
        open.indices = Array(mesh.indices.dropLast(3))
        try GeometryChecks.require(try PartGeometry.report(open).boundaryEdges == 3, "Missing face did not report 3 boundary edges")
        var reversed = mesh
        reversed.indices.swapAt(1,2)
        try GeometryChecks.require(try PartGeometry.report(reversed).windingConflicts == 3, "Reversed face winding was not detected")
        var duplicate = mesh
        duplicate.indices += [0,2,1]
        try GeometryChecks.require(try PartGeometry.report(duplicate).nonManifoldEdges == 3, "Non-manifold edges not detected")
        // Importers can split vertices at normal seams; exact positional seams must join.
        let seams = EditableMesh(vertices: mesh.indices.map { mesh.vertices[Int($0)] },
            normals: Array(repeating: SIMD3(0,0,1), count: mesh.indices.count), indices: (0..<UInt32(mesh.indices.count)).map { $0 })
        try GeometryChecks.require(try PartGeometry.report(seams).boundaryEdges == 0, "Normal seams misreported as holes")
        let factor = try PartGeometry.scaleFactor(measuredMeters: 0.01, referenceMM: 20)
        try GeometryChecks.require(abs(factor-2) < 1e-6, "Reference calibration scale incorrect")
        let scaled = try PartGeometry.transform(mesh, scale: factor)
        try GeometryChecks.require(simd_length(scaled.bounds.extent-SIMD3(repeating: 0.02)) < 1e-6, "Uniform scaling did not double dimensions")
        try GeometryChecks.require(mesh.bounds.extent.x == 0.01 && scaled.revision != mesh.revision, "Transform mutated source or reused preview revision")
        let rotated = try PartGeometry.transform(scaled, quarterTurnAxis: 0, placeOnBed: true)
        try GeometryChecks.require(abs(rotated.bounds.minimum.z) < 1e-7 && abs(rotated.bounds.center.x) < 1e-7 && abs(rotated.bounds.center.y) < 1e-7, "Z-up bed placement failed")
        try GeometryChecks.require(simd_distance(rotated.normals[0],SIMD3(0,-1,0)) < 1e-6 && rotated.indices == mesh.indices, "Rotation changed winding or failed to rotate normals")
        for length in [Float(0), -1, .nan, .infinity] {
            do {
                _ = try PartGeometry.scaleFactor(measuredMeters: 0.01, referenceMM: length)
                throw ScanFailure.message("TEST FAILED: invalid reference accepted")
            } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}
        }
        let output = directory.appendingPathComponent("part-mm.stl")
        try PartGeometry.writeSTL(mesh, to: output)
        let bytes = try Data(contentsOf: output)
        try GeometryChecks.require(bytes.count == 284, "Binary STL size incorrect")
        let count = bytes.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self)) }
        try GeometryChecks.require(count == 4, "STL triangle count incorrect")
        var invalid = mesh
        invalid.indices = [0,0,1]
        do {
            try PartGeometry.writeSTL(invalid, to: directory.appendingPathComponent("invalid.stl"))
            throw ScanFailure.message("TEST FAILED: degenerate STL accepted")
        } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}
        try GeometryChecks.require(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("invalid.stl").path), "Rejected STL was published")
        for face in 0..<4 {
            var points: [SIMD3<Float>] = []
            for corner in 0..<3 {
                let start = 84+face*50+12+corner*12
                let p: SIMD3<Float> = bytes.withUnsafeBytes { buffer in
                    SIMD3((0..<3).map { axis in Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: start+axis*4, as: UInt32.self))) })
                }
                try GeometryChecks.require(simd_distance(p,mesh.vertices[Int(mesh.indices[face*3+corner])]*1000) < 1e-5, "STL millimeter conversion/order incorrect")
                points.append(p)
            }
            let normal: SIMD3<Float> = bytes.withUnsafeBytes { buffer in
                SIMD3((0..<3).map { axis in Float(bitPattern: UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: 84+face*50+axis*4, as: UInt32.self))) })
            }
            try GeometryChecks.require(simd_dot(normal,simd_normalize(simd_cross(points[1]-points[0],points[2]-points[0]))) > 0.999, "STL normal/winding mismatch")
        }
        print("PASS: part dimensions/calibration, immutable rotation/bed placement, boundary/non-manifold/winding/seam checks and binary STL layout/mm coordinates/normals")
    }
}
