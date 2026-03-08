import AppKit
import Foundation
import SQLite3

final class CodexTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .codex

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
        FileManager.default.fileExists(atPath: dbPath)
            || NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
            || FileManager.default.fileExists(atPath: "/Applications/Codex.app")
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
            print("[CodexTaskSource] DB not found at \(dbPath)")
            return checkPresenceFallback()
        }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK else {
            print("[CodexTaskSource] sqlite3_open_v2 failed: \(rc)")
            return checkPresenceFallback()
        }
        defer { sqlite3_close(db) }

        let runningWorkspaces = findRunningCodexWorkspaces()
        let isDesktopAppRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
        print("[CodexTaskSource] poll: runningWorkspaces=\(runningWorkspaces), isDesktopAppRunning=\(isDesktopAppRunning)")

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

        print("[CodexTaskSource] total snapshots: \(snapshots.count) (threads=\(threadSnapshots.count), jobs=\(jobSnapshots.count))")
        for s in snapshots.prefix(3) {
            print("[CodexTaskSource]   \(s.id) status=\(s.status) title=\(s.title.prefix(40))")
        }

        return snapshots
    }

    private func queryThreads(
        db: OpaquePointer?,
        runningWorkspaces: Set<String>,
        isDesktopAppRunning: Bool
    ) -> [ExternalTaskSnapshot] {
        let query = """
            SELECT id, title, cwd, model_provider, approval_mode,
                   updated_at, git_branch, tokens_used, cli_version,
                   first_user_message, agent_nickname, source
            FROM threads
            WHERE archived = 0
            ORDER BY updated_at DESC
            LIMIT 50
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var snapshots: [ExternalTaskSnapshot] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let threadId = columnText(stmt, 0) ?? ""
            let rawTitle = columnText(stmt, 1) ?? "Untitled"
            let cwd = columnText(stmt, 2)
            let modelProvider = columnText(stmt, 3) ?? ""
            let approvalMode = columnText(stmt, 4) ?? ""
            let updatedAt = sqlite3_column_int64(stmt, 5)
            let gitBranch = columnText(stmt, 6)
            let tokensUsed = sqlite3_column_int64(stmt, 7)
            let cliVersion = columnText(stmt, 8)
            let firstUserMessage = columnText(stmt, 9)
            let agentNickname = columnText(stmt, 10)
            let source = columnText(stmt, 11) ?? ""

            if isConductorManagedThread(firstUserMessage: firstUserMessage) {
                continue
            }

            // Extract the actual user prompt (strip system instructions)
            let title = extractUserPrompt(from: firstUserMessage ?? rawTitle)

            let workspaceName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }

            let updatedDate = Date(timeIntervalSince1970: TimeInterval(updatedAt))
            let age = Date().timeIntervalSince(updatedDate)
            let isActiveCLIWorkspace = cwd.map { runningWorkspaces.contains($0) } ?? false
            let status: TaskStatus
            if isActiveCLIWorkspace || (isDesktopAppRunning && age < 1800) {
                status = .running
            } else {
                status = .completed
            }

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
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var workspaces: Set<String> = []
        for line in output.components(separatedBy: "\n") {
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-Fn", "-d", "cwd"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.components(separatedBy: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// Fallback to simple presence check if SQLite is unavailable
    private func checkPresenceFallback() -> [ExternalTaskSnapshot] {
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

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}
