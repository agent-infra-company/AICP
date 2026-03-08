import XCTest
@testable import ClawdbotNotchCompanion

final class TaskSourceAggregatorTests: XCTestCase {
    func testRegisterStartsMonitoringAfterAggregatorHasStarted() async throws {
        let aggregator = TaskSourceAggregator()
        let snapshot = ExternalTaskSnapshot(
            id: "claude-123",
            sourceKind: .claudeCode,
            title: "Claude Code session",
            workspace: "quebec",
            status: .running,
            progress: "Working...",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: Date(),
            deepLinkURL: nil,
            metadata: [:]
        )
        let source = StubTaskSource(sourceKind: .claudeCode, snapshots: [snapshot])

        let receivedSnapshot = expectation(description: "aggregator yields snapshots from a late-registered source")
        let streamTask = Task {
            for await snapshotsByKind in aggregator.snapshotStream {
                if snapshotsByKind[.claudeCode] == [snapshot] {
                    receivedSnapshot.fulfill()
                    break
                }
            }
        }

        await aggregator.startAll()
        await aggregator.register(source)

        await fulfillment(of: [receivedSnapshot], timeout: 1.0)
        streamTask.cancel()
        await aggregator.stopAll()
    }
}

private final class StubTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind
    private let snapshots: [ExternalTaskSnapshot]

    init(sourceKind: TaskSourceKind, snapshots: [ExternalTaskSnapshot]) {
        self.sourceKind = sourceKind
        self.snapshots = snapshots
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        AsyncStream { continuation in
            continuation.yield(snapshots)
            continuation.finish()
        }
    }

    func stopMonitoring() async {}

    func isAvailable() async -> Bool { true }
}
