import AppKit
import Foundation

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

    private let bundleIdentifier = "com.todesktop.230313mzl4w4u92"
    private let pollInterval: TimeInterval
    private var isRunning = false
    private let parser = CursorProcessSnapshotParser()

    init(pollInterval: TimeInterval = 5.0) {
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        } || FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
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
        guard isCursorRunning else { return [] }

        guard let output = runCommand("/bin/ps", arguments: ["-axo", "command="]) else {
            return []
        }

        var rolesByWorkspace: [String: Set<CursorProcessSnapshotParser.Role>] = [:]

        for line in output.components(separatedBy: "\n") {
            guard let activity = parser.parse(line: line) else { continue }
            rolesByWorkspace[activity.workspace, default: []].insert(activity.role)
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

    private func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
