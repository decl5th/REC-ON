import Foundation
import OSLog

nonisolated enum RECONDiagnostics {
    private static let logger = Logger(subsystem: "com.C5RECON", category: "DeviceValidation")

    static let sessionID: String = {
        ProcessInfo.processInfo.environment["RECON_TEST_SESSION"] ?? "manual"
    }()

    static func emit(_ event: String, detail: String = "") {
        let suffix = detail.isEmpty ? "" : " \(detail)"
        let message = "[RECON_DIAG] session=\(sessionID) event=\(event)\(suffix)"
        print(message)
        logger.info("\(message, privacy: .public)")
    }
}

nonisolated final class DiagnosticCounter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "recon.diagnostics.counter")
    private var value = 0

    func increment() -> Int {
        queue.sync {
            value += 1
            return value
        }
    }
}
