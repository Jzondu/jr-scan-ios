import Foundation

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
    var passesStarted: Int?
    var depthSummary: String?
    var referenceScanID: UUID?
    var captureKind: String? // nil = existing photo/Object Capture scan.
}

