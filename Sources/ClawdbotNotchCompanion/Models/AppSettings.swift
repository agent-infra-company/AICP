import Foundation

enum NotchStyle: String, Codable, CaseIterable, Identifiable, Hashable {
    case glow
    case subtle
    case hidden
    var id: String { rawValue }
}

struct AppSettings: Codable, Hashable {
    var launchAtLogin: Bool
    var showInFullscreen: Bool
    var hideInScreenRecording: Bool
    var telemetryOptIn: Bool
    var retentionDays: Int
    var primaryDisplayOnly: Bool
    var selectedProfileId: UUID?
    var selectedRouteByProfile: [UUID: String]
    var hasCompletedOnboarding: Bool
    var glowColorHex: String
    var notchStyle: NotchStyle

    static var `default`: AppSettings {
        AppSettings(
            launchAtLogin: true,
            showInFullscreen: true,
            hideInScreenRecording: true,
            telemetryOptIn: false,
            retentionDays: 90,
            primaryDisplayOnly: true,
            selectedProfileId: nil,
            selectedRouteByProfile: [:],
            hasCompletedOnboarding: false,
            glowColorHex: "#FF0000",
            notchStyle: .glow
        )
    }

    init(
        launchAtLogin: Bool,
        showInFullscreen: Bool,
        hideInScreenRecording: Bool,
        telemetryOptIn: Bool,
        retentionDays: Int,
        primaryDisplayOnly: Bool,
        selectedProfileId: UUID?,
        selectedRouteByProfile: [UUID: String],
        hasCompletedOnboarding: Bool = false,
        glowColorHex: String = "#FF0000",
        notchStyle: NotchStyle = .glow
    ) {
        self.launchAtLogin = launchAtLogin
        self.showInFullscreen = showInFullscreen
        self.hideInScreenRecording = hideInScreenRecording
        self.telemetryOptIn = telemetryOptIn
        self.retentionDays = retentionDays
        self.primaryDisplayOnly = primaryDisplayOnly
        self.selectedProfileId = selectedProfileId
        self.selectedRouteByProfile = selectedRouteByProfile
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.glowColorHex = glowColorHex
        self.notchStyle = notchStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        showInFullscreen = try container.decode(Bool.self, forKey: .showInFullscreen)
        hideInScreenRecording = try container.decode(Bool.self, forKey: .hideInScreenRecording)
        telemetryOptIn = try container.decode(Bool.self, forKey: .telemetryOptIn)
        retentionDays = try container.decode(Int.self, forKey: .retentionDays)
        primaryDisplayOnly = try container.decode(Bool.self, forKey: .primaryDisplayOnly)
        selectedProfileId = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileId)
        selectedRouteByProfile = try container.decode([UUID: String].self, forKey: .selectedRouteByProfile)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        glowColorHex = try container.decodeIfPresent(String.self, forKey: .glowColorHex) ?? "#FF0000"
        notchStyle = try container.decodeIfPresent(NotchStyle.self, forKey: .notchStyle) ?? .glow
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
