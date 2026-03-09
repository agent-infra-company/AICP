import XCTest
@testable import AICP

final class ExternalSnapshotActivityDetectorTests: XCTestCase {
    func testNewSnapshotAlwaysAnnounces() {
        let snapshot = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(),
            metadata: ["source": "cli"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: nil, new: snapshot))
    }

    func testNeedsInputTurnAdvancementAnnounces() {
        let old = makeSnapshot(
            id: "claude-thread",
            sourceKind: .claudeCode,
            status: .needsInput,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: [:]
        )
        let new = makeSnapshot(
            id: "claude-thread",
            sourceKind: .claudeCode,
            status: .needsInput,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: [:]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCodexCLIFollowUpTurnAnnouncesWhileStillRunning() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "cli", "turnId": "turn-1"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "cli", "turnId": "turn-2"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCodexCLISameTurnRunningUpdatesDoNotAnnounce() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "cli", "turnId": "turn-1"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "cli", "turnId": "turn-1"]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testCodexCLIFallsBackToUpdatedAtWhenTurnIdentifiersAreMissing() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "cli"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "cli"]
        )

        XCTAssertTrue(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    func testNonCLIRepeatedRunningUpdatesDoNotAnnounce() {
        let old = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["source": "vscode"]
        )
        let new = makeSnapshot(
            id: "codex-thread",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 102),
            metadata: ["source": "vscode"]
        )

        XCTAssertFalse(ExternalSnapshotActivityDetector.shouldAnnounce(old: old, new: new))
    }

    private func makeSnapshot(
        id: String,
        sourceKind: TaskSourceKind,
        status: TaskStatus,
        updatedAt: Date,
        metadata: [String: String]
    ) -> ExternalTaskSnapshot {
        ExternalTaskSnapshot(
            id: id,
            sourceKind: sourceKind,
            title: "Task",
            workspace: nil,
            status: status,
            progress: "Working...",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: updatedAt,
            deepLinkURL: nil,
            metadata: metadata
        )
    }
}
