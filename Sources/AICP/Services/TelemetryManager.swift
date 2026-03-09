import Foundation

protocol TelemetryManaging: AnyObject {
    func setOptIn(_ enabled: Bool)
    func record(_ event: TelemetryEvent)
}

enum TelemetryEvent {
    case taskSubmitted(taskId: String, profileId: UUID, routeId: String)
    case taskAutoRetry(taskId: String, count: Int)
    case runtimeAction(String, profileId: UUID, healthy: Bool)
    case error(String)

    var kind: String {
        switch self {
        case .taskSubmitted:
            "task_submitted"
        case .taskAutoRetry:
            "task_auto_retry"
        case .runtimeAction:
            "runtime_action"
        case .error:
            "error"
        }
    }

    var payload: [String: String] {
        switch self {
        case let .taskSubmitted(taskId, profileId, routeId):
            return [
                "taskId": taskId,
                "profileId": profileId.uuidString,
                "routeId": routeId
            ]
        case let .taskAutoRetry(taskId, count):
            return [
                "taskId": taskId,
                "count": String(count)
            ]
        case let .runtimeAction(action, profileId, healthy):
            return [
                "action": action,
                "profileId": profileId.uuidString,
                "healthy": String(healthy)
            ]
        case let .error(message):
            return [
                "message": message
            ]
        }
    }
}

final class LocalTelemetryManager: TelemetryManaging, @unchecked Sendable {
    private let queue = DispatchQueue(label: "aicp.telemetry")
    private let fileURL: URL
    private var optIn: Bool = false

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = appSupport
                .appendingPathComponent("AICP", isDirectory: true)
                .appendingPathComponent("telemetry.log")
        }
    }

    func setOptIn(_ enabled: Bool) {
        queue.async {
            self.optIn = enabled
        }
    }

    /// Maximum telemetry log size before rotation (5 MB).
    private static let maxLogSize: UInt64 = 5_000_000

    func record(_ event: TelemetryEvent) {
        queue.async {
            guard self.optIn else {
                return
            }

            do {
                let fm = FileManager.default
                try fm.createDirectory(
                    at: self.fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Rotate if the log exceeds the size limit.
                self.rotateIfNeeded()

                var payload = event.payload
                payload["kind"] = event.kind
                payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
                let data = try JSONSerialization.data(withJSONObject: payload)

                if fm.fileExists(atPath: self.fileURL.path) {
                    let handle = try FileHandle(forWritingTo: self.fileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    handle.write(data)
                    handle.write(Data("\n".utf8))
                } else {
                    var content = Data()
                    content.append(data)
                    content.append(Data("\n".utf8))
                    try content.write(to: self.fileURL)
                }
            } catch {
                // Telemetry is best-effort and should never break app behavior.
            }
        }
    }

    /// Rotates the log file when it exceeds `maxLogSize`.
    /// Keeps at most one rotated file (`telemetry.log.1`).
    private func rotateIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }

        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= Self.maxLogSize else {
            return
        }

        let rotatedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("telemetry.log.1")
        try? fm.removeItem(at: rotatedURL)
        try? fm.moveItem(at: fileURL, to: rotatedURL)
    }
}
