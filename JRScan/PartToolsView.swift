import SwiftUI
import simd
import UIKit

@MainActor
final class PartTools: ObservableObject {
    @Published var mesh: EditableMesh?
    @Published var report: PartReport?
    @Published var working = false
    @Published var error: String?
    @Published var changes: [String] = []
    private var original: EditableMesh?
    private var originalReport: PartReport?

    func load(_ url: URL) async {
        guard mesh == nil else { return }
        working = true
        defer { working = false }
        do {
            let pair = try await Task.detached(priority: .userInitiated) {
                let m = try EditableMesh.load(url)
                return (m, try PartGeometry.report(m))
            }.value
            mesh = pair.0; original = pair.0; report = pair.1; originalReport = pair.1
        } catch { self.error = error.localizedDescription }
    }

    func transform(scale: Float = 1, axis: Int? = nil, bed: Bool = false, note: String) async {
        guard let mesh, !working else { return }
        working = true; error = nil
        defer { working = false }
        do {
            let pair = try await Task.detached(priority: .userInitiated) {
                let result = try PartGeometry.transform(mesh, scale: scale, quarterTurnAxis: axis, placeOnBed: bed)
                return (result, try PartGeometry.report(result))
            }.value
            self.mesh = pair.0; report = pair.1
            changes.append(note)
        } catch { self.error = error.localizedDescription }
    }

    func reset() { mesh = original; report = originalReport; changes = []; error = nil }
}

struct PartToolsView: View {
    @ObservedObject var store: ScanStore
    let scanID: UUID
    let source: URL
    @StateObject private var tools = PartTools()
    @State private var camera = MeshCamera.orbit
    @State private var points: [SIMD3<Float>] = []
    @State private var picking = false
    @State private var reference = ""
    @State private var referenceAxis = -1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let mesh = tools.mesh {
                MeshSceneView(mesh: mesh, reference: mesh.bounds, crop: nil, camera: camera,
                              picked: points, onPick: picking ? { point in
                    if points.count == 2 { points = [] }
                    points.append(point)
                } : nil, zUp: true)
                    .frame(height: 260).id("\(camera.rawValue)-\(mesh.revision)")
                    .allowsHitTesting(!tools.working && !store.busy)
                Picker("View", selection: $camera) {
                    ForEach(MeshCamera.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                Form {
                    Section("Dimensions — millimeters") {
                        Text(dimensions(mesh)).monospacedDigit()
                        Text("Axis-aligned extents, not fitted part dimensions. Crop away background first.").font(.footnote)
                    }
                    Section("Measure and calibrate") {
                        Toggle("Pick two surface points", isOn: $picking)
                        Text("Drag to orbit, pinch to zoom, then tap two visible surfaces. Measures straight-line distance, not along the surface.").font(.footnote)
                        if let distance = distance {
                            Text("Selected distance: \(Double(distance * 1000), specifier: "%.2f") mm").monospacedDigit()
                        } else { Text("\(points.count) of 2 points selected") }
                        Button("Clear points") { points = [] }
                        Picker("Reference measurement", selection: $referenceAxis) {
                            Text("Picked distance").tag(-1)
                            ForEach(0..<3) { Text("\(["X", "Y", "Z"][$0]) extent").tag($0) }
                        }
                        TextField("Known real length (mm)", text: $reference).keyboardType(.decimalPad)
                        Button("Apply uniform calibration") { calibrate(mesh) }
                        Text("Use a caliper or ruler measurement of the same feature. Uniform scaling adjusts size; it cannot correct shape errors or guarantee fit.").font(.footnote)
                    }
                    Section("Print orientation — Z is up") {
                        HStack {
                            ForEach(0..<3) { axis in
                                Button("\(["X", "Y", "Z"][axis]) +90°") {
                                    transform(axis: axis, note: "Rotate \(["X", "Y", "Z"][axis]) +90 degrees")
                                }.buttonStyle(.bordered)
                            }
                        }
                        Button("Center XY and place bottom at Z = 0") { transform(bed: true, note: "Center XY, bottom at Z=0") }
                        Text("Rotates the entire mesh. Placement does not flatten the bottom or close holes.").font(.footnote)
                    }
                    Section("Mesh inspection") {
                        Text("\(mesh.vertices.count) vertices • \(mesh.triangleCount) triangles")
                        if let report = tools.report { Text(report.text).font(.footnote) }
                        Text("Coincident vertices are matched exactly for edge checks. Inspect the exported STL in your slicer before printing.").font(.footnote)
                    }
                    Section("Save a separate geometry revision") {
                        ForEach(Array(tools.changes.enumerated()), id: \.offset) { _, note in Text(note).font(.caption) }
                        Button("Reset unsaved changes") { tools.reset(); points = [] }
                        Button("Save part geometry") {
                            let result = MeshEditResult(mesh: mesh, summary: tools.changes.joined(separator: "; ") + ". Geometry in meters; original retained.")
                            Task { if await store.saveEdit(scanID, result: result) { dismiss() } }
                        }.disabled(tools.changes.isEmpty)
                        Text("Save here, then export OBJ or millimeter STL from the scan. Restore original remains available.").font(.footnote)
                    }
                }.disabled(tools.working || store.busy)
                    .scrollDismissesKeyboard(.interactively)
            }
            if tools.working || store.busy { ProgressView("Preparing part…").padding() }
            if let error = tools.error { Text(error).foregroundStyle(.red).padding() }
        }
        .navigationTitle("Part tools")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(tools.working || store.busy)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .task { await tools.load(source) }
    }

    private var distance: Float? { points.count == 2 ? simd_distance(points[0], points[1]) : nil }
    private func dimensions(_ mesh: EditableMesh) -> String {
        let e = mesh.bounds.extent * 1000
        return String(format: "X %.2f × Y %.2f × Z %.2f mm", e.x, e.y, e.z)
    }
    private func calibrate(_ mesh: EditableMesh) {
        do {
            let length = referenceAxis == -1 ? (distance ?? 0) : mesh.bounds.extent[referenceAxis]
            let mm = Float(reference.replacingOccurrences(of: ",", with: ".")) ?? .nan
            let factor = try PartGeometry.scaleFactor(measuredMeters: length, referenceMM: mm)
            transform(scale: factor, note: String(format: "Calibration %.3f mm → %.3f mm (×%.6f)", length*1000, mm, factor))
        } catch { tools.error = error.localizedDescription }
    }
    private func transform(scale: Float = 1, axis: Int? = nil, bed: Bool = false, note: String) {
        points = []; picking = false
        Task { await tools.transform(scale: scale, axis: axis, bed: bed, note: note) }
    }
}
