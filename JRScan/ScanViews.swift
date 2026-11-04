// Guided capture controls follow Apple's GuidedCaptureSample sequencing.
// License: Resources/Apple-ObjectCapture-LICENSE.txt.
import SwiftUI
import RealityKit
import QuickLook
import UIKit
import AVFoundation
import ARKit

struct ScanListView: View {
    @StateObject private var store = ScanStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Combined detail scan — photos + LiDAR", systemImage: "camera") { Task { await store.newCapture() } }
                        .disabled(store.busy || !ObjectCaptureSession.isSupported || !PhotogrammetrySession.isSupported)
                    Button("New live LiDAR scan", systemImage: "viewfinder") { Task { await store.newLidarCapture() } }
                        .disabled(store.busy || !ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))
                    Text("Combined detail uses Apple’s guided photos + LiDAR capture for objects and parts. Live LiDAR is the faster, coarser surface mode. Existing LiDAR meshes cannot gain missing detail without a new capture.").font(.footnote)
                    if !ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                        Text("Live LiDAR mesh capture is unavailable on this device.").font(.footnote)
                    }
                    Text("Capture and reconstruction run on this iPhone. Keep the app open during processing. Back up important scans; uninstalling can remove local data.")
                        .font(.footnote)
                }
                if store.scans.isEmpty {
                    Text("No scans yet. Start with a matte, textured object about 10–30 cm across in even light.")
                }
                ForEach(store.scans) { scan in
                    NavigationLink {
                        ScanDetailView(store: store, id: scan.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scan.name)
                            Text("\(scan.captureKind == "lidar" ? "LiDAR" : (scan.captureKind == "combined" ? "Combined" : "Object Capture")) • \(scan.stage.rawValue.capitalized) • \(scan.created.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    NavigationLink("Device and persistence checks") { InstallCheckView() }
                    NavigationLink("Notices") { NoticesView() }
                }
            }
            .navigationTitle("JR Scan")
            .fullScreenCover(isPresented: $store.showCapture) {
                if let session = store.capture { CaptureScreen(store: store, session: session) }
            }
            .fullScreenCover(isPresented: $store.showLidar) {
                if let lidar = store.lidar { LidarCaptureScreen(store: store, capture: lidar) }
            }
            .alert("JR Scan", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } message: { Text(store.error ?? "") }
            .onChange(of: scenePhase) { _, phase in store.sceneChanged(phase) }
        }
    }
}

struct CaptureScreen: View {
    @ObservedObject var store: ScanStore
    let session: ObjectCaptureSession
    @State private var showCancel = false
    @State private var detectionMessage: String?
    @State private var showEarlyFinish = false
    private var pass: Int { store.activeID.flatMap { store.record($0)?.passesStarted } ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Combined detail capture").font(.headline)
                Spacer()
                Button("Cancel") { showCancel = true }
            }.padding()
            ObjectCaptureView(session: session)
            VStack(spacing: 10) {
                Text(instruction).font(.headline)
                Text("Pass \(pass) of 3 recommended: \(pass == 1 ? "middle height" : pass == 2 ? "higher angle" : "lower angle"). Keep the part stationary.").font(.caption)
                Text("Photos supply fine detail; LiDAR supports shape and scale. Use even light, sharp views and overlapping coverage.").font(.caption)
                Text("Images: \(session.numberOfShotsTaken) / \(session.maximumNumberOfInputImages)")
                ForEach(session.feedback.map(feedback).sorted(), id: \.self) { message in
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
                if let detectionMessage { Text(detectionMessage).foregroundStyle(.orange) }
                switch session.state {
                case .ready:
                    Button("Detect object") {
                        detectionMessage = session.startDetecting() ? nil : "Detection could not start. Aim at a well-lit textured object and retry."
                    }.buttonStyle(.borderedProminent)
                case .detecting:
                    HStack {
                        Button("Reset bounds") { _ = session.resetDetection() }
                        Button("Start capture") { session.startCapturing() }.buttonStyle(.borderedProminent)
                    }
                case .capturing:
                    if session.isPaused { Button("Resume capture") { session.resume() } }
                    HStack {
                        Button("Take image") { session.requestImageCapture() }.disabled(!session.canRequestImageCapture)
                        Button("Finish & save") {
                            if pass < 3 { showEarlyFinish = true } else { session.finish() }
                        }.buttonStyle(.borderedProminent)
                            .disabled(session.numberOfShotsTaken == 0)
                    }
                    if session.userCompletedScanPass {
                        Text(pass < 3 ? "Pass complete. Move to the next height for more coverage." : "Three heights started. Finish this coverage dial, then save and reconstruct.").font(.caption)
                        Button("New pass at another height") { store.nextCapturePass() }
                    }
                case .initializing, .finishing: ProgressView()
                default: EmptyView()
                }
            }.padding()
        }
        .interactiveDismissDisabled()
        .confirmationDialog("Finish before three heights? Extra angles can improve coverage, but the device image limit still applies.", isPresented: $showEarlyFinish, titleVisibility: .visible) {
            Button("Finish with current inputs") { session.finish() }
            Button("Keep capturing", role: .cancel) {}
        }
        .confirmationDialog("Cancel capture? Saved images will be retained, but a partial capture may not reconstruct.", isPresented: $showCancel, titleVisibility: .visible) {
            Button("Cancel capture", role: .destructive) { store.cancelCapture() }
        }
    }

    private var instruction: String {
        switch session.state {
        case .initializing: return "Starting camera…"
        case .ready: return "Aim at the object, then detect it."
        case .detecting: return "Adjust the box to fit your object."
        case .capturing: return "Move slowly around the stationary object. Follow the coverage dial."
        case .finishing: return "Saving images and checkpoints…"
        case .completed: return "Capture saved"
        case .failed: return "Capture failed — input retained"
        @unknown default: return "Follow the capture guidance."
        }
    }

    private func feedback(_ value: ObjectCaptureSession.Feedback) -> String {
        switch value {
        case .objectTooFar: return "Move closer"
        case .objectTooClose: return "Move farther away"
        case .environmentTooDark: return "More light required"
        case .environmentLowLight: return "More light recommended"
        case .movingTooFast: return "Move slower"
        case .outOfFieldOfView: return "Aim at the object"
        default: return "Capture feedback: \(String(describing: value))"
        }
    }
}

