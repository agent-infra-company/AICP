import Foundation

actor DefaultRuntimeManager: RuntimeManager {
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
        guard let profile = profilesById[profileId], profile.enabled else {
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
            guard !sshRef.contains("\n"), !sshRef.contains("\r") else {
                throw RuntimeManagerError.commandRejected("SSH reference contains invalid control characters.")
            }
            command = "ssh \(sshRef) '\(escapeForSingleQuotes(command))'"
        }

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
            throw RuntimeManagerError.unhealthy(detail)
        }

        return RuntimeStatus(isHealthy: healthy, detail: detail, checkedAt: Date())
    }

    private func escapeForSingleQuotes(_ raw: String) -> String {
        raw.replacingOccurrences(of: "'", with: "'\\''")
    }
}
