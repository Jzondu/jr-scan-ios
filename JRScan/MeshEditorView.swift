import SwiftUI
import SceneKit
import simd

enum MeshCamera: String, CaseIterable, Identifiable {
    case orbit = "3D", front = "Front", top = "Top", side = "Side"
    var id: String { rawValue }
}

@MainActor
final class MeshEditor: ObservableObject {
    @Published var source: EditableMesh?
    @Published var result: MeshEditResult?
    @Published var options = MeshEditOptions()
    @Published var appliedOptions: MeshEditOptions?
    @Published var working = false
    @Published var error: String?
    var currentResult: MeshEditResult? { options == appliedOptions ? result : nil }

    func load(_ url: URL) async {
        guard source == nil else { return }
        working = true
        defer { working = false }
        do { source = try await Task.detached(priority: .userInitiated) { try EditableMesh.load(url) }.value }
        catch { self.error = error.localizedDescription }
    }

    func apply() async {
        guard let source, !working else { return }
        let snapshot = options
        working = true
        error = nil
        defer { working = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try MeshEditing.apply(source, options: snapshot) }.value
            self.result = result
            appliedOptions = snapshot
        } catch { self.error = error.localizedDescription; result = nil; appliedOptions = nil }
    }
}

struct MeshEditorView: View {
    @ObservedObject var store: ScanStore
    let scanID: UUID
    let source: URL
    @StateObject private var editor = MeshEditor()
    @State private var camera = MeshCamera.orbit
    @State private var showSource = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if let mesh = editor.source {
                MeshSceneView(mesh: showSource ? mesh : (editor.currentResult?.mesh ?? mesh),
                              reference: mesh.bounds, crop: mesh.bounds.cropped(editor.options), camera: camera)
                    .frame(height: 280).id(camera)
                    .accessibilityLabel("3D mesh preview with crop box. Drag to rotate; pinch to zoom.")
                Picker("View", selection: $camera) {
                    ForEach(MeshCamera.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                Form {
                    Section("Crop box — retain the inside") {
                        Text("Rotate to check all sides. The outlined box is the area to keep. Press Preview changes after adjusting it.")
                            .font(.footnote)
                        ForEach(0..<3) { axis in axisControls(axis, bounds: mesh.bounds) }
                        Button("Reset crop box") { editor.options.lower = .zero; editor.options.upper = SIMD3(repeating: 1) }
                    }
                    Section("Mesh cleanup") {
                        Picker("Loose pieces", selection: $editor.options.fragments) {
                            ForEach(FragmentPolicy.allCases) { Text($0.title).tag($0) }
                        }
                        Text("Removes duplicate and degenerate faces and recalculates normals. Tiny pieces use 1% of the largest piece's surface area. Largest-only can remove intentional disconnected parts; crop the background first.")
                            .font(.footnote)
                        Text("Cut edges may stay open. No hole filling, smoothing or texture editing.").font(.footnote)
                    }
                    Section {
                        Toggle("Show unedited source", isOn: $showSource)
                        Button("Preview changes") {
                            showSource = false
                            Task { await editor.apply() }
                        }.disabled(editor.working || store.busy)
                        if let result = editor.currentResult {
                            Text(result.summary).font(.caption)
                            Button("Save edited geometry") {
                                Task { if await store.saveEdit(scanID, result: result) { dismiss() } }
                            }.disabled(editor.working || store.busy)
                        } else {
                            Text("No changes saved. Preview the current settings before saving.").font(.footnote)
                        }
                        Text("The original USDZ is preserved. Saved edits are geometry only; OBJ export uses the saved edit until you restore the original.")
                            .font(.footnote)
                    }
                }.disabled(editor.working || store.isExporting)
            } else if !editor.working {
                ContentUnavailableView("Geometry unavailable", systemImage: "exclamationmark.triangle", description: Text(editor.error ?? "Return to the scan and try again."))
            }
            if editor.working || store.isExporting { ProgressView(store.isExporting ? "Saving geometry…" : "Preparing geometry…").padding() }
            if let error = editor.error { Text(error).foregroundStyle(.red).font(.footnote).padding() }
        }
        .navigationTitle("Crop & clean")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(editor.working || store.isExporting)
        .task { await editor.load(source) }
    }

