import Foundation

/// Do not log arbitrary NSError userInfo, which can contain input data.
enum ReconstructionFailure {
    static func details(_ error: Error, stage: String) -> String {
        var lines = ["Processing stage: \(stage)",
                     "Swift error type: \(String(reflecting: type(of: error)))"]
        // Keep a simple enum case (e.g. processError) when available, but never
        // print a generic NSError description that serializes its userInfo.
        let value = String(describing: error)
        if value.range(of: "^[A-Za-z_][A-Za-z0-9_.]*$", options: .regularExpression) != nil {
            lines.append("Swift error case: \(value)")
        }
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()
        for depth in 0..<4 {
            guard let item = current, seen.insert(ObjectIdentifier(item)).inserted else { break }
            lines.append("\(depth == 0 ? "Error" : "Underlying error"): \(item.domain) (\(item.code))")
            lines.append("Description: \(String(item.localizedDescription.prefix(1500)))")
            if let reason = item.localizedFailureReason { lines.append("Reason: \(String(reason.prefix(1500)))") }
            if let recovery = item.localizedRecoverySuggestion { lines.append("Recovery: \(String(recovery.prefix(1500)))") }
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return lines.joined(separator: "\n")
    }

    static func message(_ error: Error) -> String {
        let nsError = error as NSError
        return "Reconstruction failed: \(error.localizedDescription) [\(nsError.domain), code \(nsError.code)]. Saved images and original checkpoints are retained. Retry saved input; if it fails again, try the option without object masking and checkpoints, then share diagnostic text."
    }
}

enum ReconstructionMode: String {
    case guided, withoutMasking
}
