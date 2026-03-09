import Foundation
import os.log

actor DefaultRuntimeManager: RuntimeManager {
    private static let log = CompanionDiagnostics.logger(category: "RuntimeManager")

    private var profilesById: [UUID: ProfileConfig] = [:]
    private var templatesById: [UUID: CommandTemplateSet] = [:]

    private let commandExecutor: ShellCommandExecuting
    private let templateEngine = CommandTemplateEngine()
    private let whitelistValidator = CommandWhitelistValidator()

    init(commandExecutor: ShellCommandExecuting) {
        self.commandExecutor = commandExecutor
    }

    func updateConfiguration(profiles: [ProfileConfig], templateSets: [CommandTemplateSet]) async {
        profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        templatesById = Dictionary(uniqueKeysWithValues: templateSets.map { ($0.id, $0) })
    }

    func start(profileId: UUID) async throws -> RuntimeStatus {
        try await execute(action: .start, profileId: profileId)
    }

    func stop(profileId: UUID) async throws -> RuntimeStatus {
        try await execute(action: .stop, profileId: profileId)
    }

    func restart(profileId: UUID) async throws -> RuntimeStatus {
        try await execute(action: .restart, profileId: profileId)
    }

    func status(profileId: UUID) async throws -> RuntimeStatus {
        try await execute(action: .status, profileId: profileId)
    }

    private func execute(action: RuntimeAction, profileId: UUID) async throws -> RuntimeStatus {
        Self.log.info("Executing runtime action=\(String(describing: action), privacy: .public) profileId=\(profileId.uuidString, privacy: .public)")

        guard let profile = profilesById[profileId], profile.enabled else {
            Self.log.error("Profile not found or disabled profileId=\(profileId.uuidString, privacy: .public)")
            throw RuntimeManagerError.profileMissing
        }

        guard let templateSet = templatesById[profile.commandTemplateSetId] else {
            throw RuntimeManagerError.templateSetMissing
        }

        let context = LocalCommandContext.from(profile: profile)
        var command = try templateEngine.render(
            template: templateSet.command(for: action),
            values: context.values,
            allowedPlaceholders: templateSet.allowedPlaceholders
        )
        try whitelistValidator.validate(action: action, generatedCommand: command, templateSet: templateSet)

        if profile.kind == .remote {
            guard let sshRef = profile.sshRef, !sshRef.isEmpty else {
                throw RuntimeManagerError.missingSSHReference
            }
            guard Self.isValidSSHReference(sshRef) else {
                throw RuntimeManagerError.commandRejected("SSH reference contains invalid characters. Expected format: user@host or host.")
            }
            command = "ssh \(sshRef) '\(escapeForSingleQuotes(command))'"
        }

        Self.log.debug("Executing command for action=\(String(describing: action), privacy: .public) profile=\(profile.name, privacy: .public)")

        let result = try await commandExecutor.execute(command: command)
        let output = [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        let detail = output.isEmpty ? "No output" : output
        let healthy: Bool

        switch action {
        case .stop:
            healthy = false
        case .status:
            let lower = detail.lowercased()
            healthy = result.exitCode == 0 && !lower.contains("stopped") && !lower.contains("down")
        case .start, .restart:
            healthy = result.exitCode == 0
        }

        if action != .stop, !healthy {
            Self.log.error("Runtime unhealthy after action=\(String(describing: action), privacy: .public) profile=\(profile.name, privacy: .public) exitCode=\(result.exitCode)")
            throw RuntimeManagerError.unhealthy(detail)
        }

        Self.log.info("Runtime action=\(String(describing: action), privacy: .public) completed healthy=\(healthy) profile=\(profile.name, privacy: .public)")
        return RuntimeStatus(isHealthy: healthy, detail: detail, checkedAt: Date())
    }

    private func escapeForSingleQuotes(_ raw: String) -> String {
        raw.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// Validates that an SSH reference matches a safe pattern (e.g. user@host, host, user@host:port).
    private static let sshRefPattern = #"^[a-zA-Z0-9._\-]+(@[a-zA-Z0-9._\-]+(:[0-9]{1,5})?)?$"#

    private static func isValidSSHReference(_ ref: String) -> Bool {
        ref.range(of: sshRefPattern, options: .regularExpression) != nil
    }
}