    private func axisControls(_ axis: Int, bounds: MeshBounds) -> some View {
        VStack(alignment: .leading) {
            let name = ["X", "Y", "Z"][axis]
            let minValue = bounds.minimum[axis] + bounds.extent[axis] * editor.options.lower[axis]
            let maxValue = bounds.minimum[axis] + bounds.extent[axis] * editor.options.upper[axis]
            Text("\(name): \(Double(minValue * 1000), specifier: "%.2f") to \(Double(maxValue * 1000), specifier: "%.2f") mm").font(.caption.monospacedDigit())
            HStack {
                Text("Min").font(.caption)
                Slider(value: Binding(get: { Double(editor.options.lower[axis]) }, set: {
                    editor.options.lower[axis] = min(Float($0), editor.options.upper[axis] - 0.001)
                }), in: 0...0.999, step: 0.001)
            }
            HStack {
                Text("Max").font(.caption)
                Slider(value: Binding(get: { Double(editor.options.upper[axis]) }, set: {
                    editor.options.upper[axis] = max(Float($0), editor.options.lower[axis] + 0.001)
                }), in: 0.001...1, step: 0.001)
            }
        }.disabled(bounds.extent[axis] < 1e-9)
    }
}

struct GeometryPreviewView: View {
    let source: URL
    @StateObject private var editor = MeshEditor()
    @State private var camera = MeshCamera.orbit
    var body: some View {
        VStack {
            if let mesh = editor.source {
                MeshSceneView(mesh: mesh, reference: mesh.bounds, crop: nil, camera: camera).id(camera)
                Picker("View", selection: $camera) {
                    ForEach(MeshCamera.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("\(mesh.triangleCount) triangles • drag to rotate, pinch to zoom").font(.footnote)
            } else if let error = editor.error { Text(error).foregroundStyle(.red) }
            else { ProgressView("Loading geometry…") }
        }.padding().navigationTitle("Edited geometry").task { await editor.load(source) }
    }
}

struct MeshSceneView: UIViewRepresentable {
    let mesh: EditableMesh
    let reference: MeshBounds
    let crop: MeshBounds?
    let camera: MeshCamera
    final class Coordinator { var revision: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        let distance = max(reference.diagonal, 0.001)
        let center = reference.center
        let offset: SIMD3<Float>
        switch camera {
        case .orbit: offset = SIMD3(1,0.8,1) * distance
        case .front: offset = SIMD3(0,0,2) * distance
        case .top: offset = SIMD3(0,2,0) * distance
        case .side: offset = SIMD3(2,0,0) * distance
        }
        cameraNode.simdPosition = center + offset
        cameraNode.camera?.zNear = Double(max(distance / 10_000, 0.000001))
        cameraNode.camera?.zFar = Double(max(distance * 100, 1))
        cameraNode.look(at: SCNVector3(center.x,center.y,center.z),
                        up: camera == .top ? SCNVector3(0,0,-1) : SCNVector3(0,1,0), localFront: SCNVector3(0,0,-1))
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3(center.x,center.y,center.z)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let root = view.scene?.rootNode else { return }
        root.childNode(withName: "crop", recursively: false)?.removeFromParentNode()
        if context.coordinator.revision != mesh.revision {
        root.childNode(withName: "mesh", recursively: false)?.removeFromParentNode()
        let vertices = mesh.vertices.map { SCNVector3($0.x,$0.y,$0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x,$0.y,$0.z) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.lightGray
        material.isDoubleSided = true
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "mesh"
        root.addChildNode(node)
        context.coordinator.revision = mesh.revision
        }
        if let crop {
            let size = simd_max(crop.extent, SIMD3(repeating: max(reference.diagonal * 1e-6, 1e-9)))
            let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
            let lines = SCNMaterial()
            lines.fillMode = .lines
            lines.lightingModel = .constant
            lines.diffuse.contents = UIColor.systemTeal
            lines.readsFromDepthBuffer = false
            box.materials = [lines]
            let outline = SCNNode(geometry: box)
            outline.name = "crop"
            outline.simdPosition = crop.center
            outline.renderingOrder = 10
            root.addChildNode(outline)
        }
    }
}
