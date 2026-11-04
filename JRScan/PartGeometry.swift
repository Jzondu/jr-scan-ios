import Foundation
import simd

struct PartReport: Sendable {
    let boundaryEdges: Int
    let nonManifoldEdges: Int
    let windingConflicts: Int
    let degenerateFaces: Int
    var text: String {
        "Open edges: \(boundaryEdges) • Non-manifold edges: \(nonManifoldEdges) • Winding conflicts: \(windingConflicts) • Degenerate faces: \(degenerateFaces). Edge checks do not detect self-intersections or guarantee printability."
    }
}

enum PartGeometry {
    private struct Edge: Hashable { let a: Int; let b: Int }
    // Collapse exactly coincident positions for analysis, without modifying the mesh.
    static func report(_ mesh: EditableMesh) throws -> PartReport {
        try mesh.validate()
        var positions: [SIMD3<Float>: Int] = [:]
        let ids = mesh.vertices.map { p -> Int in
            if let id = positions[p] { return id }
            let id = positions.count; positions[p] = id; return id
        }
        var edges: [Edge: (count: Int, direction: Int)] = [:]
        var degenerate = 0
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            if i.isMultiple(of: 3000) { try Task.checkCancellation() }
            let v = (0..<3).map { Int(mesh.indices[i+$0]) }
            let p = v.map { mesh.vertices[$0] }
            if simd_length(simd_cross(p[1]-p[0], p[2]-p[0])) <= 1e-15 { degenerate += 1 }
            for j in 0..<3 {
                let a = ids[v[j]], b = ids[v[(j+1)%3]]
                let edge = Edge(a: min(a,b), b: max(a,b))
                let old = edges[edge] ?? (0,0)
                edges[edge] = (old.count+1, old.direction + (a < b ? 1 : -1))
            }
        }
        return PartReport(boundaryEdges: edges.values.filter { $0.count == 1 }.count,
            nonManifoldEdges: edges.values.filter { $0.count > 2 }.count,
            windingConflicts: edges.values.filter { $0.count == 2 && $0.direction != 0 }.count,
            degenerateFaces: degenerate)
    }

    static func scaleFactor(measuredMeters: Float, referenceMM: Float) throws -> Float {
        let factor = referenceMM / (measuredMeters * 1000)
        guard measuredMeters.isFinite, measuredMeters > 1e-8, referenceMM.isFinite, referenceMM > 0,
              factor.isFinite, (0.001...1000).contains(factor) else {
            throw ScanFailure.message("Enter a positive reference length and select a nonzero distance. Allowed scale factor: 0.001–1000.")
        }
        return factor
    }

    static func transform(_ mesh: EditableMesh, scale: Float = 1, quarterTurnAxis: Int? = nil,
                          placeOnBed: Bool = false) throws -> EditableMesh {
        try mesh.validate()
        guard scale.isFinite, (0.001...1000).contains(scale),
              quarterTurnAxis == nil || (0..<3).contains(quarterTurnAxis!) else {
            throw ScanFailure.message("Invalid part transform.")
        }
        let rotation: simd_quatf
        if let axis = quarterTurnAxis {
            var direction = SIMD3<Float>.zero; direction[axis] = 1
            rotation = simd_quatf(angle: .pi/2, axis: direction)
        } else { rotation = simd_quatf(angle: 0, axis: SIMD3(0,1,0)) }
        let center = mesh.bounds.center
        var result = EditableMesh(vertices: mesh.vertices.map { rotation.act(($0-center)*scale) + center },
                                  normals: mesh.normals.map { rotation.act($0) }, indices: mesh.indices)
        if placeOnBed {
            let b = result.bounds
            let shift = SIMD3(b.center.x, b.center.y, b.minimum.z)
            result.vertices = result.vertices.map { $0-shift }
        }
        try result.validate()
        return result
    }

    /// Binary STL coordinates are explicitly millimeters; normals derived per face.
    static func writeSTL(_ mesh: EditableMesh, to url: URL) throws {
        try mesh.validate()
        guard mesh.triangleCount <= Int(UInt32.max) else { throw ScanFailure.message("Too many triangles for STL.") }
        var data = Data("JR Scan | millimeters | geometry only".utf8)
        data.append(Data(repeating: 0, count: 80-data.count))
        func append<T>(_ value: T) { var v = value; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        append(UInt32(mesh.triangleCount).littleEndian)
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            if i.isMultiple(of: 3000) { try Task.checkCancellation() }
            let p = (0..<3).map { mesh.vertices[Int(mesh.indices[i+$0])] * 1000 }
            let cross = simd_cross(p[1]-p[0], p[2]-p[0])
            let length = simd_length(cross)
            guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }), length.isFinite, length > 1e-15 else {
                throw ScanFailure.message("STL contains a degenerate or invalid face. Use Crop & clean mesh first.")
            }
            for v in [cross/length] + p { for axis in 0..<3 { append(v[axis].bitPattern.littleEndian) } }
            append(UInt16(0))
        }
        guard data.count == 84 + 50 * mesh.triangleCount else { throw ScanFailure.message("Invalid STL length.") }
        try data.write(to: url, options: .atomic)
    }
}
