import Foundation

protocol RuntimeManager: AnyObject, Sendable {
    func updateConfiguration(profiles: [ProfileConfig], templateSets: [CommandTemplateSet]) async
    func start(profileId: UUID) async throws -> RuntimeStatus
    func stop(profileId: UUID) async throws -> RuntimeStatus
    func restart(profileId: UUID) async throws -> RuntimeStatus
    func status(profileId: UUID) async throws -> RuntimeStatus
}

enum RuntimeManagerError: Error, LocalizedError {
    case profileMissing
    case templateSetMissing
    case commandRejected(String)
    case unhealthy(String)

    var errorDescription: String? {
        switch self {
        case .profileMissing:
            "Profile not found."
        case .templateSetMissing:
            "Command template set not found for profile."
        case let .commandRejected(message):
            "Runtime command rejected: \(message)"
        case let .unhealthy(message):
            "Runtime unhealthy: \(message)"
        }
    }
}
