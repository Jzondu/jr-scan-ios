// Capture/reconstruction sequencing adapted from Apple's GuidedCaptureSample.
// See Resources/Apple-ObjectCapture-LICENSE.txt (also included in the app bundle).
import SwiftUI
import RealityKit
import AVFoundation
import UIKit
import ARKit

struct ScanRecord: Codable, Identifiable {
    enum Stage: String, Codable {
        case capturing, captured, reconstructing, completed, interrupted, cancelled, failed
    }
    let id: UUID
    var name: String
    let created: Date
    var updated: Date
    var stage: Stage
    var captureFinished = false
    var modelName: String?
    var message: String?
    var exportMessage: String?
    // Optional fields keep manifests from builds 3–6 decodable without migration.
    var reconstructionMode: String?
    var lastProcessingStage: String?
    var lastErrorDetails: String?
    var editedModelName: String?
    var editSummary: String?
    var captureKind: String? // nil = existing photo/Object Capture scan.
}

@MainActor
final class ScanStore: ObservableObject {
    @Published var scans: [ScanRecord] = []
    @Published var error: String?
    @Published var capture: ObjectCaptureSession?
    @Published var showCapture = false
    @Published var activeID: UUID?
    @Published var progress: Double = 0
    @Published var processingStage = ""
    @Published var isProcessing = false
    @Published var isCancelling = false
    @Published var isExporting = false
    @Published var isStarting = false
    @Published var lidar: LidarCapture?
    @Published var showLidar = false
    private var reconstruction: PhotogrammetrySession?
    private var processingTask: Task<Void, Never>?
    private var stopReason: String?
    private var captureTask: Task<Void, Never>?
    private(set) var root: URL?

    var busy: Bool { isStarting || showCapture || showLidar || isProcessing || isExporting }

