import AppKit
import Foundation
import os.log

final class ClaudeDesktopTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .claudeDesktop

    private static let log = ControlPlaneDiagnostics.logger(category: "ClaudeDesktopTaskSource")

    private let bundleIdentifier = "com.anthropic.claudefordesktop"
    private let pollInterval: TimeInterval
    private var isRunning = false
    private let localReader: ClaudeDesktopLocalReader

    init(
        pollInterval: TimeInterval = 10.0,
        localReader: ClaudeDesktopLocalReader = ClaudeDesktopLocalReader()
    ) {
        self.pollInterval = pollInterval
        self.localReader = localReader
    }

    func isAvailable() async -> Bool {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        let isInstalled = FileManager.default.fileExists(atPath: "/Applications/Claude.app")
        let hasLocalSessions = localReader.hasLocalSessions()
        let available = isRunning || isInstalled || hasLocalSessions

        Self.log.debug(
            "Availability available=\(available) running=\(isRunning) installed=\(isInstalled) localSessions=\(hasLocalSessions)"
        )

        return available
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
                    let snapshots = self.readRecentSessions()
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

    private func readRecentSessions() -> [ExternalTaskSnapshot] {
        let isDesktopRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        let sessions = localReader.readRecentSessions(limit: 6, desktopIsRunning: isDesktopRunning)
            .filter { session in
                session.status == .running || Date().timeIntervalSince(session.lastActivityAt) < 7200
            }

        Self.log.debug(
            "Read recent sessions running=\(isDesktopRunning) eligibleSessions=\(sessions.count)"
        )

        if sessions.isEmpty {
            return []
        }

        return sessions.map { session in
            var metadata: [String: String] = ["sessionId": session.sessionId]
            if let cliSessionId = session.cliSessionId {
                metadata["cliSessionId"] = cliSessionId
            }
            if let model = session.model {
                metadata["model"] = model
            }
            if let processName = session.processName {
                metadata["processName"] = processName
            }

            let progress = session.model.map { $0.replacingOccurrences(of: "claude-", with: "") }

            return ExternalTaskSnapshot(
                id: session.sessionId,
                sourceKind: .claudeDesktop,
                title: session.title,
                workspace: nil,
                status: session.status,
                progress: progress,
                needsInputPrompt: nil,
                lastError: session.lastError,
                updatedAt: session.lastActivityAt,
                deepLinkURL: URL(string: "claude://"),
                metadata: metadata
            )
        }
    }
}
