import SwiftUI
import ARKit
import SceneKit
import Metal

@MainActor
final class LidarCapture: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    let archive: LidarArchive
    @Published var triangleCount = 0
    @Published var patchCount = 0
    @Published var savedTriangles = 0
    @Published var tracking = "Starting LiDAR tracking…"
    @Published var errorMessage: String?
    @Published var paused = false
    @Published var finishing = false
    @Published var meshWarnings = 0
    @Published var lastMeshWarning: String?
    var onIssue: ((String) -> Void)?
    var onWarning: ((String) -> Void)?
    private var patches: [UUID: LidarMeshPatch] = [:]
    private weak var view: ARSCNView?
    private var started = false
    private var collecting = false
    private var checkpointTask: Task<Void, Never>?
    private var checkpointFailed = false

    init(directory: URL) {
        archive = LidarArchive(directory: directory)
        super.init()
        // Every delegate entry below uses assumeIsolated only because this queue
        // is explicitly main; Metal buffers are copied before returning to ARKit.
        session.delegateQueue = .main
        session.delegate = self
    }

    func attach(_ view: ARSCNView) {
        self.view = view
        view.session = session
        session.delegate = self
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        guard !started else { return }
        started = true
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            issue("ARKit LiDAR mesh reconstruction is unsupported on this device."); return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        // Plane flattening is disabled to retain the LiDAR surface estimate.
        configuration.planeDetection = []
        collecting = true
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func checkpoint() {
        guard started, checkpointTask == nil, !finishing, !checkpointFailed else { return }
        let snapshot = Array(patches.values)
        checkpointTask = Task {
            do {
                try await archive.save(snapshot)
                savedTriangles = snapshot.reduce(0) { $0 + $1.indices.count/3 }
            } catch {
                let message = "LiDAR checkpoint could not be saved. Check free storage. \(error.localizedDescription)"
                errorMessage = message
                checkpointFailed = true
                collecting = false
                paused = true
                tracking = "Checkpoint failed. Free storage and finish, or close to retain the last saved mesh."
                session.pause()
                onIssue?(message)
            }
            checkpointTask = nil
        }
    }

    func pause(reason: String) {
        collecting = false
        paused = true
        tracking = reason + " Finish the saved mesh or close and start a new scan."
        session.pause()
        checkpoint()
    }

    func finish() async -> EditableMesh? {
        guard !finishing else { return nil }
        finishing = true
        collecting = false
        paused = true
        tracking = "Capture stopped. Saving the current mesh."
        session.pause()
        defer { finishing = false }
        await checkpointTask?.value
        let snapshot = Array(patches.values)
        do {
            try await archive.save(snapshot)
            savedTriangles = triangleCount
            return try await Task.detached(priority: .userInitiated) { try LidarMeshAssembly.combine(snapshot) }.value
        } catch {
            issue("Could not finish LiDAR mesh: \(error.localizedDescription). Previously saved patches are retained.")
            return nil
        }
    }

    func stopAndSave() async -> String? {
        collecting = false
        session.pause()
        finishing = true
        defer { finishing = false }
        await checkpointTask?.value
        do { try await archive.save(Array(patches.values)); return nil }
        catch { return "Could not save the latest mesh: \(error.localizedDescription). Earlier checkpoints remain available." }
    }

    private func issue(_ message: String) {
        errorMessage = message
        collecting = false
        paused = true
        tracking = "Capture paused after an error. Finish the retained mesh or close."
        session.pause()
        onIssue?(message)
    }

    private func ingest(_ anchors: [ARAnchor]) {
        guard collecting else { return }
            for anchor in anchors {
                guard let anchor = anchor as? ARMeshAnchor else { continue }
                do {
                let geometry = anchor.geometry
                let previousFaces = (patches[anchor.identifier]?.indices.count ?? 0)/3
                if geometry.faces.count == 0 || geometry.vertices.count == 0 {
                    patches.removeValue(forKey: anchor.identifier)
                    view?.scene.rootNode.childNode(withName: anchor.identifier.uuidString, recursively: false)?.removeFromParentNode()
                    triangleCount -= previousFaces
                    continue
                }
                if triangleCount-previousFaces+geometry.faces.count > 250_000 ||
                    (patches[anchor.identifier] == nil && patches.count >= 512) {
                    pause(reason: "Reached the local scan size limit (250,000 triangles / 512 patches).")
                    break
                }
                guard geometry.vertices.format == .float3,
                      geometry.faces.indexCountPerPrimitive == 3 else {
                    throw ScanFailure.message("Unsupported ARKit mesh buffer format.")
                }
                let vertices = try LidarMeshAssembly.vectors(Data(bytes: geometry.vertices.buffer.contents(), count: geometry.vertices.buffer.length),
                                                           count: geometry.vertices.count, offset: geometry.vertices.offset, stride: geometry.vertices.stride, requireFinite: false)
                let indices = try LidarMeshAssembly.indices(Data(bytes: geometry.faces.buffer.contents(), count: geometry.faces.buffer.length),
                                                           faceCount: geometry.faces.count, bytesPerIndex: geometry.faces.bytesPerIndex, vertexCount: vertices.count)
                let sanitized = try LidarMeshAssembly.sanitize(id: anchor.identifier,
                    transform: LidarMeshAssembly.matrixValues(anchor.transform), vertices: vertices, indices: indices)
                if sanitized.removedFaces > 0 || sanitized.invalidVertices > 0 {
                    warn("Filtered LiDAR update: \(sanitized.invalidVertices) invalid positions, \(sanitized.removedFaces) unusable faces. Normals regenerated.")
                }
                guard let patch = sanitized.patch else {
                    if sanitized.removedFaces == 0 { warn("LiDAR update had no usable faces; previous patch retained.") }
                    continue
                }
                patches[patch.id] = patch
                triangleCount = triangleCount-previousFaces+patch.indices.count/3
                draw(patch, transform: anchor.transform)
                } catch {
                    warn("Skipped LiDAR patch update; previous valid patch retained: \(error.localizedDescription)")
                }
            }
            patchCount = patches.count
    }

    private func warn(_ message: String) {
        meshWarnings += 1
        lastMeshWarning = message
        // Log first few events and powers of two to retain evidence without per-frame spam.
        if meshWarnings <= 3 || (meshWarnings & (meshWarnings-1)) == 0 {
            onWarning?("Mesh warning \(meshWarnings): \(message)")
        }
    }

    private func draw(_ patch: LidarMeshPatch, transform: simd_float4x4) {
        guard let root = view?.scene.rootNode else { return }
        root.childNode(withName: patch.id.uuidString, recursively: false)?.removeFromParentNode()
        let positions = patch.vertices.map { SCNVector3($0.x,$0.y,$0.z) }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions)],
                                   elements: [SCNGeometryElement(indices: patch.indices, primitiveType: .triangles)])
        let material = SCNMaterial()
        material.fillMode = .lines
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.systemTeal
        material.isDoubleSided = true
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = patch.id.uuidString
        node.simdTransform = transform
        root.addChildNode(node)
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        MainActor.assumeIsolated { ingest(anchors) }
    }
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated { ingest(anchors) }
    }
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated {
            guard collecting else { return }
            for anchor in anchors {
                if let patch = patches.removeValue(forKey: anchor.identifier) { triangleCount -= patch.indices.count/3 }
                view?.scene.rootNode.childNode(withName: anchor.identifier.uuidString, recursively: false)?.removeFromParentNode()
            }
            patchCount = patches.count
        }
    }
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        MainActor.assumeIsolated {
            guard !paused else { return }
            switch camera.trackingState {
            case .normal: tracking = "Tracking normal — move slowly around nearby surfaces."
            case .notAvailable: tracking = "Tracking unavailable. Point at a well-lit textured area."
            case .limited(let reason): tracking = "Tracking limited: \(String(describing: reason)). Slow down and improve lighting."
            }
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated { pause(reason: "LiDAR session interrupted."); onIssue?(tracking) }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated { if paused { self.session.pause() } }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated { issue(ReconstructionFailure.details(error, stage: "LiDAR capture")); checkpoint() }
    }
}

