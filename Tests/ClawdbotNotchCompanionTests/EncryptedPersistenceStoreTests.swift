import CryptoKit
import Foundation
import XCTest
@testable import ClawdbotNotchCompanion

final class EncryptedPersistenceStoreTests: XCTestCase {
    func testRoundTripAndEncryption() async throws {
        let keyProvider = InMemoryKeyProvider()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let fileURL = temporaryDirectory.appendingPathComponent("state.enc")
        let store = EncryptedPersistenceStore(
            keyProvider: keyProvider,
            keyReference: "test-key",
            fileURL: fileURL
        )

        var state = PersistedState.bootstrap()
        state.settings.retentionDays = 123
        try await store.saveState(state)

        let loaded = try await store.loadState()
        XCTAssertEqual(loaded.settings.retentionDays, 123)

        let ciphertext = try Data(contentsOf: fileURL)
        let ciphertextString = String(data: ciphertext, encoding: .utf8)
        XCTAssertFalse(ciphertextString?.contains("Local OpenClaw") ?? false)
    }
}

private final class InMemoryKeyProvider: SymmetricKeyProviding, @unchecked Sendable {
    private var keys: [String: SymmetricKey] = [:]

    func loadOrCreateKey(reference: String) throws -> SymmetricKey {
        if let existing = keys[reference] {
            return existing
        }

        let created = SymmetricKey(size: .bits256)
        keys[reference] = created
        return created
    }
}
