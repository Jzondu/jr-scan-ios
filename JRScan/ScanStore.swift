// Capture/reconstruction sequencing adapted from Apple's GuidedCaptureSample.
// See Resources/Apple-ObjectCapture-LICENSE.txt (also included in the app bundle).
import SwiftUI
import RealityKit
import AVFoundation
import UIKit

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
    @Published var isExporting = false
    @Published var isStarting = false
    private var reconstruction: PhotogrammetrySession?
    private var processingTask: Task<Void, Never>?
    private var stopReason: String?
    private var captureTask: Task<Void, Never>?
    private(set) var root: URL?

    var busy: Bool { isStarting || showCapture || isProcessing || isExporting }

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
                    item.message = "The previous session ended unexpectedly. Saved inputs are retained. Restart reconstruction from inputs; mid-session resume is not promised."
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
        showCapture = false
        capture = nil
        captureTask = nil
        activeID = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reconstruct(_ id: UUID) {
        guard !busy else { return }
        guard PhotogrammetrySession.isSupported else { error = "On-device reconstruction is unsupported."; return }
        isProcessing = true
        activeID = id
        stopReason = nil
        processingTask = Task {
            do {
                try checkSpace()
                guard imageCount(id) > 0 else { throw ScanFailure.message("There are no saved input images to reconstruct.") }
                let fileName = "model-\(UUID().uuidString).usdz"
                let output = try folder(id).appendingPathComponent("Models").appendingPathComponent(fileName)
                // Preserve every earlier output; a retry writes a new file, never overwrites a good model.
                var configuration = PhotogrammetrySession.Configuration()
                configuration.checkpointDirectory = try checkpoints(id)
                let session = try PhotogrammetrySession(input: try images(id), configuration: configuration)
                reconstruction = session
                activeID = id
                stopReason = nil
                progress = 0
                processingStage = "Preparing input"
                isProcessing = true
                UIApplication.shared.isIdleTimerDisabled = true
                try update(id) { $0.stage = .reconstructing; $0.message = nil }
                log(id, "On-device reconstruction started (.reduced)")
                try session.process(requests: [.modelFile(url: output, detail: .reduced)])
                var modelRequestCompleted = false
                for try await event in session.outputs {
                    switch event {
                    case .requestProgress(_, let fraction): progress = min(1, max(0, fraction))
                    case .requestProgressInfo(_, let info):
                        processingStage = info.processingStage.map { String(describing: $0) } ?? "Reconstructing"
                    case .requestComplete(_, _): modelRequestCompleted = true
                    case .requestError(_, let failure): throw failure
                    case .processingComplete:
                        if let stopReason {
                            stage(id, .interrupted, message: stopReason)
                        } else {
                            let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard modelRequestCompleted, size > 0 else { throw ScanFailure.message("Reconstruction finished without a usable model file.") }
                            try update(id) { $0.modelName = fileName; $0.stage = .completed; $0.message = nil }
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
                    case .stitchingIncomplete: log(id, "Warning: framework reports incomplete stitching")
                    default: break
                    }
                }
                throw ScanFailure.message("Reconstruction output stream ended before completion. Inputs retained.")
            } catch {
                stage(id, stopReason == nil ? .failed : .interrupted, message: stopReason ?? error.localizedDescription)
                self.error = "Reconstruction: \(stopReason ?? error.localizedDescription). Inputs and previous outputs are retained."
                endProcessing()
            }
        }
    }

    func cancelReconstruction() { reconstruction?.cancel() }

    private func endProcessing() {
        reconstruction = nil
        isProcessing = false
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
    }

    func export(_ id: UUID, units: ExportUnits) async -> [URL]? {
        guard !busy, let source = model(id) else { return nil }
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
            Units: \(units.rawValue)
            Coordinates = reconstructed meter coordinates × \(units.multiplier).
            OBJ has no universal unit declaration. Configure your importer for these units.
            Vertices: \(summary.vertices); triangles: \(summary.triangles)
            Bounds minimum: \(summary.minimum); maximum: \(summary.maximum)
            Normals included; scene transforms baked into vertex positions. No texture export.
            Recovered metric scale is not metrology-grade accuracy. Compare a known measurement.
            Original USDZ and capture inputs remain in this scan's folder.
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
            Stage: \(item.stage.rawValue)
            Saved images: \(imageCount(id))
            Message: \(item.message ?? "none")
            Export: \(item.exportMessage ?? "not exported")
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