    init() {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            root = documents.appendingPathComponent("Scans", isDirectory: true)
            try FileManager.default.createDirectory(at: root!, withIntermediateDirectories: true)
            try load()
        } catch { self.error = "Local storage: \(error.localizedDescription)" }
    }

    func folder(_ id: UUID) throws -> URL {
        guard let root else { throw ScanFailure.message("Local storage is unavailable. Restart the app and check free space.") }
        return root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func images(_ id: UUID) throws -> URL { try folder(id).appendingPathComponent("Images", isDirectory: true) }
    func checkpoints(_ id: UUID) throws -> URL { try folder(id).appendingPathComponent("Checkpoints", isDirectory: true) }
    func record(_ id: UUID) -> ScanRecord? { scans.first { $0.id == id } }
    func model(_ id: UUID) -> URL? {
        guard let name = record(id)?.modelName, let directory = try? folder(id) else { return nil }
        let url = directory.appendingPathComponent("Models").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func editedModel(_ id: UUID) -> URL? {
        guard let name = record(id)?.editedModelName, let directory = try? folder(id) else { return nil }
        let url = directory.appendingPathComponent("Edits").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func geometrySource(_ id: UUID) -> URL? { editedModel(id) ?? model(id) }

    func isLidar(_ id: UUID) -> Bool { record(id)?.captureKind == "lidar" }
    func hasLidarCheckpoint(_ id: UUID) -> Bool {
        guard let directory = try? folder(id) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("RawLiDAR/index.json").path)
    }

    func newLidarCapture() async {
        guard !busy else { return }
        isStarting = true
        defer { isStarting = false }
        guard ARWorldTrackingConfiguration.isSupported, ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            error = "Live LiDAR scene-mesh capture is unsupported on this device."; return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            error = "Camera access is required for LiDAR tracking. Enable Camera in Settings → JR Scan."; return
        }
        let id = UUID()
        do {
            try checkSpace()
            let directory = try folder(id)
            for name in ["RawLiDAR","Models","Exports"] {
                try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            var item = ScanRecord(id: id, name: "LiDAR \(Date().formatted(date: .abbreviated, time: .shortened))",
                                  created: Date(), updated: Date(), stage: .capturing)
            item.captureKind = "lidar"
            try write(item)
            scans.insert(item, at: 0)
            let controller = LidarCapture(directory: directory.appendingPathComponent("RawLiDAR"))
            controller.onIssue = { [weak self] message in
                self?.stage(id, .interrupted, message: message)
            }
            activeID = id
            lidar = controller
            showLidar = true
            UIApplication.shared.isIdleTimerDisabled = true
            log(id, "ARKit LiDAR mesh capture started; local patch checkpoints every 2 seconds")
        } catch { self.error = "Could not start LiDAR: \(error.localizedDescription)" }
    }

    func finishLidarCapture() async {
        guard let lidar, let id = activeID, !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        guard let mesh = await lidar.finish() else { return }
        do {
            try await commitLidarMesh(id, mesh: mesh)
            closeLidar()
        } catch {
            let message = "LiDAR mesh could not be saved: \(error.localizedDescription). Raw checkpoints retained; free space and retry."
            lidar.errorMessage = message
            lidar.tracking = "Capture stopped. Free storage and retry Finish, or close to retain checkpoints."
            stage(id, .failed, message: message)
        }
    }

    func cancelLidarCapture() async {
        guard let lidar, let id = activeID, !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        let failure = await lidar.stopAndSave()
        stage(id, failure == nil ? .cancelled : .interrupted,
              message: failure ?? "LiDAR capture closed. Recover the saved mesh from this scan; no tracking-session resume is promised.")
        closeLidar()
        if let failure { error = failure }
    }

    private func closeLidar() {
        lidar?.session.pause()
        showLidar = false
        lidar = nil
        activeID = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func recoverLidarMesh(_ id: UUID) async {
        guard !busy, isLidar(id) else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            try checkSpace()
            let archive = LidarArchive(directory: try folder(id).appendingPathComponent("RawLiDAR"))
            let patches = try await archive.load()
            let mesh = try await Task.detached(priority: .userInitiated) { try LidarMeshAssembly.combine(patches) }.value
            try await commitLidarMesh(id, mesh: mesh)
        } catch {
            stage(id, .failed, message: "LiDAR recovery failed: \(error.localizedDescription). Saved files retained.")
            self.error = "LiDAR recovery: \(error.localizedDescription)"
        }
    }

    private func commitLidarMesh(_ id: UUID, mesh: EditableMesh) async throws {
        try checkSpace()
        let name = "lidar-\(UUID().uuidString)-meters.obj"
        let output = try folder(id).appendingPathComponent("Models").appendingPathComponent(name)
        let count = try await Task.detached(priority: .userInitiated) {
            var options = MeshEditOptions()
            options.fragments = .keepAll
            let clean = try MeshEditing.apply(mesh, options: options)
            try clean.mesh.writeOBJ(output)
            return clean.mesh.triangleCount
        }.value
        try update(id) {
            $0.modelName = name; $0.stage = .completed; $0.captureFinished = true
            $0.editedModelName = nil; $0.editSummary = nil; $0.exportMessage = nil
            $0.message = "Live LiDAR geometry: \(count) triangles. Coarse untextured surface estimate; crop surroundings before export. Not metrology-grade accuracy."
        }
        log(id, "LiDAR mesh saved: \(count) triangles in meters; anchor transforms applied, raw checkpoints retained")
    }

    func saveEdit(_ id: UUID, result: MeshEditResult) async -> Bool {
        guard !busy else { return false }
        isExporting = true
        defer { isExporting = false }
        do {
            try checkSpace()
            let revision = UUID().uuidString
            let directory = try folder(id).appendingPathComponent("Edits").appendingPathComponent(revision)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = directory.appendingPathComponent("geometry-meters.obj")
            try await Task.detached(priority: .userInitiated) { try result.mesh.writeOBJ(output) }.value
            try result.summary.write(to: directory.appendingPathComponent("Edit-note.txt"), atomically: true, encoding: .utf8)
            // Publish only after validated geometry and its note are durably written.
            try update(id) {
                $0.editedModelName = "\(revision)/geometry-meters.obj"
                $0.editSummary = result.summary
                $0.exportMessage = nil
            }
            log(id, "Saved separate geometry edit: \(result.summary)")
            return true
        } catch {
            log(id, "Geometry edit failed: \(error.localizedDescription)")
            self.error = "Could not save geometry edit: \(error.localizedDescription). Original and previous saved edit retained."
            return false
        }
    }

    func restoreOriginalGeometry(_ id: UUID) {
        guard !busy else { return }
        do {
            try update(id) { $0.editedModelName = nil; $0.editSummary = nil; $0.exportMessage = nil }
            log(id, "Restored original geometry for preview/edit/export; edit files retained in backup")
        } catch { self.error = error.localizedDescription }
    }

    func imageCount(_ id: UUID) -> Int {
        guard let directory = try? images(id), let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return 0 }
        return urls.filter { ["heic","heif","jpg","jpeg","png","tif","tiff"].contains($0.pathExtension.lowercased()) }.count
    }

    private func load() throws {
        guard let root else { return }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                 options: .skipsHiddenFiles)
        var loaded: [ScanRecord] = []
        for directory in folders where UUID(uuidString: directory.lastPathComponent) != nil {
            do {
                var item = try JSONDecoder().decode(ScanRecord.self, from: Data(contentsOf: directory.appendingPathComponent("scan.json")))
                guard item.id.uuidString == directory.lastPathComponent else { throw ScanFailure.message("Scan identity mismatch.") }
                if item.stage == .capturing || item.stage == .reconstructing {
                    item.stage = .interrupted
                    item.message = item.captureKind == "lidar"
                        ? "LiDAR capture ended unexpectedly. Recover the saved mesh patches below. Tracking-session resume is not promised."
                        : "The previous session ended unexpectedly. Saved inputs are retained. Restart reconstruction from inputs; mid-session resume is not promised."
                    try write(item)
                }
                loaded.append(item)
            } catch {
                self.error = "A scan could not be read (\(directory.lastPathComponent)). Files are retained in Files → JR Scan → Scans. \(error.localizedDescription)"
            }
        }
        scans = loaded.sorted { $0.created > $1.created }
    }

    private func write(_ scan: ScanRecord) throws {
        let url = try folder(scan.id).appendingPathComponent("scan.json")
        try JSONEncoder().encode(scan).write(to: url, options: .atomic)
    }

    private func update(_ id: UUID, _ change: (inout ScanRecord) -> Void) throws {
        guard let index = scans.firstIndex(where: { $0.id == id }) else { throw ScanFailure.message("Scan not found.") }
        var item = scans[index]
        change(&item)
        item.updated = Date()
        try write(item)
        scans[index] = item
    }

    private func stage(_ id: UUID, _ stage: ScanRecord.Stage, message: String? = nil) {
        do { try update(id) { $0.stage = stage; $0.message = message } }
        catch { self.error = "Could not save scan status. Check free space. \(error.localizedDescription)" }
        log(id, "\(stage.rawValue): \(message ?? "")")
    }

    private func checkSpace() throws {
        guard let root else { throw ScanFailure.message("Storage is unavailable.") }
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < 1_000_000_000 {
            throw ScanFailure.message("Less than 1 GB of free storage remains. Free space before capturing or reconstructing. Large scans may require more.")
        }
    }

    func newCapture() async {
        guard !busy else { return }
        isStarting = true
        defer { isStarting = false }
        guard ObjectCaptureSession.isSupported, PhotogrammetrySession.isSupported else {
            error = "This device or OS does not support the capture and reconstruction workflow."; return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            error = "Camera access is required. Enable Camera in Settings → JR Scan, then retry."; return
        }
        let id = UUID()
        do {
            try checkSpace()
            let directory = try folder(id)
            for name in ["Images","Checkpoints","Models","Exports"] {
                try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            let item = ScanRecord(id: id, name: "Scan \(Date().formatted(date: .abbreviated, time: .shortened))",
                                  created: Date(), updated: Date(), stage: .capturing)
            try write(item)
            scans.insert(item, at: 0)
            activeID = id
            let session = ObjectCaptureSession()
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = try checkpoints(id)
            configuration.isOverCaptureEnabled = false
            session.start(imagesDirectory: try images(id), configuration: configuration)
            capture = session
            showCapture = true
            UIApplication.shared.isIdleTimerDisabled = true
            log(id, "Capture started")
            captureTask = Task { [weak self] in
                for await state in session.stateUpdates {
                    guard let self, !Task.isCancelled else { return }
                    switch state {
                    case .completed:
                        do { try self.update(id) { $0.captureFinished = true; $0.stage = .captured; $0.message = nil } }
                        catch { self.error = "Input is saved, but status could not be saved: \(error.localizedDescription)" }
                        self.log(id, "Capture saved; \(self.imageCount(id)) images")
                        self.closeCapture()
                        return
                    case .failed(let failure):
                        self.stage(id, .failed, message: failure.localizedDescription)
                        self.error = "Capture: \(failure.localizedDescription). Saved input is retained."
                        self.closeCapture()
                        return
                    default: break
                    }
                }
            }
            if case .failed(let failure) = session.state { throw failure }
        } catch {
            if record(id) != nil { stage(id, .failed, message: error.localizedDescription) }
            closeCapture()
            self.error = "Could not start capture: \(error.localizedDescription)"
        }
    }

    func cancelCapture() {
        guard let id = activeID else { return }
        captureTask?.cancel()
        capture?.cancel()
        stage(id, .cancelled, message: "Capture cancelled. Already-written inputs are retained; a partial capture may not reconstruct.")
        closeCapture()
    }

    private func closeCapture() {
        captureTask?.cancel()
        showCapture = false
        capture = nil
        captureTask = nil
        activeID = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reconstruct(_ id: UUID, mode: ReconstructionMode = .guided) {
        guard !busy else { return }
        guard !isLidar(id) else { error = "This is a LiDAR scan. Use Recover saved LiDAR mesh instead of photo reconstruction."; return }
        guard PhotogrammetrySession.isSupported else { error = "On-device reconstruction is unsupported."; return }
        isProcessing = true
        activeID = id
        stopReason = nil
        isCancelling = false
        progress = 0
        processingStage = "Preparing saved input"
        processingTask = Task {
            do {
                try checkSpace()
                guard imageCount(id) > 0 else { throw ScanFailure.message("There are no saved input images to reconstruct.") }
                let fileName = "model-\(UUID().uuidString).usdz"
                let output = try folder(id).appendingPathComponent("Models").appendingPathComponent(fileName)
                // Preserve every earlier output; a retry writes a new file, never overwrites a good model.
                var configuration = PhotogrammetrySession.Configuration()
                if mode == .guided {
                    configuration.checkpointDirectory = try checkpoints(id)
                } else {
                    // Diagnostic fallback suggested by Apple for mask-related failures.
                    // Do not reuse or delete capture/reconstruction checkpoint state.
                    configuration.isObjectMaskingEnabled = false
                    configuration.checkpointDirectory = nil
                }
                let session = try PhotogrammetrySession(input: try images(id), configuration: configuration)
                reconstruction = session
                activeID = id
                stopReason = nil
                progress = 0
                processingStage = "Preparing input"
                isProcessing = true
                UIApplication.shared.isIdleTimerDisabled = true
                try update(id) {
                    $0.stage = .reconstructing; $0.message = nil
                    $0.reconstructionMode = mode.rawValue
                    $0.lastProcessingStage = processingStage
                    $0.lastErrorDetails = nil
                }
                log(id, "On-device reconstruction started (.reduced), mode=\(mode.rawValue), saved images=\(imageCount(id)), capture finished=\(record(id)?.captureFinished ?? false)")
                try session.process(requests: [.modelFile(url: output, detail: .reduced)])
                var modelRequestCompleted = false
                var reconstructionWarning: String? = mode == .withoutMasking
                    ? "Reconstructed without object masking or capture checkpoints. Background geometry may be included; inspect before export." : nil
                for try await event in session.outputs {
                    switch event {
                    case .requestProgress(_, let fraction): progress = min(1, max(0, fraction))
                    case .requestProgressInfo(_, let info):
                        let nextStage = info.processingStage.map { String(describing: $0) } ?? "Reconstructing"
                        if nextStage != processingStage {
                            processingStage = nextStage
                            try update(id) { $0.lastProcessingStage = nextStage }
                            log(id, "Processing stage: \(nextStage)")
                        }
                    case .requestComplete(_, _): modelRequestCompleted = true
                    case .requestError(_, let failure): throw failure
                    case .processingComplete:
                        if let stopReason {
                            stage(id, .interrupted, message: stopReason)
                        } else if isCancelling {
                            stage(id, .cancelled, message: "Reconstruction cancelled. Inputs retained; restart when ready.")
                        } else {
                            let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard modelRequestCompleted, size > 0 else { throw ScanFailure.message("Reconstruction finished without a usable model file.") }
                            try update(id) {
                                $0.modelName = fileName; $0.stage = .completed; $0.message = reconstructionWarning
                                $0.editedModelName = nil; $0.editSummary = nil; $0.exportMessage = nil
                            }
                            log(id, "USDZ saved (\(size) bytes)")
                        }
                        endProcessing()
                        return
                    case .processingCancelled:
                        stage(id, stopReason == nil ? .cancelled : .interrupted,
                              message: stopReason ?? "Reconstruction cancelled. Inputs retained; restart when ready.")
                        endProcessing()
                        return
                    case .invalidSample(_, let reason): log(id, "Invalid input sample: \(reason)")
                    case .skippedSample(_): log(id, "Input sample skipped by framework")
                    case .automaticDownsampling: log(id, "Framework downsampled inputs")
                    case .stitchingIncomplete:
                        reconstructionWarning = "The framework reports incomplete stitching. Inspect the model for missing or disconnected parts before using its geometry."
                        log(id, "Warning: framework reports incomplete stitching")
                    default: break
                    }
                }
                throw ScanFailure.message("Reconstruction output stream ended before completion. Inputs retained.")
            } catch {
                if isCancelling, stopReason == nil {
                    stage(id, .cancelled, message: "Reconstruction cancelled. Inputs and previous outputs retained.")
                } else {
                    let details = ReconstructionFailure.details(error, stage: processingStage)
                    try? update(id) { $0.lastErrorDetails = details; $0.lastProcessingStage = processingStage }
                    log(id, details)
                    let message = stopReason ?? ReconstructionFailure.message(error)
                    stage(id, stopReason == nil ? .failed : .interrupted, message: message)
                    self.error = message
                }
                endProcessing()
            }
        }
    }

    func cancelReconstruction() { isCancelling = true; reconstruction?.cancel() }

    private func endProcessing() {
        reconstruction = nil
        isProcessing = false
        isCancelling = false
        activeID = nil
        processingTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func sceneChanged(_ phase: ScenePhase) {
        if phase == .active { capture?.resume() }
        else { capture?.pause() }
        if phase == .background, isProcessing, let id = activeID {
            stopReason = "App left the foreground. Inputs retained; restart reconstruction from saved input."
            stage(id, .interrupted, message: stopReason)
            reconstruction?.cancel()
        }
        if phase == .background, let lidar, let id = activeID {
            lidar.pause(reason: "JR Scan left the foreground.")
            stage(id, .interrupted, message: "LiDAR paused when the app left the foreground. Finish the saved mesh or close; checkpoints are retained.")
        }
    }

    func export(_ id: UUID, units: ExportUnits) async -> [URL]? {
        guard !busy, let source = geometrySource(id) else { return nil }
        isExporting = true
        defer { isExporting = false }
        do {
            try checkSpace()
            let directory = try folder(id).appendingPathComponent("Exports")
                .appendingPathComponent("\(units.rawValue)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("JRScan-\(id.uuidString)-\(units.rawValue).obj")
            let summary = try await Task.detached(priority: .userInitiated) {
                try OBJExporter.convert(source: source, destination: destination, units: units)
            }.value
            let note = """
            JR Scan — geometry OBJ
            Scan ID: \(id.uuidString)
            Geometry source: \(editedModel(id) != nil ? "saved crop/cleanup revision" : "original reconstruction")
            Units: \(units.rawValue)
            Coordinates = reconstructed meter coordinates × \(units.multiplier).
            OBJ has no universal unit declaration. Configure your importer for these units.
            Vertices: \(summary.vertices); triangles: \(summary.triangles)
            Bounds minimum: \(summary.minimum); maximum: \(summary.maximum)
            Normals included; scene transforms baked into vertex positions. No texture export.
            Recovered metric scale is not metrology-grade accuracy. Compare a known measurement.
            Original model and capture inputs remain in this scan's folder.
            Edit details: \(record(id)?.editSummary ?? "none")
            """
            try note.write(to: directory.appendingPathComponent("Export-\(units.rawValue).txt"), atomically: true, encoding: .utf8)
            try update(id) { $0.exportMessage = "\(summary.triangles) triangles exported in \(units.rawValue)" }
            log(id, "OBJ export: \(summary.triangles) triangles, \(units.rawValue)")
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            try? update(id) { $0.exportMessage = "Export failed: \(error.localizedDescription)" }
            log(id, "OBJ export failed: \(error.localizedDescription)")
            self.error = "OBJ export failed: \(error.localizedDescription). Original USDZ and inputs are retained."
            return nil
        }
    }

    func rename(_ id: UUID, name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !name.isEmpty else { return }
        do { try update(id) { $0.name = name } } catch { self.error = error.localizedDescription }
    }

    func delete(_ id: UUID) {
        guard !busy else { return }
        do {
            // Only an existing scan ID under our own storage root can be removed.
            guard record(id) != nil else { return }
            try FileManager.default.removeItem(at: folder(id))
            scans.removeAll { $0.id == id }
        } catch { self.error = "Deletion failed: \(error.localizedDescription)" }
    }

    func diagnostics(_ id: UUID) -> URL? {
        do {
            guard let item = record(id) else { return nil }
            let info = Bundle.main.infoDictionary ?? [:]
            let header = """
            JR Scan \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))
            OS: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
            Device: \(UIDevice.current.model)
            Bundle: \(Bundle.main.bundleIdentifier ?? "?")
            Object Capture supported: \(ObjectCaptureSession.isSupported)
            Reconstruction supported: \(PhotogrammetrySession.isSupported)
            Scan: \(id.uuidString)
            Capture kind: \(item.captureKind ?? "photo/Object Capture")
            LiDAR scene mesh supported: \(ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh))
            Stage: \(item.stage.rawValue)
            Reconstruction mode: \(item.reconstructionMode ?? "guided (older build)")
            Last processing stage: \(item.lastProcessingStage ?? "not recorded by this build")
            Capture finish confirmed: \(item.captureFinished)
            Saved images: \(imageCount(id))
            Free disk bytes: \((try? folder(id).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage).map { String($0) } ?? "unknown")
            Message: \(item.message ?? "none")
            Error details: \(item.lastErrorDetails ?? "not recorded; retry on this build for full details")
            Export: \(item.exportMessage ?? "not exported")
            Geometry edit: \(item.editSummary ?? "none")
            No photographs or account credentials are included in this log.

            """
            let historyURL = try folder(id).appendingPathComponent("events.txt")
            let history = (try? String(contentsOf: historyURL, encoding: .utf8)) ?? ""
            let output = try folder(id).appendingPathComponent("Diagnostics.txt")
            try (header + history).write(to: output, atomically: true, encoding: .utf8)
            return output
        } catch { self.error = "Could not write diagnostics: \(error.localizedDescription)"; return nil }
    }

    private func log(_ id: UUID, _ event: String) {
        do {
            let url = try folder(id).appendingPathComponent("events.txt")
            let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let bounded = String(previous.suffix(48_000))
            try (bounded + "\(Date().ISO8601Format()) \(event)\n").write(to: url, atomically: true, encoding: .utf8)
        } catch { self.error = "Could not save diagnostic log. Check free storage. \(error.localizedDescription)" }
    }
}
