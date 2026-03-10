import Foundation
import Security

protocol SecretStoring: AnyObject, Sendable {
    func secret(for key: String) throws -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String) throws
}

// MARK: - Keychain (signed app bundle)

final class KeychainSecretStore: SecretStoring, @unchecked Sendable {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func secret(for key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    func setSecret(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func removeSecret(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

// MARK: - File-based (unbundled / swift run)

/// Stores secrets in a JSON file with POSIX 0600 permissions.
/// Used for `swift run` mode where keychain access triggers repeated
/// authorization prompts because the binary is unsigned.
final class FileSecretStore: SecretStoring, @unchecked Sendable {
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

// MARK: - Factory

enum SecretStoreFactory {
    static func create(service: String) -> SecretStoring {
        if AppRuntimeEnvironment.current.isBundledApp {
            return KeychainSecretStore(service: service)
        } else {
            return FileSecretStore()
        }
    }
}
