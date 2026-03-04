import Foundation

struct GatewayEventEnvelope: Codable, Hashable, Identifiable {
    var id: String
    var source: String
    var sessionId: String?
    var runId: String?
    var taskId: String?
    var eventType: String
    var payload: [String: String]
    var receivedAt: Date

    init(
        id: String = UUID().uuidString,
        source: String,
        sessionId: String? = nil,
        runId: String? = nil,
        taskId: String? = nil,
        eventType: String,
        payload: [String: String],
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.sessionId = sessionId
        self.runId = runId
        self.taskId = taskId
        self.eventType = eventType
        self.payload = payload
        self.receivedAt = receivedAt
    }
}

struct RouteInfo: Codable, Hashable, Identifiable {
    var id: String
    var displayName: String
    var metadata: [String: String]
}

struct TaskDraft: Codable, Hashable {
    var profileId: UUID
    var routeId: String
    var title: String
    var prompt: String
    var clientTaskId: String
}

struct SentTaskInfo: Codable, Hashable {
    var taskId: String
    var sessionId: String?
    var runId: String?
    var status: TaskStatus
}

struct RuntimeStatus: Codable, Hashable {
    var isHealthy: Bool
    var detail: String
    var checkedAt: Date
}
