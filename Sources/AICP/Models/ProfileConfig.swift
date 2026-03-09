import Foundation

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }
}

enum ProfileAuthMode: String, Codable, CaseIterable, Identifiable {
    case none
    case bearerToken

    var id: String { rawValue }
}

struct ProfileConfig: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ProfileKind
    var gatewayURL: URL
    var authMode: ProfileAuthMode
    var tokenRef: String?
    var sshRef: String?
    var commandTemplateSetId: UUID
    var enabled: Bool

    static func defaultLocal(commandTemplateSetId: UUID) -> ProfileConfig {
        ProfileConfig(
            id: UUID(),
            name: "Local OpenClaw",
            kind: .local,
            gatewayURL: URL(string: "http://127.0.0.1:4689")!,
            authMode: .none,
            tokenRef: nil,
            sshRef: nil,
            commandTemplateSetId: commandTemplateSetId,
            enabled: true
        )
    }
}
