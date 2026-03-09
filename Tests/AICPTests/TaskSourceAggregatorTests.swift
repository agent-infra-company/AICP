import XCTest
@testable import AICP

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

    func testUnavailableSourceStartsAfterBecomingAvailable() async throws {
        let aggregator = TaskSourceAggregator(availabilityPollInterval: .milliseconds(50))
        let snapshot = ExternalTaskSnapshot(
            id: "cursor-signal-arena",
            sourceKind: .cursor,
            title: "Agent session",
            workspace: "signal-arena",
            status: .running,
            progress: "Agent",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: Date(),
            deepLinkURL: nil,
            metadata: [:]
        )
        let source = ToggleableStubTaskSource(
            sourceKind: .cursor,
            snapshots: [snapshot],
            initiallyAvailable: false
        )

        let receivedSnapshot = expectation(description: "aggregator yields snapshots after source becomes available")
        let streamTask = Task {
            for await snapshotsByKind in aggregator.snapshotStream {
                if snapshotsByKind[.cursor] == [snapshot] {
                    receivedSnapshot.fulfill()
                    break
                }
            }
        }

        await aggregator.register(source)
        await aggregator.startAll()
        await source.setAvailable(true)

        await fulfillment(of: [receivedSnapshot], timeout: 1.0)
        streamTask.cancel()
        await aggregator.stopAll()
    }

    func testFinishedSourceIsRestartedByAvailabilityLoop() async throws {
        let aggregator = TaskSourceAggregator(availabilityPollInterval: .milliseconds(50))
        let snapshot = ExternalTaskSnapshot(
            id: "claude-ephemeral",
            sourceKind: .claudeCode,
            title: "Ephemeral session",
            workspace: "quebec",
            status: .running,
            progress: "Working...",
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: Date(),
            deepLinkURL: nil,
            metadata: [:]
        )
        let source = RestartingStubTaskSource(sourceKind: .claudeCode, snapshots: [snapshot])

        await aggregator.register(source)
        await aggregator.startAll()

        let restarted = expectation(description: "aggregator restarts a finished source")
        let observer = Task {
            let deadline = ContinuousClock.now + .seconds(1)
            while ContinuousClock.now < deadline {
                if await source.startCount() >= 2 {
                    restarted.fulfill()
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        await fulfillment(of: [restarted], timeout: 1.0)
        observer.cancel()
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

private actor AvailabilityBox {
    private var available: Bool

    init(initiallyAvailable: Bool) {
        self.available = initiallyAvailable
    }

    func get() -> Bool {
        available
    }

    func set(_ newValue: Bool) {
        available = newValue
    }
}

private final class ToggleableStubTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind

    private let snapshots: [ExternalTaskSnapshot]
    private let availability: AvailabilityBox

    init(sourceKind: TaskSourceKind, snapshots: [ExternalTaskSnapshot], initiallyAvailable: Bool) {
        self.sourceKind = sourceKind
        self.snapshots = snapshots
        self.availability = AvailabilityBox(initiallyAvailable: initiallyAvailable)
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        AsyncStream { continuation in
            continuation.yield(snapshots)
            continuation.finish()
        }
    }

    func stopMonitoring() async {}

    func isAvailable() async -> Bool {
        await availability.get()
    }

    func setAvailable(_ newValue: Bool) async {
        await availability.set(newValue)
    }
}

private actor StartCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func get() -> Int {
        count
    }
}

private final class RestartingStubTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind

    private let snapshots: [ExternalTaskSnapshot]
    private let counter = StartCounter()

    init(sourceKind: TaskSourceKind, snapshots: [ExternalTaskSnapshot]) {
        self.sourceKind = sourceKind
        self.snapshots = snapshots
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        await counter.increment()
        return AsyncStream { continuation in
            continuation.yield(snapshots)
            continuation.finish()
        }
    }

    func stopMonitoring() async {}

    func isAvailable() async -> Bool { true }

    func startCount() async -> Int {
        await counter.get()
    }
}
