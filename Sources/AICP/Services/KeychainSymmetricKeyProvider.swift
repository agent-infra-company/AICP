import CryptoKit
import Foundation

protocol SymmetricKeyProviding: AnyObject, Sendable {
    func loadOrCreateKey(reference: String) throws -> SymmetricKey
}

final class FileBackedSymmetricKeyProvider: SymmetricKeyProviding, @unchecked Sendable {
    private let secretStore: SecretStoring

    init(secretStore: SecretStoring) {
        self.secretStore = secretStore
    }

    func loadOrCreateKey(reference: String) throws -> SymmetricKey {
        if let encoded = try secretStore.secret(for: reference),
           let data = Data(base64Encoded: encoded) {
            return SymmetricKey(data: data)
        }

        let newKey = SymmetricKey(size: .bits256)
        let raw = newKey.withUnsafeBytes { Data($0) }
        try secretStore.setSecret(raw.base64EncodedString(), for: reference)
        return newKey
    }
}
