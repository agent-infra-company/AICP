import Foundation

enum RuntimeAction: String, Codable, CaseIterable, Identifiable {
    case start
    case stop
    case restart
    case status

    var id: String { rawValue }
}

struct CommandTemplateSet: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var startCmd: String
    var stopCmd: String
    var restartCmd: String
    var statusCmd: String
    var allowedPlaceholders: [String]

    func command(for action: RuntimeAction) -> String {
        switch action {
        case .start:
            startCmd
        case .stop:
            stopCmd
        case .restart:
            restartCmd
        case .status:
            statusCmd
        }
    }

    static var localDefault: CommandTemplateSet {
        CommandTemplateSet(
            id: UUID(),
            name: "Default Local Commands",
            startCmd: "openclaw gateway start --port {{port}}",
            stopCmd: "openclaw gateway stop",
            restartCmd: "openclaw gateway restart --port {{port}}",
            statusCmd: "openclaw gateway status",
            allowedPlaceholders: ["host", "port", "gateway_url", "profile_name"]
        )
    }

    static var remoteDefault: CommandTemplateSet {
        CommandTemplateSet(
            id: UUID(),
            name: "Default Remote Commands",
            startCmd: "openclaw gateway start --port {{port}}",
            stopCmd: "openclaw gateway stop",
            restartCmd: "openclaw gateway restart --port {{port}}",
            statusCmd: "openclaw gateway status",
            allowedPlaceholders: ["host", "port", "gateway_url", "profile_name"]
        )
    }
}
