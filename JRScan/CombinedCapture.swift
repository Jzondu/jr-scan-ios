import Foundation
import RealityKit

enum CombinedCapture {
    // Reads at most 12 saved samples serially; no images or metadata leave the phone.
    // Absence of exposed depth is reported, never fabricated or treated as a guarantee.
    static func audit(_ directory: URL) async throws -> String {
        let images = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["heic","heif","jpg","jpeg","png","tif","tiff"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(12)
        var withDepth = 0, readable = 0, failed = 0
        for url in images {
            try Task.checkCancellation()
            do {
                let sample = try await PhotogrammetrySample(contentsOf: url)
                readable += 1
                if sample.depthDataMap != nil { withDepth += 1 }
            } catch is CancellationError { throw CancellationError() }
            catch { failed += 1 }
        }
        return "Saved-input sample: \(withDepth)/\(readable) readable photos expose depth data; \(failed) unreadable. Checked up to 12 photos. " +
            (withDepth > 0 ? "Photo + depth inputs present; final detail depends on capture quality." : "Depth not verified in this sample; no combined-data guarantee. Original inputs retained.")
    }
}
