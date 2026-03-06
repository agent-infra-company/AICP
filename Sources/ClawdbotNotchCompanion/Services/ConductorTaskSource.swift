import Foundation
import SQLite3

final class ConductorTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .conductor

    private let dbPath: String
    private let pollInterval: TimeInterval
    private var isRunning = false

    init(
        dbPath: String? = nil,
        pollInterval: TimeInterval = 3.0
    ) {
        if let dbPath {
            self.dbPath = dbPath
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.dbPath = appSupport
                .appendingPathComponent("com.conductor.app")
                .appendingPathComponent("conductor.db")
                .path
        }
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: dbPath)
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

    private func pollDatabase() -> [ExternalTaskSnapshot] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_close(db) }

        let query = """
            SELECT s.id, s.status, s.agent_type, s.title, s.model,
                   s.permission_mode, s.updated_at,
                   w.directory_name, w.branch, w.derived_status
            FROM sessions s
            LEFT JOIN workspaces w ON s.workspace_id = w.id
            WHERE s.is_hidden = 0
              AND (s.status IN ('working', 'needs_plan_response')
                   OR (s.status = 'error' AND w.state NOT IN ('archived')))
            ORDER BY s.updated_at DESC
            LIMIT 50
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var snapshots: [ExternalTaskSnapshot] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = columnText(stmt, 0) ?? ""
            let status = columnText(stmt, 1) ?? ""
            let agentType = columnText(stmt, 2) ?? "claude"
            let title = columnText(stmt, 3) ?? "Untitled"
            let model = columnText(stmt, 4) ?? ""
            let permissionMode = columnText(stmt, 5) ?? ""
            let updatedAtStr = columnText(stmt, 6) ?? ""
            let directoryName = columnText(stmt, 7)
            let branch = columnText(stmt, 8)
            let derivedStatus = columnText(stmt, 9)

            let taskStatus = mapStatus(status)
            let updatedAt = parseDate(updatedAtStr) ?? Date()

            var metadata: [String: String] = [
                "agentType": agentType,
                "model": model,
            ]
            if let branch { metadata["branch"] = branch }
            if let permissionMode = permissionMode.isEmpty ? nil : permissionMode {
                metadata["permissionMode"] = permissionMode
            }
            if let derivedStatus { metadata["derivedStatus"] = derivedStatus }

            let snapshot = ExternalTaskSnapshot(
                id: sessionId,
                sourceKind: .conductor,
                title: title,
                workspace: directoryName,
                status: taskStatus,
                progress: taskStatus == .running ? "Working..." : nil,
                needsInputPrompt: taskStatus == .needsInput ? "Plan ready for review" : nil,
                lastError: taskStatus == .failed ? "Session error" : nil,
                updatedAt: updatedAt,
                deepLinkURL: URL(string: "conductor://"),
                metadata: metadata
            )
            snapshots.append(snapshot)
        }

        return snapshots
    }

    private func mapStatus(_ status: String) -> TaskStatus {
        switch status {
        case "working": return .running
        case "needs_plan_response": return .needsInput
        case "error": return .failed
        case "idle": return .completed
        default: return .running
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    private func parseDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: str)
    }
}
