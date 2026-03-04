import Foundation

enum TaskStateError: Error, LocalizedError {
    case invalidTransition(from: TaskStatus, to: TaskStatus)

    var errorDescription: String? {
        switch self {
        case let .invalidTransition(from, to):
            "Invalid task status transition from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

struct TaskStateMachine {
    private let transitions: [TaskStatus: Set<TaskStatus>] = [
        .draft: [.queued, .canceled],
        .queued: [.running, .failed, .canceled, .needsAttention],
        .running: [.needsInput, .completed, .failed, .canceled, .needsAttention],
        .needsInput: [.running, .failed, .canceled, .needsAttention],
        .completed: [],
        .failed: [.queued, .needsAttention],
        .canceled: [],
        .needsAttention: [.queued, .canceled]
    ]

    func canTransition(from current: TaskStatus, to next: TaskStatus) -> Bool {
        transitions[current, default: []].contains(next)
    }

    func transition(_ task: TaskRecord, to next: TaskStatus) throws -> TaskRecord {
        guard canTransition(from: task.status, to: next) else {
            throw TaskStateError.invalidTransition(from: task.status, to: next)
        }

        var updated = task
        updated.status = next
        updated.updatedAt = Date()
        if next != .needsInput {
            updated.needsInputPrompt = nil
        }
        if next != .failed && next != .needsAttention {
            updated.lastError = nil
        }
        return updated
    }
}
