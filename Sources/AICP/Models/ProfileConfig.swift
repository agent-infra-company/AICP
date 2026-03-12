import Foundation

struct ProfileConfig: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var gatewayURL: URL
    var commandTemplateSetId: UUID
    var enabled: Bool

    static func defaultLocal(commandTemplateSetId: UUID) -> ProfileConfig {
        ProfileConfig(
            id: UUID(),
            name: "Local Gateway",
            gatewayURL: URL(string: "http://127.0.0.1:18789")!,
            commandTemplateSetId: commandTemplateSetId,
            enabled: true
        )
    }
}
