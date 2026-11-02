import Foundation
import ModelIO
import simd
import Darwin

@main
struct GeometryChecks {
    static func main() throws {
        setbuf(stdout, nil)
        let inner = NSError(domain: "Test.Underlying", code: 19, userInfo: [NSLocalizedDescriptionKey: "Input failed", "PhotoPayload": Data([1,2,3])])
        let failure = NSError(domain: "CoreOC.PhotogrammetrySession.Error", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: "Reconstruction failed", NSUnderlyingErrorKey: inner,
                                         "AccountSecret": "DO_NOT_LOG_THIS"])
        let report = ReconstructionFailure.details(failure, stage: "imageAlignment")
        try require(report.contains("CoreOC.PhotogrammetrySession.Error (6)") && report.contains("Test.Underlying (19)"), "Error domain/code chain is missing")
        try require(!report.contains("DO_NOT_LOG_THIS") && !report.contains("PhotoPayload"), "Arbitrary error userInfo leaked into diagnostic text")
        print("PASS: failure domain/code/underlying chain captured without arbitrary userInfo payloads")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JRScan-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let asset = MDLAsset()
        let parent = MDLObject()
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4(-2,3,4,1)
        parent.transform = MDLTransform(matrix: translation)
        let mesh = fixture()
        var scale = matrix_identity_float4x4
        scale.columns.0.x = -2
        scale.columns.1.y = 3
        scale.columns.2.z = 4
        mesh.transform = MDLTransform(matrix: scale)
        parent.addChild(mesh)
        asset.add(parent)

        let meters = try OBJExporter.flattened(asset, units: .meters)
        let millimeters = try OBJExporter.flattened(asset, units: .millimeters)
        let m = directory.appendingPathComponent("meters.obj")
        let mm = directory.appendingPathComponent("millimeters.obj")
        try meters.export(to: m)
        try millimeters.export(to: mm)
        let a = try OBJExporter.validate(m)
        let b = try OBJExporter.validate(mm)
        try require(a.triangles == 1 && b.triangles == 1, "Expected one triangle in each unit export")
        try require(simd_length(a.minimum - SIMD3(-4,3,4)) < 0.0001, "Parent/mesh transforms were not correctly baked")
        try require(simd_length(a.maximum - SIMD3(-2,6,8)) < 0.0001, "Expected transformed bounds")
        try require(simd_length(b.minimum - a.minimum * 1000) < 0.01, "Millimeter minimum must be 1000x meters")
        try require(simd_length(b.maximum - a.maximum * 1000) < 0.01, "Millimeter maximum must be 1000x meters")
        try checkWindingAndNormals(m)
        print("PASS: nested transform, reflected winding, inverse-transpose normals, triangle topology and 1000x unit conversion")

        let empty = MDLAsset()
        do {
            _ = try OBJExporter.flattened(empty, units: .meters)
            throw ScanFailure.message("TEST FAILED: empty model accepted")
        } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}
        let malformed = directory.appendingPathComponent("malformed.obj")
        try "v 0 0 0\nvn 0 0 1\nf 1//1 2//1 99//1\n".write(to: malformed, atomically: true, encoding: .utf8)
        do {
            _ = try OBJExporter.validate(malformed)
            throw ScanFailure.message("TEST FAILED: out-of-range face accepted")
        } catch ScanFailure.message(let text) where !text.hasPrefix("TEST FAILED") {}
        print("PASS: empty geometry and invalid OBJ indices are rejected")

        // Exercise actual USDZ import -> Model I/O normalization -> OBJ encoding, not only in-memory buffers.
        guard CommandLine.arguments.count == 2 else { throw ScanFailure.message("TEST FAILED: provide generated USDZ fixture") }
        let usdz = URL(fileURLWithPath: CommandLine.arguments[1])
        let converted = try OBJExporter.convert(source: usdz, destination: directory.appendingPathComponent("converted.obj"), units: .meters)
        try require(converted.triangles == 1, "USDZ import lost geometry")
        try require(simd_length(converted.minimum - a.minimum) < 0.0001, "USDZ import changed coordinate bounds")
        try checkWindingAndNormals(directory.appendingPathComponent("converted.obj"))
        print("PASS: USDZ -> geometry OBJ import/export")
    }

    static func fixture() -> MDLMesh {
        let n = simd_normalize(SIMD3<Float>(0,-1,1))
        let data: [Float] = [0,0,0,n.x,n.y,n.z, 1,0,0,n.x,n.y,n.z, 0,1,1,n.x,n.y,n.z]
        let indices: [UInt32] = [0,1,2]
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 24)
        let submesh = MDLSubmesh(indexBuffer: MDLMeshBufferData(type: .index, data: indices.withUnsafeBytes { Data($0) }),
                                indexCount: 3, indexType: .uInt32, geometryType: .triangles, material: nil)
        return MDLMesh(vertexBuffer: MDLMeshBufferData(type: .vertex, data: data.withUnsafeBytes { Data($0) }),
                       vertexCount: 3, descriptor: descriptor, submeshes: [submesh])
    }

    static func checkWindingAndNormals(_ url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var face: [(Int,Int)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            if words.first == "v" { vertices.append(SIMD3(Float(words[1])!,Float(words[2])!,Float(words[3])!)) }
            if words.first == "vn" { normals.append(SIMD3(Float(words[1])!,Float(words[2])!,Float(words[3])!)) }
            if words.first == "f" {
                face = words.dropFirst().map {
                    let fields = $0.split(separator: "/", omittingEmptySubsequences: false)
                    return (Int(fields[0])!-1, Int(fields[2])!-1)
                }
            }
        }
        try require(face.count == 3, "Expected triangle face")
        let cross = simd_normalize(simd_cross(vertices[face[1].0]-vertices[face[0].0], vertices[face[2].0]-vertices[face[0].0]))
        let expected = simd_normalize(SIMD3<Float>(0,-1.0/3,1.0/4))
        for (_, index) in face {
            try require(simd_dot(normals[index], cross) > 0.999, "Reflection winding and normals disagree")
            try require(simd_length(normals[index]-expected) < 0.0001, "Normal requires inverse-transpose transform")
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ScanFailure.message("TEST FAILED: \(message)") }
    }
}
