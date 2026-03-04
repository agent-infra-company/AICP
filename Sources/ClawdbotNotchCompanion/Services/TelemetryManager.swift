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

final class LocalTelemetryManager: TelemetryManaging {
    private let queue = DispatchQueue(label: "clawdbot.telemetry")
    private let fileURL: URL
    private var optIn: Bool = false

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = appSupport
                .appendingPathComponent("ClawdbotNotchCompanion", isDirectory: true)
                .appendingPathComponent("telemetry.log")
        }
    }

    func setOptIn(_ enabled: Bool) {
        queue.async {
            self.optIn = enabled
        }
    }

    func record(_ event: TelemetryEvent) {
        queue.async {
            guard self.optIn else {
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: self.fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                var payload = event.payload
                payload["kind"] = event.kind
                payload["timestamp"] = ISO8601DateFormatter().string(from: Date())
                let data = try JSONSerialization.data(withJSONObject: payload)

                if FileManager.default.fileExists(atPath: self.fileURL.path) {
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
}
