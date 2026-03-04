import CryptoKit
import Foundation

protocol PersistenceStore: AnyObject, Sendable {
    func loadState() async throws -> PersistedState
    func saveState(_ state: PersistedState) async throws
}

enum PersistenceError: Error, LocalizedError {
    case corruptCiphertext

    var errorDescription: String? {
        switch self {
        case .corruptCiphertext:
            "Encrypted state is corrupt and cannot be decoded."
        }
    }
}

actor EncryptedPersistenceStore: PersistenceStore {
    private let keyProvider: SymmetricKeyProviding
    private let keyReference: String
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        keyProvider: SymmetricKeyProviding,
        keyReference: String = "state.encryption.key",
        fileURL: URL? = nil
    ) {
        self.keyProvider = keyProvider
        self.keyReference = keyReference

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = appSupport
                .appendingPathComponent("ClawdbotNotchCompanion", isDirectory: true)
                .appendingPathComponent("state.enc")
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadState() async throws -> PersistedState {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let bootstrap = PersistedState.bootstrap()
            try await saveState(bootstrap)
            return bootstrap
        }

        let encryptedData = try Data(contentsOf: fileURL)
        let key = try keyProvider.loadOrCreateKey(reference: keyReference)

        guard let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData) else {
            throw PersistenceError.corruptCiphertext
        }

        let plaintext = try AES.GCM.open(sealedBox, using: key)
        return try decoder.decode(PersistedState.self, from: plaintext)
    }

    func saveState(_ state: PersistedState) async throws {
        try ensureDirectoryExists()

        let key = try keyProvider.loadOrCreateKey(reference: keyReference)
        let plaintext = try encoder.encode(state)
        let sealed = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealed.combined else {
            throw PersistenceError.corruptCiphertext
        }

        try combined.write(to: fileURL, options: .atomic)
    }

    private func ensureDirectoryExists() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
