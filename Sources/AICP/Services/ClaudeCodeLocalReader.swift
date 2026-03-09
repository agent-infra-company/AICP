import Foundation

/// Reads Claude Code's local state from ~/.claude/ for rich session metadata.
final class ClaudeCodeLocalReader: @unchecked Sendable {

    private let claudeDir: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.claudeDir = "\(home)/.claude"
    }

    // MARK: - Session Discovery

    struct SessionInfo {
        let sessionId: String
        let projectPath: String
        let encodedProjectDir: String
        let title: String
        let gitBranch: String?
        let model: String?
        let version: String?
        let slug: String?
        let permissionMode: String?
        let lastTimestamp: Date?
        let detectedStatus: TaskStatus
    }

    /// Given a CWD from a running process, find the most recent session JSONL and extract metadata.
    func readSessionForCWD(_ cwd: String) -> SessionInfo? {
        let encoded = encodeProjectPath(cwd)
        let projectDir = "\(claudeDir)/projects/\(encoded)"

        guard FileManager.default.fileExists(atPath: projectDir) else { return nil }

        // Find the most recently modified .jsonl file in the project dir
        guard let jsonlFile = mostRecentJSONL(in: projectDir) else { return nil }

        let sessionId = URL(fileURLWithPath: jsonlFile).deletingPathExtension().lastPathComponent
        return parseSessionJSONL(path: jsonlFile, sessionId: sessionId, projectPath: cwd, encodedDir: encoded)
    }

    /// Read a specific session by ID and CWD. Used when we know the exact sessionId
    /// (e.g. from --resume on the command line).
    func readSession(id sessionId: String, cwd: String) -> SessionInfo? {
        let encoded = encodeProjectPath(cwd)
        let projectDir = "\(claudeDir)/projects/\(encoded)"
        let path = "\(projectDir)/\(sessionId).jsonl"

        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return parseSessionJSONL(path: path, sessionId: sessionId, projectPath: cwd, encodedDir: encoded)
    }

    /// Find the most recent *active* (non-completed) session for a CWD.
    /// This avoids picking a stale completed session when a newer active one exists,
    /// and avoids misattributing another process's session to this PID.
    func readActiveSessionForCWD(_ cwd: String) -> SessionInfo? {
        let encoded = encodeProjectPath(cwd)
        let projectDir = "\(claudeDir)/projects/\(encoded)"

        guard FileManager.default.fileExists(atPath: projectDir) else { return nil }

        // Get JSONL files sorted by modification time (most recent first)
        let jsonlFiles = sortedJSONLFiles(in: projectDir)
        guard !jsonlFiles.isEmpty else { return nil }

        // First pass: find the most recently modified file with an active session
        for file in jsonlFiles {
            let sessionId = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
            guard let info = parseSessionJSONL(path: file, sessionId: sessionId, projectPath: cwd, encodedDir: encoded) else {
                continue
            }
            if info.detectedStatus != .completed {
                return info
            }
        }

        // Fallback: if all sessions are completed, return the most recent one
        let file = jsonlFiles[0]
        let sessionId = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        return parseSessionJSONL(path: file, sessionId: sessionId, projectPath: cwd, encodedDir: encoded)
    }

    // MARK: - History

    struct HistoryEntry {
        let display: String
        let timestamp: Date
        let project: String
        let sessionId: String
    }

    /// Read the last N entries from history.jsonl
    func readRecentHistory(limit: Int = 50) -> [HistoryEntry] {
        let path = "\(claudeDir)/history.jsonl"
        guard let lines = tailLines(path: path, count: limit) else { return [] }

        var entries: [HistoryEntry] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let display = obj["display"] as? String,
                  let timestamp = obj["timestamp"] as? Double,
                  let project = obj["project"] as? String,
                  let sessionId = obj["sessionId"] as? String
            else { continue }

            entries.append(HistoryEntry(
                display: display,
                timestamp: Date(timeIntervalSince1970: timestamp / 1000),
                project: project,
                sessionId: sessionId
            ))
        }
        return entries
    }

    // MARK: - Tasks

    struct ClaudeTask {
        let id: String
        let subject: String
        let description: String
        let activeForm: String?
        let status: String
        let blocks: [String]
        let blockedBy: [String]
    }

    /// Read task files from ~/.claude/tasks/
    func readActiveTasks() -> [ClaudeTask] {
        let tasksDir = "\(claudeDir)/tasks"
        guard FileManager.default.fileExists(atPath: tasksDir) else { return [] }

        var tasks: [ClaudeTask] = []
        guard let uuidDirs = try? FileManager.default.contentsOfDirectory(atPath: tasksDir) else { return [] }

        for uuidDir in uuidDirs.suffix(10) { // Only check last 10 task groups
            let groupPath = "\(tasksDir)/\(uuidDir)"
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: groupPath) else { continue }

            for file in files where file.hasSuffix(".json") {
                let filePath = "\(groupPath)/\(file)"
                guard let data = FileManager.default.contents(atPath: filePath),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = obj["id"] as? String,
                      let subject = obj["subject"] as? String,
                      let status = obj["status"] as? String
                else { continue }

                // Only include non-completed, non-deleted tasks
                guard status == "pending" || status == "in_progress" else { continue }

                tasks.append(ClaudeTask(
                    id: id,
                    subject: subject,
                    description: obj["description"] as? String ?? "",
                    activeForm: obj["activeForm"] as? String,
                    status: status,
                    blocks: obj["blocks"] as? [String] ?? [],
                    blockedBy: obj["blockedBy"] as? [String] ?? []
                ))
            }
        }
        return tasks
    }

    // MARK: - Private Helpers

    /// Encode a filesystem path to Claude Code's project directory naming convention.
    /// `/Users/foo/myproject` → `-Users-foo-myproject`
    private func encodeProjectPath(_ path: String) -> String {
        return path.replacingOccurrences(of: "/", with: "-")
    }

    /// Return all .jsonl files in a directory sorted by modification time (most recent first).
    private func sortedJSONLFiles(in directory: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }

        let jsonlFiles = contents.filter { $0.hasSuffix(".jsonl") }
        guard !jsonlFiles.isEmpty else { return [] }

        var candidates: [(path: String, modified: Date)] = []
        for file in jsonlFiles {
            let fullPath = "\(directory)/\(file)"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
               let modified = attrs[.modificationDate] as? Date {
                candidates.append((fullPath, modified))
            }
        }

        return candidates
            .sorted { $0.modified > $1.modified }
            .map(\.path)
    }

    /// Find the most recently modified .jsonl file in a directory.
    private func mostRecentJSONL(in directory: String) -> String? {
        sortedJSONLFiles(in: directory).first
    }

    /// Parse a session JSONL file to extract metadata.
    /// Only reads the first few lines (for title) and last few lines (for current state).
    private func parseSessionJSONL(path: String, sessionId: String, projectPath: String, encodedDir: String) -> SessionInfo? {
        // Read first lines to get the initial user message (title)
        let firstLines = headLines(path: path, count: 10)
        // Read last lines to get current state
        let lastLines = tailLines(path: path, count: 20)

        var title = "Claude Code session"
        var gitBranch: String?
        var model: String?
        var version: String?
        var slug: String?
        var permissionMode: String?
        var lastTimestamp: Date?

        // Extract title from first user message
        if let firstLines {
            for line in firstLines {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = obj["type"] as? String
                else { continue }

                if type == "user", let message = obj["message"] as? [String: Any] {
                    if let content = message["content"] as? String {
                        title = extractUserPrompt(from: content)
                    } else if let content = message["content"] as? [[String: Any]] {
                        // Content array format — find first text block
                        for block in content {
                            if let text = block["text"] as? String {
                                title = extractUserPrompt(from: text)
                                break
                            }
                        }
                    }
                    // Also grab metadata from this first user entry
                    gitBranch = obj["gitBranch"] as? String
                    version = obj["version"] as? String
                    slug = obj["slug"] as? String
                    permissionMode = obj["permissionMode"] as? String
                    break
                }
            }
        }

        // Extract latest state from tail
        var detectedStatus: TaskStatus = .running
        if let lastLines {
            for line in lastLines.reversed() {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                // Update with latest metadata from any entry that has it
                if let branch = obj["gitBranch"] as? String { gitBranch = branch }
                if let v = obj["version"] as? String { version = v }
                if let s = obj["slug"] as? String { slug = s }
                if let pm = obj["permissionMode"] as? String { permissionMode = pm }

                // Get model from assistant messages
                if let message = obj["message"] as? [String: Any],
                   let m = message["model"] as? String {
                    model = m
                }

                // Get timestamp (use the most recent one, not the first found)
                if let ts = obj["timestamp"] as? String,
                   let parsed = parseISO8601(ts) {
                    if lastTimestamp == nil || parsed > lastTimestamp! {
                        lastTimestamp = parsed
                    }
                }
            }

            // Detect status from the last JSONL entries (most recent first)
            detectedStatus = detectSessionStatus(from: lastLines)
        }

        return SessionInfo(
            sessionId: sessionId,
            projectPath: projectPath,
            encodedProjectDir: encodedDir,
            title: title,
            gitBranch: gitBranch,
            model: model,
            version: version,
            slug: slug,
            permissionMode: permissionMode,
            lastTimestamp: lastTimestamp,
            detectedStatus: detectedStatus
        )
    }

    /// Strip <system_instruction> and <system-instruction> tags from user content
    /// to extract the actual user prompt.
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

        // Trim whitespace and newlines
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to 80 chars for display
        if text.count > 80 {
            text = String(text.prefix(77)) + "..."
        }

        return text.isEmpty ? "Claude Code session" : text
    }

    /// Detect session status from the last JSONL entries.
    /// Claude Code JSONL entries have a "type" field: "user", "assistant", "result", "tool_use", "tool_result".
    /// - If last meaningful entry is "result" → completed
    /// - If last meaningful entry is "assistant" with stop_reason "end_turn" and no pending tool_use → needsInput (waiting for user)
    /// - Otherwise → running
    private func detectSessionStatus(from lastLines: [String]) -> TaskStatus {
        // Walk backwards through lines to find the last meaningful entry
        for line in lastLines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            switch type {
            case "result":
                // Session has ended
                return .completed

            case "assistant":
                if let message = obj["message"] as? [String: Any],
                   let stopReason = message["stop_reason"] as? String {
                    if stopReason == "end_turn" {
                        // Assistant finished — waiting for user response
                        return .needsInput
                    }
                    if stopReason == "tool_use" {
                        // Assistant requested a tool — CLI is paused for permission approval
                        return .needsInput
                    }
                }
                return .running

            case "user":
                // Last entry is a user message — model is processing
                return .running

            default:
                continue
            }
        }
        return .running
    }

    private func parseISO8601(_ str: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }

    /// Read the first N lines of a file.
    private func headLines(path: String, count: Int) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        // Read a chunk from the beginning (16KB should be plenty for first few entries)
        let data = handle.readData(ofLength: 16384)
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Array(lines.prefix(count))
    }

    /// Read the last N lines of a file efficiently.
    private func tailLines(path: String, count: Int) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return nil }

        // Read last 64KB — enough for ~20 JSONL entries
        let readSize: UInt64 = min(fileSize, 65536)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Array(lines.suffix(count))
    }
}
