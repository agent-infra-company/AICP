import AppKit
import Foundation

final class CodexTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .codex

    private let bundleIdentifier = "com.openai.codex"
    private let pollInterval: TimeInterval
    private var isRunning = false

    init(pollInterval: TimeInterval = 10.0) {
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        } || FileManager.default.fileExists(atPath: "/Applications/Codex.app")
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        isRunning = true
        return AsyncStream { [weak self] continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                while self.isRunning && !Task.isCancelled {
                    let snapshots = self.checkPresence()
                    continuation.yield(snapshots)
                    try? await Task.sleep(for: .seconds(self.pollInterval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stopMonitoring() async {
        isRunning = false
    }

    private func checkPresence() -> [ExternalTaskSnapshot] {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        guard isRunning else { return [] }

        return [
            ExternalTaskSnapshot(
                id: "codex-app",
                sourceKind: .codex,
                title: "Codex",
                workspace: nil,
                status: .running,
                progress: "Active",
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: Date(),
                deepLinkURL: URL(string: "codex://"),
                metadata: [:]
            )
        ]
    }
}
