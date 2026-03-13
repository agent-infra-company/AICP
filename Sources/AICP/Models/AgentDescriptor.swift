import Foundation

/// Describes a registered agent's identity and display metadata.
/// Built-in agents (Conductor, Claude Code, etc.) have descriptors derived from TaskSourceKind.
/// Custom/remote agents provide their own descriptor at registration time.
struct AgentDescriptor: Identifiable, Codable, Hashable {
    var id: String
    var displayName: String
    var iconSystemName: String
    var iconColorHex: String
    var iconImageName: String?
    var urlScheme: String?
    var activationBundleIdentifiers: [String]
    var activationApplicationPaths: [String]

    /// Whether this agent supports receiving messages (task submission).
    var supportsMessaging: Bool

    /// Whether this agent supports follow-up answers.
    var supportsFollowUp: Bool

    /// Endpoint URL for remote agents (HTTP/WebSocket).
    var endpointURL: URL?

    init(
        id: String,
        displayName: String,
        iconSystemName: String = "puzzlepiece.extension",
        iconColorHex: String = "#888888",
        iconImageName: String? = nil,
        urlScheme: String? = nil,
        activationBundleIdentifiers: [String] = [],
        activationApplicationPaths: [String] = [],
        supportsMessaging: Bool = false,
        supportsFollowUp: Bool = false,
        endpointURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        self.iconColorHex = iconColorHex
        self.iconImageName = iconImageName
        self.urlScheme = urlScheme
        self.activationBundleIdentifiers = activationBundleIdentifiers
        self.activationApplicationPaths = activationApplicationPaths
        self.supportsMessaging = supportsMessaging
        self.supportsFollowUp = supportsFollowUp
        self.endpointURL = endpointURL
    }
}

extension AgentDescriptor {
    /// Create a descriptor from a built-in TaskSourceKind.
    static func builtIn(_ kind: TaskSourceKind) -> AgentDescriptor {
        AgentDescriptor(
            id: kind.rawValue,
            displayName: kind.displayName,
            iconSystemName: kind.iconName,
            iconColorHex: kind.iconColorHexValue,
            iconImageName: kind.iconImageName,
            urlScheme: kind.urlScheme,
            activationBundleIdentifiers: kind.activationBundleIdentifiers,
            activationApplicationPaths: kind.activationApplicationPaths,
            supportsMessaging: kind == .openClaw || kind == .claudeCode || kind == .codex,
            supportsFollowUp: kind == .openClaw
        )
    }
}
