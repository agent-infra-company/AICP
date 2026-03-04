import XCTest
@testable import ClawdbotNotchCompanion

final class TaskStateMachineTests: XCTestCase {
    func testValidTransitionsWork() throws {
        let machine = TaskStateMachine()
        var task = TaskRecord.draft(profileId: UUID(), routeId: "default", prompt: "do work")

        task = try machine.transition(task, to: .queued)
        XCTAssertEqual(task.status, .queued)

        task = try machine.transition(task, to: .running)
        XCTAssertEqual(task.status, .running)

        task = try machine.transition(task, to: .needsInput)
        XCTAssertEqual(task.status, .needsInput)

        task = try machine.transition(task, to: .running)
        XCTAssertEqual(task.status, .running)

        task = try machine.transition(task, to: .completed)
        XCTAssertEqual(task.status, .completed)
    }

    func testInvalidTransitionThrows() throws {
        let machine = TaskStateMachine()
        let task = TaskRecord.draft(profileId: UUID(), routeId: "default", prompt: "do work")

        XCTAssertThrowsError(try machine.transition(task, to: .completed))
    }

    func testRetryTransitionAllowedFromFailedToQueued() throws {
        let machine = TaskStateMachine()
        var task = TaskRecord.draft(profileId: UUID(), routeId: "default", prompt: "do work")

        task = try machine.transition(task, to: .queued)
        task = try machine.transition(task, to: .failed)
        task = try machine.transition(task, to: .queued)

        XCTAssertEqual(task.status, .queued)
    }
}
