import AppKit
import Foundation
import SQLite3
import os.log

final class CodexTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .codex

    private static let log = CompanionDiagnostics.logger(category: "CodexTaskSource")

    private let bundleIdentifier = "com.openai.codex"
    private let dbPath: String
    private let pollInterval: TimeInterval
    private var isRunning = false

    init(pollInterval: TimeInterval = 5.0) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.codex/state_5.sqlite"
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        let existingDatabases = codexDatabaseCandidates().filter { FileManager.default.fileExists(atPath: $0) }
        let isAppRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
        let isInstalled = FileManager.default.fileExists(atPath: "/Applications/Codex.app")
        let available = !existingDatabases.isEmpty || isAppRunning || isInstalled

        Self.log.debug(
            "Availability available=\(available) appRunning=\(isAppRunning) installed=\(isInstalled) dbPath=\(self.dbPath, privacy: .public) existingDatabases=\(CompanionDiagnostics.joined(existingDatabases), privacy: .public)"
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
                    let snapshots = self.pollDatabase()
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

    // MARK: - Database Polling

    private func pollDatabase() -> [ExternalTaskSnapshot] {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            Self.log.warning(
                "Primary Codex DB missing path=\(self.dbPath, privacy: .public) candidates=\(CompanionDiagnostics.joined(self.codexDatabaseCandidates()), privacy: .public)"
            )
            return checkPresenceFallback()
        }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
            Self.log.error(
                "Failed to open Codex DB path=\(self.dbPath, privacy: .public) rc=\(rc) error=\(message, privacy: .public)"
            )
            return checkPresenceFallback()
        }
        defer { sqlite3_close(db) }

        let runningWorkspaces = findRunningCodexWorkspaces()
        let isDesktopAppRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        Self.log.debug(
            "Polling Codex DB runningWorkspaces=\(CompanionDiagnostics.joined(runningWorkspaces.sorted()), privacy: .public) desktopRunning=\(isDesktopAppRunning)"
        )

        var snapshots: [ExternalTaskSnapshot] = []

        // Query threads
        let threadSnapshots = queryThreads(
            db: db,
            runningWorkspaces: runningWorkspaces,
            isDesktopAppRunning: isDesktopAppRunning
        )
        snapshots.append(contentsOf: threadSnapshots)

        // Query active agent jobs
        let jobSnapshots = queryAgentJobs(db: db)
        snapshots.append(contentsOf: jobSnapshots)

        Self.log.debug(
            "Poll complete totalSnapshots=\(snapshots.count) threadSnapshots=\(threadSnapshots.count) jobSnapshots=\(jobSnapshots.count)"
        )
        for snapshot in snapshots.prefix(3) {
            Self.log.debug(
                "Snapshot id=\(snapshot.id, privacy: .public) status=\(String(describing: snapshot.status), privacy: .public) title=\(snapshot.title, privacy: .public)"
            )
        }

        return snapshots
    }

    private func queryThreads(
        db: OpaquePointer?,
        runningWorkspaces: Set<String>,
        isDesktopAppRunning: Bool
    ) -> [ExternalTaskSnapshot] {
        let query = """
            SELECT id, rollout_path, title, cwd, model_provider, approval_mode,
                   updated_at, git_branch, tokens_used, cli_version,
                   first_user_message, agent_nickname, source
            FROM threads
            WHERE archived = 0
            ORDER BY updated_at DESC
            LIMIT 50
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
            Self.log.error("Failed to prepare Codex thread query error=\(message, privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var snapshots: [ExternalTaskSnapshot] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let threadId = columnText(stmt, 0) ?? ""
            let rolloutPath = columnText(stmt, 1)
            let rawTitle = columnText(stmt, 2) ?? "Untitled"
            let cwd = columnText(stmt, 3)
            let modelProvider = columnText(stmt, 4) ?? ""
            let approvalMode = columnText(stmt, 5) ?? ""
            let updatedAt = sqlite3_column_int64(stmt, 6)
            let gitBranch = columnText(stmt, 7)
            let tokensUsed = sqlite3_column_int64(stmt, 8)
            let cliVersion = columnText(stmt, 9)
            let firstUserMessage = columnText(stmt, 10)
            let agentNickname = columnText(stmt, 11)
            let source = columnText(stmt, 12) ?? ""

            if isConductorManagedThread(firstUserMessage: firstUserMessage) {
                continue
            }

            // Extract the actual user prompt (strip system instructions)
            let title = extractUserPrompt(from: firstUserMessage ?? rawTitle)

            let workspaceName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

            let updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedAt))
            let age = Date().timeIntervalSince(updatedDate)
            let cliRolloutState = source == "cli" ? rolloutPath.flatMap(Self.cliRolloutState(atPath:)) : nil
            let status = Self.statusForThread(
                source: source,
                cwd: cwd,
                rolloutState: cliRolloutState,
                runningWorkspaces: runningWorkspaces,
                isDesktopAppRunning: isDesktopAppRunning,
                updatedDate: updatedDate
            )

            // Skip old completed threads (only show last hour)
            if status == .completed && age > 3600 { continue }

            var metadata: [String: String] = [
                "modelProvider": modelProvider,
                "approvalMode": approvalMode,
                "source": source,
            ]
            if let gitBranch { metadata["branch"] = gitBranch }
            if tokensUsed > 0 { metadata["tokensUsed"] = "\(tokensUsed)" }
            if let cliVersion { metadata["cliVersion"] = cliVersion }
            if let agentNickname { metadata["agentNickname"] = agentNickname }
            if let cwd { metadata["cwd"] = cwd }
            if let turnId = cliRolloutState?.turnId { metadata["turnId"] = turnId }

            // Build progress string
            var progressParts: [String] = []
            if source == "vscode" {
                progressParts.append("VS Code")
            }
            if let agentNickname, !agentNickname.isEmpty {
                progressParts.append(agentNickname)
            }
            if let gitBranch {
                progressParts.append(gitBranch)
            }
            if tokensUsed > 0 {
                progressParts.append("\(tokensUsed / 1000)K tokens")
            }
            let progress = progressParts.isEmpty
                ? (status == .running ? "Working..." : nil)
                : progressParts.joined(separator: " · ")

            let snapshot = ExternalTaskSnapshot(
                id: "codex-\(threadId)",
                sourceKind: .codex,
                title: title,
                workspace: workspaceName,
                status: status,
                progress: progress,
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: updatedDate,
                deepLinkURL: URL(string: "codex://"),
                metadata: metadata
            )
            snapshots.append(snapshot)
        }

        if snapshots.isEmpty {
            Self.log.debug(
                "No Codex thread snapshots were eligible runningWorkspaces=\(CompanionDiagnostics.joined(runningWorkspaces.sorted()), privacy: .public) desktopRunning=\(isDesktopAppRunning)"
            )
        }
        return snapshots
    }

    private func queryAgentJobs(db: OpaquePointer?) -> [ExternalTaskSnapshot] {
        let query = """
            SELECT id, name, status, instruction, last_error, updated_at
            FROM agent_jobs
            WHERE status NOT IN ('completed', 'cancelled')
            ORDER BY updated_at DESC
            LIMIT 20
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
            Self.log.error("Failed to prepare Codex agent job query error=\(message, privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var snapshots: [ExternalTaskSnapshot] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let jobId = columnText(stmt, 0) ?? ""
            let name = columnText(stmt, 1) ?? "Agent Job"
            let statusStr = columnText(stmt, 2) ?? ""
            let instruction = columnText(stmt, 3)
            let lastError = columnText(stmt, 4)
            let updatedAt = sqlite3_column_int64(stmt, 5)

            let status = mapJobStatus(statusStr)
            let updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedAt))

            let snapshot = ExternalTaskSnapshot(
                id: "codex-job-\(jobId)",
                sourceKind: .codex,
                title: name,
                workspace: nil,
                status: status,
                progress: instruction.map { String($0.prefix(80)) },
                needsInputPrompt: nil,
                lastError: lastError,
                updatedAt: updatedDate,
                deepLinkURL: URL(string: "codex://"),
                metadata: ["jobStatus": statusStr]
            )
            snapshots.append(snapshot)
        }

        return snapshots
    }

    // MARK: - Helpers

    private func mapJobStatus(_ status: String) -> TaskStatus {
        switch status {
        case "running", "in_progress": return .running
        case "pending", "queued": return .queued
        case "failed", "error": return .failed
        default: return .running
        }
    }

    static func statusForThread(
        source: String,
        cwd: String?,
        rolloutPath: String?,
        runningWorkspaces: Set<String>,
        isDesktopAppRunning: Bool,
        updatedDate: Date,
        now: Date = Date()
    ) -> TaskStatus {
        let rolloutState = rolloutPath.flatMap(cliRolloutState(atPath:))
        return statusForThread(
            source: source,
            cwd: cwd,
            rolloutState: rolloutState,
            runningWorkspaces: runningWorkspaces,
            isDesktopAppRunning: isDesktopAppRunning,
            updatedDate: updatedDate,
            now: now
        )
    }

    static func statusForThread(
        source: String,
        cwd: String?,
        rolloutState: CodexCLIRolloutState?,
        runningWorkspaces: Set<String>,
        isDesktopAppRunning: Bool,
        updatedDate: Date,
        now: Date = Date()
    ) -> TaskStatus {
        let age = now.timeIntervalSince(updatedDate)
        let isActiveCLIWorkspace = cwd.map { runningWorkspaces.contains($0) } ?? false

        if source == "cli" {
            if let rolloutState {
                return rolloutState.status
            }
            return isActiveCLIWorkspace ? .running : .completed
        }

        if isActiveCLIWorkspace || (isDesktopAppRunning && age < 1800) {
            return .running
        }

        return .completed
    }

    static func cliRolloutState(atPath path: String) -> CodexCLIRolloutState? {
        guard let tail = readRolloutTail(atPath: path, maxBytes: 65_536) else {
            return nil
        }

        let decoder = JSONDecoder()
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines.reversed() where !line.isEmpty {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(CodexRolloutEvent.self, from: data) else {
                continue
            }

            guard event.type == "event_msg" else { continue }

            switch event.payload.type {
            case "task_started":
                return CodexCLIRolloutState(status: .running, turnId: event.payload.turnId)
            case "task_complete":
                return CodexCLIRolloutState(status: .completed, turnId: event.payload.turnId)
            case "turn_aborted":
                return CodexCLIRolloutState(status: .canceled, turnId: event.payload.turnId)
            default:
                continue
            }
        }

        return nil
    }

    private static func readRolloutTail(atPath path: String, maxBytes: Int) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer {
            try? handle.close()
        }

        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        handle.seek(toFileOffset: offset)

        guard let tail = String(data: handle.readDataToEndOfFile(), encoding: .utf8) else {
            return nil
        }

        return tail
    }

    /// Strip <system_instruction> blocks from Codex title/first_user_message
    private func extractUserPrompt(from content: String) -> String {
        var text = content

        // Remove <system_instruction>...</system_instruction> blocks
        while let startRange = text.range(of: "<system_instruction>"),
              let endRange = text.range(of: "</system_instruction>") {
            let fullRange = startRange.lowerBound..<endRange.upperBound
            text.removeSubrange(fullRange)
        }

        // Remove <system-instruction>...</system-instruction> blocks
        while let startRange = text.range(of: "<system-instruction>"),
              let endRange = text.range(of: "</system-instruction>") {
            let fullRange = startRange.lowerBound..<endRange.upperBound
            text.removeSubrange(fullRange)
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > 80 {
            text = String(text.prefix(77)) + "..."
        }

        return text.isEmpty ? "Codex" : text
    }

    private func isConductorManagedThread(firstUserMessage: String?) -> Bool {
        guard let firstUserMessage else { return false }
        return firstUserMessage.contains("You are working inside Conductor")
            || firstUserMessage.contains("com.conductor.app")
    }

    private func findRunningCodexWorkspaces() -> Set<String> {
        guard let output = ProcessProbe.run(
            path: "/bin/ps",
            arguments: ["-axo", "pid=,command="],
            logger: Self.log,
            label: "ps"
        ) else {
            return []
        }

        var workspaces: Set<String> = []
        let lines = output.components(separatedBy: "\n")
        let codexLines = lines.filter { $0.localizedCaseInsensitiveContains("codex") }

        for line in lines {
            guard line.localizedCaseInsensitiveContains("codex") else { continue }
            guard !line.contains(".cursor/extensions/") else { continue }
            guard !line.contains("Cursor.app") else { continue }
            guard !line.contains("com.conductor.app") else { continue }
            guard !line.contains("app-server") else { continue }

            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let pidComponent = components.first, let pid = Int(pidComponent) else { continue }

            if let workspace = extractCDArgument(from: line) ?? extractCWD(pid: pid) {
                workspaces.insert(workspace)
            }
        }

        if workspaces.isEmpty && !codexLines.isEmpty {
            let sample = codexLines.prefix(5).joined(separator: " || ")
            Self.log.warning(
                "Codex-related processes found but no CLI workspaces were extracted sample=\(sample, privacy: .public)"
            )
        }

        return workspaces
    }

    private func extractCDArgument(from commandLine: String) -> String? {
        guard let range = commandLine.range(of: " --cd ") else { return nil }
        let remainder = commandLine[range.upperBound...]
        if let end = remainder.firstIndex(of: " ") {
            return String(remainder[..<end])
        }
        return String(remainder)
    }

    private func extractCWD(pid: Int) -> String? {
        guard let output = ProcessProbe.run(
            path: "/usr/sbin/lsof",
            arguments: ["-a", "-p", "\(pid)", "-Fn", "-d", "cwd"],
            logger: Self.log,
            label: "lsof"
        ) else {
            return nil
        }

        for line in output.components(separatedBy: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        Self.log.debug("No Codex CLI CWD found for pid=\(pid)")
        return nil
    }

    /// Fallback to simple presence check if SQLite is unavailable
    private func checkPresenceFallback() -> [ExternalTaskSnapshot] {
        let isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        guard isRunning else {
            Self.log.debug("Codex fallback returned no snapshots because desktop app is not running")
            return []
        }

        Self.log.debug("Using Codex app presence fallback")

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

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func codexDatabaseCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.codex/state_5.sqlite",
            "\(home)/.codex/sqlite/codex-dev.db",
        ]
    }
}

private struct CodexRolloutEvent: Decodable {
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let turnId: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case turnId = "turn_id"
        }
    }
}

struct CodexCLIRolloutState {
    let status: TaskStatus
    let turnId: String?
}
