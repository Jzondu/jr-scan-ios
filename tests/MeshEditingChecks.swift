import Foundation
import simd

enum MeshEditingChecks {
    static func run(in directory: URL) throws {
        let source = EditableMesh(vertices: [
            SIMD3(-1,-1,0), SIMD3(1,-1,0), SIMD3(1,1,0), SIMD3(-1,1,0),
            SIMD3(3,0,0), SIMD3(3.01,0,0), SIMD3(3,0.01,0),
            SIMD3(-1,-1,0), SIMD3(1,-1,0), SIMD3(1,1,0)
        ], normals: [], indices: [0,1,2, 0,2,3, 8,9,7, 0,0,1, 4,5,6])
        let originalVertices = source.vertices
        let originalIndices = source.indices
        var options = MeshEditOptions()
        let clean = try MeshEditing.apply(source, options: options)
        try GeometryChecks.require(clean.mesh.triangleCount == 2, "Cleanup must remove cyclic duplicate, degenerate and tiny disconnected piece")
        try GeometryChecks.require(source.vertices == originalVertices && source.indices == originalIndices, "Editing mutated source geometry")
        options.fragments = .keepAll
        let all = try MeshEditing.apply(source, options: options)
        try GeometryChecks.require(all.mesh.triangleCount == 3, "Keep-all must retain an intentional disconnected piece")
        options.fragments = .largestOnly
        let largest = try MeshEditing.apply(source, options: options)
        try GeometryChecks.require(largest.mesh.triangleCount == 2, "Largest component selection failed")

        options.fragments = .removeSmall
        options.lower.x = (0-source.bounds.minimum.x) / source.bounds.extent.x
        let cropped = try MeshEditing.apply(source, options: options)
        try GeometryChecks.require(abs(cropped.mesh.bounds.minimum.x) < 1e-6, "Crossing triangles must be clipped at X=0")
        try GeometryChecks.require(abs(area(cropped.mesh)-2) < 1e-5, "Clipping lost intersecting triangle area or retained duplicate overlap")
        try GeometryChecks.require(cropped.mesh.normals.allSatisfy { $0.z > 0.999 && abs(simd_length($0)-1) < 1e-5 }, "Cleaned normals disagree with surface winding")
        let output = directory.appendingPathComponent("edited-meters.obj")
        try cropped.mesh.writeOBJ(output)
        let summary = try OBJExporter.validate(output)
        try GeometryChecks.require(summary.triangles == cropped.mesh.triangleCount, "Edited OBJ export lost faces")
        let reloaded = try EditableMesh.load(output)
        try GeometryChecks.require(abs(area(reloaded)-2) < 1e-5, "Saved edit reload changed geometry")

        // Clipping on both X and Y must retain a unit square of the original surface.
        options.lower.y = 0.25
        options.upper.y = 0.75
        let box = try MeshEditing.apply(source, options: options)
        try GeometryChecks.require(abs(area(box.mesh)-1) < 1e-5, "Multi-plane clipping has incorrect surface area")
        options.lower.x = 0.75; options.upper.x = 0.85
        options.lower.y = 0.8; options.upper.y = 0.9
        do {
            _ = try MeshEditing.apply(source, options: options)
            throw ScanFailure.message("TEST FAILED: empty crop accepted")
        } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}
        print("PASS: precise crop area, multi-plane clipping, seam welding, duplicate/degenerate removal, fragment policies, normals, source preservation, edited OBJ reload and empty-crop rejection")
    }

    static func area(_ mesh: EditableMesh) -> Float {
        var area: Float = 0
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let a = mesh.vertices[Int(mesh.indices[i])], b = mesh.vertices[Int(mesh.indices[i+1])], c = mesh.vertices[Int(mesh.indices[i+2])]
            area += simd_length(simd_cross(b-a,c-a)) / 2
        }
        return area
    }
}
