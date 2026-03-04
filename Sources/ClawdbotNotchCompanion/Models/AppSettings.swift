import Foundation

struct AppSettings: Codable, Hashable {
    var launchAtLogin: Bool
    var showInFullscreen: Bool
    var hideInScreenRecording: Bool
    var telemetryOptIn: Bool
    var retentionDays: Int
    var primaryDisplayOnly: Bool
    var selectedProfileId: UUID?
    var selectedRouteByProfile: [UUID: String]

    static var `default`: AppSettings {
        AppSettings(
            launchAtLogin: true,
            showInFullscreen: true,
            hideInScreenRecording: true,
            telemetryOptIn: false,
            retentionDays: 90,
            primaryDisplayOnly: true,
            selectedProfileId: nil,
            selectedRouteByProfile: [:]
        )
    }
}

struct PersistedState: Codable {
    var profiles: [ProfileConfig]
    var commandTemplateSets: [CommandTemplateSet]
    var tasks: [TaskRecord]
    var routeAliasesByProfile: [UUID: [RouteInfo]]
    var settings: AppSettings
    var updatedAt: Date

    static func bootstrap() -> PersistedState {
        let localTemplates = CommandTemplateSet.localDefault
        let localProfile = ProfileConfig.defaultLocal(commandTemplateSetId: localTemplates.id)
        var settings = AppSettings.default
        settings.selectedProfileId = localProfile.id
        settings.selectedRouteByProfile[localProfile.id] = "default"

        return PersistedState(
            profiles: [localProfile],
            commandTemplateSets: [localTemplates],
            tasks: [],
            routeAliasesByProfile: [
                localProfile.id: [
                    RouteInfo(id: "default", displayName: "Default", metadata: [:])
                ]
            ],
            settings: settings,
            updatedAt: Date()
        )
    }
}
