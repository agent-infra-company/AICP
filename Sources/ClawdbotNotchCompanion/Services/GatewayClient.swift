import Foundation

protocol GatewayClient: AnyObject, Sendable {
    func connect(profile: ProfileConfig) async throws
    func disconnect(profileId: UUID) async
    func discoverRoutes(profile: ProfileConfig) async throws -> [RouteInfo]
    func sendTask(_ draft: TaskDraft, profile: ProfileConfig) async throws -> SentTaskInfo
    func answerFollowUp(task: TaskRecord, answer: String, profile: ProfileConfig) async throws
    func subscribeEvents(profileId: UUID) async -> AsyncStream<GatewayEventEnvelope>
}

enum GatewayClientError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case unexpectedStatus(Int)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid OpenClaw gateway URL."
        case .unauthorized:
            "Gateway authorization failed. Check token or profile auth settings."
        case let .unexpectedStatus(code):
            "Gateway request failed with HTTP \(code)."
        case .malformedResponse:
            "Gateway returned an unexpected response format."
        }
    }
}
