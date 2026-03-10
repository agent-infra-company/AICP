import Foundation

enum RuntimeRequestConfirmation: Equatable {
    case notRequired
    case required(title: String, message: String)
}

struct PendingRuntimeOperation: Identifiable, Equatable {
    var id: UUID
    var profileId: UUID
    var action: RuntimeAction
    var title: String
    var message: String

    init(profileId: UUID, action: RuntimeAction, title: String, message: String) {
        self.id = UUID()
        self.profileId = profileId
        self.action = action
        self.title = title
        self.message = message
    }
}

struct LocalCommandContext {
    var profileName: String
    var gatewayURL: URL
    var host: String
    var port: String

    static func from(profile: ProfileConfig) -> LocalCommandContext {
        let host = profile.gatewayURL.host ?? "127.0.0.1"
        let port = profile.gatewayURL.port.map(String.init) ?? "18789"
        return LocalCommandContext(profileName: profile.name, gatewayURL: profile.gatewayURL, host: host, port: port)
    }

    var values: [String: String] {
        [
            "profile_name": profileName,
            "gateway_url": gatewayURL.absoluteString,
            "host": host,
            "port": port
        ]
    }
}