private struct FileSelection: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ScanDetailView: View {
    @ObservedObject var store: ScanStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var units = ExportUnits.meters
    @State private var share: FileSelection?
    @State private var backup: FileSelection?
    @State private var preview: FileSelection?
    @State private var deleteConfirmation = false
    @State private var stopConfirmation = false
    @State private var restoreConfirmation = false

    var body: some View {
        Form {
            if let scan = store.record(id) {
                Section("Scan") {
                    TextField("Name", text: $name).onSubmit { store.rename(id, name: name) }
                    Button("Save name") { store.rename(id, name: name) }.disabled(store.busy)
                    Text(scan.created.formatted(date: .complete, time: .shortened))
                    Text("State: \(scan.stage.rawValue.capitalized)")
                    Text("Capture: \(store.isLidar(id) ? "Live LiDAR mesh" : "Photos + LiDAR / Object Capture")")
                    if !store.isLidar(id) {
                        Text("Saved input images: \(store.imageCount(id))")
                        if let passes = scan.passesStarted { Text("Capture passes started: \(passes)") }
                        if let depth = scan.depthSummary { Text(depth).font(.footnote) }
                        else { Text("Saved depth data will be checked when reconstruction starts.").font(.footnote) }
                    }
                    if let referenceID = scan.referenceScanID, store.record(referenceID) != nil {
                        NavigationLink("Open original LiDAR reference") { ScanDetailView(store: store, id: referenceID) }
                        Text("Separate capture coordinates. Models are retained independently, not automatically aligned or merged.").font(.footnote)
                    }
                    if let message = scan.message { Text(message).foregroundStyle(.orange) }
                    Text(id.uuidString).font(.caption).textSelection(.enabled)
                }
                if store.isLidar(id) {
                    Section("Saved LiDAR input") {
                        Button("Recover saved LiDAR mesh") { Task { await store.recoverLidarMesh(id) } }
                            .disabled(store.busy || !store.hasLidarCheckpoint(id))
                        Button("Capture finer detail — photos + LiDAR") { Task { await store.newCapture(referenceScanID: id) } }
                            .disabled(store.busy || !ObjectCaptureSession.isSupported || !PhotogrammetrySession.isSupported)
                        Text("Starts a new guided capture of the same stationary part. Keeps this LiDAR scan as a reference; it does not sharpen the existing mesh.").font(.footnote)
                        Text("Recovers checkpointed mesh patches locally. No photo reconstruction or live tracking-session resume is required.").font(.footnote)
                        if store.isExporting { ProgressView("Preparing geometry…") }
                    }
                } else if store.isProcessing && store.activeID == id {
                    Section("On-device reconstruction") {
                        ProgressView(value: store.progress)
                        Text("\(Int(store.progress * 100))% • \(store.processingStage)")
                        Text("Keep JR Scan in the foreground. Leaving the app stops processing; saved inputs allow a new reconstruction attempt.")
                        Button("Cancel reconstruction", role: .destructive) { stopConfirmation = true }
                            .disabled(store.isCancelling)
                    }
                } else {
                    Section("Reconstruction") {
                        Button(scan.modelName == nil ? "Reconstruct saved input" : "Reconstruct again (keep previous model)") { store.reconstruct(id) }
                            .disabled(store.busy || store.imageCount(id) == 0 || !PhotogrammetrySession.isSupported)
                        Text("Uses the supported iOS Reduced detail level. A retry starts a new request from saved input, not an arbitrary mid-session resume.")
                            .font(.footnote)
                        if scan.stage == .failed || scan.stage == .interrupted || scan.stage == .cancelled {
                            Button("Retry without object masking / checkpoints") {
                                store.reconstruct(id, mode: .withoutMasking)
                            }
                            .disabled(store.busy || store.imageCount(id) == 0 || !PhotogrammetrySession.isSupported)
                            Text("Uses the existing saved images. Preserves original inputs and checkpoints. May include background geometry. This is an alternate attempt, not a guaranteed fix.")
                                .font(.footnote)
                        }
                    }
                }
                if let model = store.model(id) {
                    Section("Model and geometry export") {
                        if let source = store.geometrySource(id) {
                            NavigationLink("Part tools — measure, calibrate, orient") { PartToolsView(store: store, scanID: id, source: source) }
                                .disabled(store.busy)
                            NavigationLink("Crop & clean mesh") { MeshEditorView(store: store, scanID: id, source: source) }
                                .disabled(store.busy)
                        }
                        if let edited = store.editedModel(id) {
                            NavigationLink("Preview edited geometry") { GeometryPreviewView(source: edited) }
                                .disabled(store.busy)
                            Text(scan.editSummary ?? "Saved geometry edit").font(.caption)
                            Button("Restore original geometry…") { restoreConfirmation = true }.disabled(store.busy)
                        }
                        if store.isLidar(id) {
                            NavigationLink("Preview original LiDAR mesh") { GeometryPreviewView(source: model) }.disabled(store.busy)
                        } else {
                            Button("Preview — rotate and zoom") { preview = FileSelection(urls: [model]) }.disabled(store.busy)
                        }
                        Button(store.isLidar(id) ? "Share original LiDAR OBJ (meters)" : "Share original USDZ") { share = FileSelection(urls: [model]) }.disabled(store.busy)
                        Picker("OBJ units", selection: $units) {
                            ForEach(ExportUnits.allCases) { unit in Text(unit.rawValue.capitalized).tag(unit) }
                        }
                        Button(store.editedModel(id) == nil ? "Export geometry OBJ…" : "Export edited geometry OBJ…") {
                            Task { if let urls = await store.export(id, units: units) { share = FileSelection(urls: urls) } }
                        }.disabled(store.busy)
                        Button("Export STL for printing (millimeters)…") {
                            Task { if let urls = await store.exportSTL(id) { share = FileSelection(urls: urls) } }
                        }.disabled(store.busy)
                        Text("STL uses the current saved geometry. Holes stay open; inspect the included edge report and your slicer preview.").font(.footnote)
                        if store.isExporting { ProgressView("Converting geometry…") }
                        if let message = scan.exportMessage { Text(message) }
                        Text("Millimeter coordinates are multiplied by 1000. OBJ has no standard unit declaration; use the included export note. This is not a metrology-grade measurement. Texture export is deferred.")
                            .font(.footnote)
                    }
                }
                Section("Backup and diagnostics") {
                    Button("Save scan and capture inputs to Files…") {
                        if let folder = try? store.folder(id) { backup = FileSelection(urls: [folder]) }
                    }.disabled(store.busy)
                    Button("Share diagnostic text…") {
                        if let log = store.diagnostics(id) { share = FileSelection(urls: [log]) }
                    }.disabled(store.busy)
                    Text("Backup includes captured inputs, checkpoints, models and exports. Diagnostic text contains stages and errors, without photos or account credentials.")
                        .font(.footnote)
                }
                Section {
                    Button("Delete scan…", role: .destructive) { deleteConfirmation = true }.disabled(store.busy)
                }
            }
        }
        .navigationTitle("Scan")
        .onAppear { name = store.record(id)?.name ?? "" }
        .sheet(item: $share) { selection in ShareFiles(urls: selection.urls) }
        .sheet(item: $backup) { selection in SaveFiles(urls: selection.urls) }
        .sheet(item: $preview) { selection in ModelPreview(url: selection.urls[0]) }
        .confirmationDialog("Delete this scan, its photos, models and exports permanently?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("Delete scan", role: .destructive) {
                store.delete(id)
                if store.record(id) == nil { dismiss() }
            }
        }
        .confirmationDialog("Cancel processing and retain inputs?", isPresented: $stopConfirmation, titleVisibility: .visible) {
            Button("Cancel reconstruction", role: .destructive) { store.cancelReconstruction() }
        }
        .confirmationDialog("Restore the original geometry for export? Saved edit files and the original model will be kept.", isPresented: $restoreConfirmation, titleVisibility: .visible) {
            Button("Restore original") { store.restoreOriginalGeometry(id) }
        }
    }
}

struct ShareFiles: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SaveFiles: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: urls, asCopy: true)
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}

struct ModelPreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

struct NoticesView: View {
    var body: some View {
        ScrollView {
            Text(notice).font(.footnote).padding().textSelection(.enabled)
        }.navigationTitle("Sample license")
    }
    private var notice: String {
        guard let url = Bundle.main.url(forResource: "Apple-ObjectCapture-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Apple sample license is included with the source repository." }
        return text
    }
}