struct LidarCameraView: UIViewRepresentable {
    let capture: LidarCapture
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        capture.attach(view)
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {}
    static func dismantleUIView(_ view: ARSCNView, coordinator: ()) { view.session.pause() }
}

struct LidarCaptureScreen: View {
    @ObservedObject var store: ScanStore
    @ObservedObject var capture: LidarCapture
    @State private var cancelConfirmation = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Live LiDAR scan").font(.headline)
                Spacer()
                Button("Close") { cancelConfirmation = true }.disabled(capture.finishing || store.isExporting)
            }.padding(.horizontal)
            LidarCameraView(capture: capture)
            Text(capture.tracking).font(.callout).padding(.horizontal)
            Text("\(capture.triangleCount) triangles • \(capture.patchCount) patches")
            Text("Checkpoint saved: \(capture.savedTriangles) triangles").font(.caption)
            if capture.meshWarnings > 0 {
                Text("\(capture.meshWarnings) mesh updates needed filtering. Capture continues; inspect coverage before saving.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Scan nearby surfaces slowly from several angles. LiDAR is coarse for small objects; crop unwanted surroundings after saving. Geometry only, no photo texture.")
                .font(.footnote).padding(.horizontal)
            if let error = capture.errorMessage { Text(error).foregroundStyle(.orange).font(.footnote).padding(.horizontal) }
            if capture.finishing || store.isExporting { ProgressView("Saving LiDAR mesh…") }
            Button("Finish & save mesh") { Task { await store.finishLidarCapture() } }
                .buttonStyle(.borderedProminent)
                .disabled(capture.triangleCount == 0 || capture.finishing || store.isExporting)
        }
        .padding(.vertical)
        .interactiveDismissDisabled()
        .onReceive(timer) { _ in capture.checkpoint() }
        .confirmationDialog("Close LiDAR capture? Saved mesh patches will be kept for recovery.", isPresented: $cancelConfirmation, titleVisibility: .visible) {
            Button("Close and keep saved mesh") { Task { await store.cancelLidarCapture() } }
        }
    }
}
