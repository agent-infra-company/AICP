import Foundation

enum ProfileKind: String, Codable, CaseIterable, Identifiable {
    case local
    case remote

    var id: String { rawValue }
}

enum ProfileAuthMode: String, Codable, CaseIterable, Identifiable {
    case none
    case token
    case password

    // Legacy decoding support
    case bearerToken

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None (local)"
        case .token, .bearerToken: "Token"
        case .password: "Password"
        }
    }

    /// Normalize legacy values to current modes.
    var normalized: ProfileAuthMode {
        switch self {
        case .bearerToken: .token
        default: self
        }
    }
}

struct ProfileConfig: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ProfileKind
    var gatewayURL: URL
    var authMode: ProfileAuthMode
    /// Keychain reference for the credential (token or password value).
    var tokenRef: String?
    var sshRef: String?
    var commandTemplateSetId: UUID
    var enabled: Bool

    static func defaultLocal(commandTemplateSetId: UUID) -> ProfileConfig {
        ProfileConfig(
            id: UUID(),
            name: "Local OpenClaw",
            kind: .local,
            gatewayURL: URL(string: "http://127.0.0.1:18789")!,
            authMode: .none,
            tokenRef: nil,
            sshRef: nil,
            commandTemplateSetId: commandTemplateSetId,
            enabled: true
        )
    }
}
