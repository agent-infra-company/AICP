import Foundation

protocol SecretStoring: AnyObject, Sendable {
    func secret(for key: String) throws -> String?
    func setSecret(_ value: String, for key: String) throws
    func removeSecret(for key: String) throws
}

/// Stores secrets in a JSON file with POSIX 0600 permissions.
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
