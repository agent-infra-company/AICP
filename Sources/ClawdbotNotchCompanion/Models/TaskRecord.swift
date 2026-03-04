import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case queued
    case running
    case needsInput = "needs_input"
    case completed
    case failed
    case canceled
    case needsAttention = "needs_attention"

    var id: String { rawValue }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .canceled, .needsAttention:
            true
        case .draft, .queued, .running, .needsInput:
            false
        }
    }
}

struct TaskRecord: Identifiable, Codable, Hashable {
    var taskId: String
    var profileId: UUID
    var routeId: String
    var sessionId: String?
    var runId: String?
    var title: String
    var prompt: String
    var status: TaskStatus
    var createdAt: Date
    var updatedAt: Date
    var retryCount: Int
    var needsInputPrompt: String?
    var lastError: String?
    var latestProgress: String?

    var id: String { taskId }

    var needsInput: Bool {
        status == .needsInput
    }

    static func draft(profileId: UUID, routeId: String, prompt: String) -> TaskRecord {
        let now = Date()
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "Task"
        let title = String((normalized.isEmpty ? fallback : normalized).prefix(80))
        return TaskRecord(
            taskId: UUID().uuidString,
            profileId: profileId,
            routeId: routeId,
            sessionId: nil,
            runId: nil,
            title: title,
            prompt: prompt,
            status: .draft,
            createdAt: now,
            updatedAt: now,
            retryCount: 0,
            needsInputPrompt: nil,
            lastError: nil,
            latestProgress: nil
        )
    }
}
