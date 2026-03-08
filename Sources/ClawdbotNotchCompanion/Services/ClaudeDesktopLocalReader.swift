import Foundation

final class ClaudeDesktopLocalReader: @unchecked Sendable {
    struct SessionInfo {
        let sessionId: String
        let cliSessionId: String?
        let title: String
        let model: String?
        let processName: String?
        let createdAt: Date
        let lastActivityAt: Date
        let status: TaskStatus
        let lastError: String?
    }

    private let sessionsRoot: String

    init(sessionsRoot: String? = nil) {
        if let sessionsRoot {
            self.sessionsRoot = sessionsRoot
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.sessionsRoot = "\(home)/Library/Application Support/Claude/local-agent-mode-sessions"
    }

    func hasLocalSessions() -> Bool {
        FileManager.default.fileExists(atPath: sessionsRoot)
    }

    func readRecentSessions(limit: Int = 6, desktopIsRunning: Bool) -> [SessionInfo] {
        let files = recentSessionFiles(limit: limit * 4)
        var sessions: [SessionInfo] = []

        for file in files {
            guard let session = parseSession(at: file, desktopIsRunning: desktopIsRunning) else {
                continue
            }

            sessions.append(session)
            if sessions.count == limit {
                break
            }
        }

        return sessions
    }

    private func recentSessionFiles(limit: Int) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: sessionsRoot) else {
            return []
        }

        var candidates: [(path: String, modifiedAt: Date)] = []

        for case let relativePath as String in enumerator {
            let fileName = URL(fileURLWithPath: relativePath).lastPathComponent
            guard fileName.hasPrefix("local_"), fileName.hasSuffix(".json") else {
                continue
            }

            let absolutePath = "\(sessionsRoot)/\(relativePath)"
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: absolutePath),
                  let modifiedAt = attributes[.modificationDate] as? Date else {
                continue
            }

            candidates.append((absolutePath, modifiedAt))
        }

        return candidates
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.path)
    }

    private func parseSession(at path: String, desktopIsRunning: Bool) -> SessionInfo? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let isArchived = object["isArchived"] as? Bool ?? false
        guard !isArchived else { return nil }

        guard let sessionId = object["sessionId"] as? String else { return nil }

        let createdAt = parseMilliseconds(object["createdAt"]) ?? Date.distantPast
        let lastActivityAt = parseMilliseconds(object["lastActivityAt"]) ?? createdAt
        let title = normalizedTitle(
            preferred: object["title"] as? String,
            fallback: object["initialMessage"] as? String
        )
        let statusInfo = readAuditStatus(
            sessionDirectory: path.replacingOccurrences(of: ".json", with: ""),
            desktopIsRunning: desktopIsRunning,
            lastActivityAt: lastActivityAt
        )

        return SessionInfo(
            sessionId: sessionId,
            cliSessionId: object["cliSessionId"] as? String,
            title: title,
            model: object["model"] as? String,
            processName: object["processName"] as? String,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            status: statusInfo.status,
            lastError: statusInfo.lastError
        )
    }

    private func readAuditStatus(
        sessionDirectory: String,
        desktopIsRunning: Bool,
        lastActivityAt: Date
    ) -> (status: TaskStatus, lastError: String?) {
        let auditPath = "\(sessionDirectory)/audit.jsonl"
        if let lines = tailLines(path: auditPath, count: 20) {
            for line in lines.reversed() {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = object["type"] as? String else {
                    continue
                }

                if type == "result" {
                    let isError = object["is_error"] as? Bool ?? false
                    let subtype = object["subtype"] as? String
                    if isError || subtype == "error" || subtype == "failed" {
                        return (.failed, "Session failed")
                    }
                    return (.completed, nil)
                }

                if type == "assistant" || type == "system" || type == "user" {
                    break
                }
            }
        }

        let age = Date().timeIntervalSince(lastActivityAt)
        if desktopIsRunning && age < 300 {
            return (.running, nil)
        }

        return (.completed, nil)
    }

    private func normalizedTitle(preferred: String?, fallback: String?) -> String {
        let rawTitle = [preferred, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? "Claude Desktop"

        if rawTitle.count > 80 {
            return String(rawTitle.prefix(77)) + "..."
        }

        return rawTitle
    }

    private func parseMilliseconds(_ value: Any?) -> Date? {
        if let milliseconds = value as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        if let milliseconds = value as? Int {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        if let milliseconds = value as? Int64 {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        return nil
    }

    private func tailLines(path: String, count: Int) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > 0 else { return nil }

        let readSize: UInt64 = min(fileSize, 32768)
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        return text
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(count)
            .map { $0 }
    }
}
