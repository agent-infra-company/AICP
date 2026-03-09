import AppKit
import Foundation
import os.log

struct CursorProcessSnapshotParser {
    enum Role: String, CaseIterable, Hashable, Comparable {
        case agentExec = "agent-exec"
        case retrieval = "retrieval-always-local"
        case user = "user"

        var displayName: String {
            switch self {
            case .agentExec: "Agent"
            case .retrieval: "Retrieval"
            case .user: "Chat"
            }
        }

        static func < (lhs: Role, rhs: Role) -> Bool {
            lhs.sortIndex < rhs.sortIndex
        }

        private var sortIndex: Int {
            switch self {
            case .agentExec: 0
            case .retrieval: 1
            case .user: 2
            }
        }
    }

    func parse(line: String) -> (workspace: String, role: Role)? {
        let marker = "Cursor Helper (Plugin): extension-host ("
        guard let markerRange = line.range(of: marker) else { return nil }

        let remainder = line[markerRange.upperBound...]
        guard let roleEnd = remainder.firstIndex(of: ")") else { return nil }

        let roleString = String(remainder[..<roleEnd])
        guard let role = Role(rawValue: roleString) else { return nil }

        let workspacePortion = String(remainder[remainder.index(after: roleEnd)...])
            .trimmingCharacters(in: .whitespaces)

        guard let suffixRange = workspacePortion.range(
            of: #" \[\d+-\d+\]$"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let workspace = workspacePortion[..<suffixRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)

        guard !workspace.isEmpty else { return nil }
        return (workspace, role)
    }

    func progressText(for roles: Set<Role>) -> String? {
        guard !roles.isEmpty else { return nil }
        return roles.sorted().map(\.displayName).joined(separator: " · ")
    }
}

final class CursorTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .cursor

    private static let log = CompanionDiagnostics.logger(category: "CursorTaskSource")

    private let bundleIdentifier = "com.todesktop.230313mzl4w4u92"
    private let pollInterval: TimeInterval
    private var isRunning = false
    private let parser = CursorProcessSnapshotParser()

    init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        let isInstalled = FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
        let available = isRunning || isInstalled

        Self.log.debug(
            "Availability available=\(available) running=\(isRunning) installed=\(isInstalled) bundleIdentifier=\(self.bundleIdentifier, privacy: .public)"
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
                    continuation.yield(self.scanProcesses())
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

    private func scanProcesses() -> [ExternalTaskSnapshot] {
        let isCursorRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        guard isCursorRunning else {
            Self.log.debug("Cursor scan skipped because app is not running")
            return []
        }

        guard let output = runCommand("/bin/ps", arguments: ["-axo", "command="], label: "ps") else {
            return []
        }

        var rolesByWorkspace: [String: Set<CursorProcessSnapshotParser.Role>] = [:]
        let lines = output.components(separatedBy: "\n")
        let cursorLines = lines.filter { $0.localizedCaseInsensitiveContains("Cursor") }
        var matchedActivities = 0

        for line in lines {
            guard let activity = parser.parse(line: line) else { continue }
            matchedActivities += 1
            rolesByWorkspace[activity.workspace, default: []].insert(activity.role)
        }

        if rolesByWorkspace.isEmpty {
            let sample = cursorLines.prefix(5).joined(separator: " || ")
            Self.log.warning(
                "Cursor is running but no extension-host activity matched matchedActivities=\(matchedActivities) sample=\(sample, privacy: .public)"
            )
        } else {
            Self.log.debug(
                "Cursor scan complete workspaces=\(rolesByWorkspace.count) matchedActivities=\(matchedActivities)"
            )
        }

        return rolesByWorkspace.keys.sorted().map { workspace in
            let roles = rolesByWorkspace[workspace, default: []]
            let progress = parser.progressText(for: roles)
            let title = roles.contains(.agentExec) ? "Agent session" : "AI chat"

            return ExternalTaskSnapshot(
                id: workspace.replacingOccurrences(of: " ", with: "-"),
                sourceKind: .cursor,
                title: title,
                workspace: workspace,
                status: .running,
                progress: progress,
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: Date(),
                deepLinkURL: nil,
                metadata: ["roles": roles.map(\.rawValue).sorted().joined(separator: ",")]
            )
        }
    }

    private func runCommand(_ path: String, arguments: [String], label: String) -> String? {
        ProcessProbe.run(path: path, arguments: arguments, logger: Self.log, label: label)
    }
}
