import Foundation
import LocalAuthentication
import Security

protocol SecretStoring: AnyObject, Sendable {
    func secret(for key: String) throws -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String) throws
}

protocol SecretStoreExporting: AnyObject, Sendable {
    func exportSecrets() throws -> [String: String]
}

protocol InteractiveSecureStorageControlling: AnyObject, Sendable {
    func requestInteractivePrimaryAccess() throws -> Bool
}

private enum SecureStoragePreference {
    private static let userDefaultsKey = "AICP.secureStorageEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
    }
}

// MARK: - Keychain (signed app bundle)

final class KeychainSecretStore: SecretStoring, @unchecked Sendable {
    private enum AccessMode: CaseIterable {
        case dataProtection
        case standard
    }

    private let service: String
    private let allowsUserInteraction: Bool

    init(service: String, allowsUserInteraction: Bool = true) {
        self.service = service
        self.allowsUserInteraction = allowsUserInteraction
    }

    func secret(for key: String) throws -> String? {
        for mode in AccessMode.allCases {
            var result: AnyObject?
            let status = SecItemCopyMatching(
                query(forKey: key, mode: mode, returningData: true) as CFDictionary,
                &result
            )

            switch status {
            case errSecSuccess:
                guard let data = result as? Data,
                      let string = String(data: data, encoding: .utf8) else {
                    return nil
                }
                return string
            case errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }

        return nil
    }

    func setSecret(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        for mode in AccessMode.allCases {
            let updateStatus = SecItemUpdate(
                query(forKey: key, mode: mode) as CFDictionary,
                attributes as CFDictionary
            )
            switch updateStatus {
            case errSecSuccess:
                return
            case errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
            }
        }

        var lastError: NSError?
        for mode in AccessMode.allCases {
            var insert = query(forKey: key, mode: mode)
            insert[kSecValueData as String] = data

            let status = SecItemAdd(insert as CFDictionary, nil)
            switch status {
            case errSecSuccess:
                return
            case errSecDuplicateItem, errSecMissingEntitlement:
                lastError = NSError(domain: NSOSStatusErrorDomain, code: Int(status))
                continue
            default:
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }

        throw lastError ?? NSError(domain: NSOSStatusErrorDomain, code: Int(errSecUnimplemented))
    }

    func removeSecret(for key: String) throws {
        var lastError: NSError?

        for mode in AccessMode.allCases {
            let status = SecItemDelete(query(forKey: key, mode: mode) as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                lastError = NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private func query(forKey key: String, mode: AccessMode, returningData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }

        // Ad-hoc local builds do not have the entitlement required for the
        // data protection keychain, so fall back to the standard login keychain.
        if mode == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        if !allowsUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        return query
    }
}

// MARK: - File-based (unbundled / swift run)

/// Stores secrets in a JSON file with POSIX 0600 permissions.
/// Used for `swift run` mode where keychain access triggers repeated
/// authorization prompts because the binary is unsigned.
final class FileSecretStore: SecretStoring, SecretStoreExporting, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".aicp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("secrets.json")
    }

    func secret(for key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let store = load()
        return store[key]
    }

    func setSecret(_ value: String, for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = load()
        store[key] = value
        try save(store)
    }

    func removeSecret(for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = load()
        store.removeValue(forKey: key)
        try save(store)
    }

    func exportSecrets() throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func save(_ store: [String: String]) throws {
        let data = try JSONEncoder().encode(store)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

/// Uses Keychain when available, but falls back to the file-backed store for
/// local ad-hoc builds where keychain access can fail or require UI interaction.
final class FallbackSecretStore: SecretStoring, InteractiveSecureStorageControlling, @unchecked Sendable {
    private let primary: SecretStoring
    private let interactivePrimary: SecretStoring?
    private let fallback: SecretStoring
    private let onInteractivePrimaryEnabled: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var prefersInteractivePrimary = false

    init(
        primary: SecretStoring,
        fallback: SecretStoring,
        interactivePrimary: SecretStoring? = nil,
        onInteractivePrimaryEnabled: (@Sendable () -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.interactivePrimary = interactivePrimary
        self.onInteractivePrimaryEnabled = onInteractivePrimaryEnabled
    }

    func secret(for key: String) throws -> String? {
        let primaryStore = currentPrimary()
        do {
            if let value = try primaryStore.secret(for: key) {
                return value
            }
        } catch {
            return try fallback.secret(for: key)
        }

        return try fallback.secret(for: key)
    }

    func setSecret(_ value: String, for key: String) throws {
        let primaryStore = currentPrimary()
        do {
            try primaryStore.setSecret(value, for: key)
        } catch {
            try fallback.setSecret(value, for: key)
        }
    }

    func removeSecret(for key: String) throws {
        let primaryStore = currentPrimary()
        var primaryError: Error?
        var fallbackSucceeded = false

        do {
            try primaryStore.removeSecret(for: key)
            return
        } catch {
            primaryError = error
        }

        do {
            try fallback.removeSecret(for: key)
            fallbackSucceeded = true
        } catch {
            if primaryError == nil {
                throw error
            }
        }

        if let primaryError, !fallbackSucceeded {
            throw primaryError
        }
    }

    func requestInteractivePrimaryAccess() throws -> Bool {
        guard let interactivePrimary else {
            return false
        }

        if isUsingInteractivePrimary() {
            return true
        }

        if let exportingFallback = fallback as? SecretStoreExporting {
            let exportedSecrets = try exportingFallback.exportSecrets()
            for (key, value) in exportedSecrets {
                try interactivePrimary.setSecret(value, for: key)
            }
        }

        // Force an interactive keychain operation even on a clean install so the
        // permission prompt appears here instead of during startup work.
        let probeKey = "setup.keychain.access.probe"
        try interactivePrimary.setSecret(UUID().uuidString, for: probeKey)
        try? interactivePrimary.removeSecret(for: probeKey)

        lock.lock()
        prefersInteractivePrimary = true
        lock.unlock()
        onInteractivePrimaryEnabled?()
        return true
    }

    private func currentPrimary() -> SecretStoring {
        lock.lock()
        defer { lock.unlock() }

        if prefersInteractivePrimary, let interactivePrimary {
            return interactivePrimary
        }

        return primary
    }

    private func isUsingInteractivePrimary() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return prefersInteractivePrimary
    }
}

// MARK: - Factory

enum SecretStoreFactory {
    static func create(service: String) -> SecretStoring {
        if AppRuntimeEnvironment.current.isBundledApp {
            let fileStore = FileSecretStore()
            let secureStorageEnabled = SecureStoragePreference.isEnabled
            return FallbackSecretStore(
                primary: secureStorageEnabled
                    ? KeychainSecretStore(service: service, allowsUserInteraction: false)
                    : fileStore,
                fallback: fileStore,
                interactivePrimary: KeychainSecretStore(service: service),
                onInteractivePrimaryEnabled: {
                    SecureStoragePreference.setEnabled(true)
                }
            )
        } else {
            return FileSecretStore()
        }
    }
}
