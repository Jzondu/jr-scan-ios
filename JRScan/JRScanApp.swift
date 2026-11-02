import SwiftUI
import AVFoundation
import RealityKit
import UIKit

@main
struct JRScanApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup { ScanListView() }
    }
}

@MainActor
final class InstallCheck: ObservableObject {
    @Published var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var persistence = "Not checked"
    @Published var savedID = ""
    @Published var launches = 0
    @Published var error: String?

    struct Marker: Codable {
        let id: UUID
        let created: Date
        var launches: Int
    }

    func checkStorage() {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true)
            let file = directory.appendingPathComponent("install-check.json")
            let existed = FileManager.default.fileExists(atPath: file.path)
            var marker = existed
                ? try JSONDecoder().decode(Marker.self, from: Data(contentsOf: file))
                : Marker(id: UUID(), created: Date(), launches: 0)
            marker.launches += 1
            try JSONEncoder().encode(marker).write(to: file, options: .atomic)
            let verified = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: file))
            guard verified.id == marker.id, verified.launches == marker.launches else {
                throw CocoaError(.fileReadCorruptFile)
            }
            savedID = verified.id.uuidString
            launches = verified.launches
            persistence = existed ? "Existing marker read and updated" : "New marker saved and read back"
            error = nil
        } catch {
            persistence = "Failed"
            self.error = error.localizedDescription
        }
    }

    func refreshCamera() { camera = AVCaptureDevice.authorizationStatus(for: .video) }

    func requestCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        refreshCamera()
    }

    var cameraDescription: String {
        switch camera {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not requested"
        case .denied: return "Denied — enable Camera in Settings"
        case .restricted: return "Restricted by device policy"
        @unknown default: return "Unknown camera permission"
        }
    }
}

struct InstallCheckView: View {
    @StateObject private var check = InstallCheck()
    @Environment(\.scenePhase) private var scenePhase

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Installation check") {
                    Text("JR Scan \(version)")
                    Text("iOS \(UIDevice.current.systemVersion)")
                    Text(Bundle.main.bundleIdentifier ?? "Unknown identity")
                        .font(.caption).textSelection(.enabled)
                    Text("This first build verifies installation and local storage. Scanning follows after this device check passes.")
                }
                Section("Device capabilities") {
                    LabeledContent("Object Capture", value: ObjectCaptureSession.isSupported ? "Supported" : "Unsupported")
                    LabeledContent("Reconstruction", value: PhotogrammetrySession.isSupported ? "Supported" : "Unsupported")
                    if !ObjectCaptureSession.isSupported || !PhotogrammetrySession.isSupported {
                        Text("This device or OS does not support the required on-device workflow.")
                    }
                }
                Section("Camera") {
                    Text(check.cameraDescription)
                    if check.camera == .notDetermined {
                        Button("Allow camera access") { Task { await check.requestCamera() } }
                    }
                    if check.camera == .denied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                Section("Local persistence") {
                    Text(check.persistence)
                    Text("Launch count: \(check.launches)")
                    Text(check.savedID).font(.caption).textSelection(.enabled)
                    Text("Note this ID, force-close, then reopen. The ID should stay the same and the count should increase. Repeat after an in-place update.")
                    if let error = check.error { Text(error).foregroundStyle(.red) }
                }
                Section("Data") {
                    Text("Processing will run on your iPhone, without a runtime server. Uninstalling can remove local data; export important scans before updates or removal.")
                }
            }
            .navigationTitle("JR Scan")
            .onAppear {
                if check.launches == 0 { check.checkStorage() }
                check.refreshCamera()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { check.refreshCamera() }
            }
        }
    }
}
