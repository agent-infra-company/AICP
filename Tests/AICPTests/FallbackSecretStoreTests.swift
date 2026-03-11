import XCTest
@testable import AICP

final class FallbackSecretStoreTests: XCTestCase {
    func testReadFallsBackWhenPrimaryThrows() throws {
        let primary = StubSecretStore(readError: StubSecretStoreError.synthetic)
        let fallback = StubSecretStore(values: ["token": "fallback-token"])
        let store = FallbackSecretStore(primary: primary, fallback: fallback)

        XCTAssertEqual(try store.secret(for: "token"), "fallback-token")
    }

    func testReadFallsBackWhenPrimaryReturnsNil() throws {
        let primary = StubSecretStore()
        let fallback = StubSecretStore(values: ["token": "fallback-token"])
        let store = FallbackSecretStore(primary: primary, fallback: fallback)

        XCTAssertEqual(try store.secret(for: "token"), "fallback-token")
    }

    func testWriteFallsBackWhenPrimaryThrows() throws {
        let primary = StubSecretStore(writeError: StubSecretStoreError.synthetic)
        let fallback = StubSecretStore()
        let store = FallbackSecretStore(primary: primary, fallback: fallback)

        try store.setSecret("written", for: "token")

        XCTAssertEqual(try fallback.secret(for: "token"), "written")
    }

    func testInteractivePrimaryAccessMigratesFallbackSecretsAndUsesInteractivePrimaryAfterward() throws {
        let primary = StubSecretStore(readError: StubSecretStoreError.synthetic, writeError: StubSecretStoreError.synthetic)
        let interactivePrimary = StubSecretStore()
        let fallback = StubSecretStore(values: ["state.encryption.key": "encoded-key"])
        let enableFlag = StubEnableFlag()
        let store = FallbackSecretStore(
            primary: primary,
            fallback: fallback,
            interactivePrimary: interactivePrimary,
            onInteractivePrimaryEnabled: { enableFlag.setEnabled() }
        )

        XCTAssertTrue(try store.requestInteractivePrimaryAccess())
        XCTAssertEqual(try interactivePrimary.secret(for: "state.encryption.key"), "encoded-key")
        XCTAssertTrue(enableFlag.isEnabled)

        try store.setSecret("new-value", for: "gateway.token")

        XCTAssertEqual(try interactivePrimary.secret(for: "gateway.token"), "new-value")
        XCTAssertNil(try fallback.secret(for: "gateway.token"))
    }
}

private enum StubSecretStoreError: Error {
    case synthetic
}

private final class StubSecretStore: SecretStoring, SecretStoreExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private let readError: Error?
    private let writeError: Error?

    init(
        values: [String: String] = [:],
        readError: Error? = nil,
        writeError: Error? = nil
    ) {
        self.values = values
        self.readError = readError
        self.writeError = writeError
    }

    func secret(for key: String) throws -> String? {
        if let readError {
            throw readError
        }

        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setSecret(_ value: String, for key: String) throws {
        if let writeError {
            throw writeError
        }

        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func removeSecret(for key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }

    func exportSecrets() throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class StubEnableFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func setEnabled() {
        lock.lock()
        defer { lock.unlock() }
        enabled = true
    }
}
