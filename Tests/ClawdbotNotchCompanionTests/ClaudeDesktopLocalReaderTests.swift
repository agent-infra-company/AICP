import Foundation
import XCTest
@testable import ClawdbotNotchCompanion

final class ClaudeDesktopLocalReaderTests: XCTestCase {
    func testReadRecentSessionsParsesCompletedSessionFromAuditLog() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeSession(
            root: root,
            sessionId: "local_test-complete",
            title: "Ship release notes",
            initialMessage: "help me ship",
            lastActivityAt: 1_772_923_278_647,
            auditLines: [
                #"{"type":"result","subtype":"success","is_error":false}"#
            ]
        )

        let reader = ClaudeDesktopLocalReader(sessionsRoot: root.path)
        let sessions = reader.readRecentSessions(limit: 3, desktopIsRunning: true)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.title, "Ship release notes")
        XCTAssertEqual(sessions.first?.status, .completed)
        XCTAssertEqual(sessions.first?.model, "claude-opus-4-6")
    }

    func testReadRecentSessionsFallsBackToRunningForActiveSession() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let nowMilliseconds = Int(Date().timeIntervalSince1970 * 1000)
        try writeSession(
            root: root,
            sessionId: "local_test-running",
            title: "",
            initialMessage: "Investigate payments",
            lastActivityAt: nowMilliseconds,
            auditLines: [
                #"{"type":"user","message":{"role":"user","content":"Investigate payments"}}"#
            ]
        )

        let reader = ClaudeDesktopLocalReader(sessionsRoot: root.path)
        let sessions = reader.readRecentSessions(limit: 3, desktopIsRunning: true)

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.title, "Investigate payments")
        XCTAssertEqual(sessions.first?.status, .running)
    }

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSession(
        root: URL,
        sessionId: String,
        title: String,
        initialMessage: String,
        lastActivityAt: Int,
        auditLines: [String]
    ) throws {
        let baseDir = root
            .appendingPathComponent("workspace")
            .appendingPathComponent("org")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let sessionJSONURL = baseDir.appendingPathComponent("\(sessionId).json")
        let auditDir = baseDir.appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(at: auditDir, withIntermediateDirectories: true)

        let payload = """
        {
          "sessionId": "\(sessionId)",
          "cliSessionId": "cli-\(sessionId)",
          "createdAt": \(lastActivityAt - 1000),
          "lastActivityAt": \(lastActivityAt),
          "model": "claude-opus-4-6",
          "isArchived": false,
          "title": "\(title)",
          "initialMessage": "\(initialMessage)"
        }
        """
        try payload.write(to: sessionJSONURL, atomically: true, encoding: .utf8)

        let auditURL = auditDir.appendingPathComponent("audit.jsonl")
        try auditLines.joined(separator: "\n").write(to: auditURL, atomically: true, encoding: .utf8)
    }
}
