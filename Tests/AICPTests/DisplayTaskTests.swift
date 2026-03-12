import XCTest
@testable import AICP

final class DisplayTaskTests: XCTestCase {
    func testDisplayTaskOrderingPinsRunningTasksAboveNewerCompletedTasks() {
        let running = makeTask(
            id: "running",
            sourceKind: .conductor,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100),
            metadata: ["branch": "apupneja/milan-v1"]
        )
        let completed = makeTask(
            id: "completed",
            sourceKind: .conductor,
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 200),
            metadata: ["branch": "apupneja/algiers-v1"]
        )

        let sorted = [completed, running].sorted(by: ControlPlaneCore.displayTaskOrdering)

        XCTAssertEqual(sorted.map(\.id), ["running", "completed"])
    }

    func testDisplayTaskOrderingUsesRecencyWithinSameStatusBucket() {
        let olderRunning = makeTask(
            id: "older",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newerRunning = makeTask(
            id: "newer",
            sourceKind: .codex,
            status: .running,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let sorted = [olderRunning, newerRunning].sorted(by: ControlPlaneCore.displayTaskOrdering)

        XCTAssertEqual(sorted.map(\.id), ["newer", "older"])
    }

    func testConductorLocationLabelPrefersBranchMetadata() {
        let task = makeTask(
            id: "conductor",
            sourceKind: .conductor,
            workspace: "milan-v1",
            status: .running,
            updatedAt: Date(),
            metadata: ["branch": "apupneja/milan-v1"]
        )

        XCTAssertEqual(task.locationLabel, "apupneja/milan-v1")
    }

    private func makeTask(
        id: String,
        sourceKind: TaskSourceKind,
        workspace: String? = nil,
        status: TaskStatus,
        updatedAt: Date,
        metadata: [String: String] = [:]
    ) -> DisplayTask {
        DisplayTask(
            id: id,
            sourceKind: sourceKind,
            title: "Task \(id)",
            workspace: workspace,
            status: status,
            progress: nil,
            needsInputPrompt: nil,
            lastError: nil,
            updatedAt: updatedAt,
            deepLinkURL: nil,
            metadata: metadata
        )
    }
}
