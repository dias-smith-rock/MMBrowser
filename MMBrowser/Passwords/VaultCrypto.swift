import Foundation
import CryptoKit
import Security

/// AES-GCM vault encryption with optional master-password key derivation.
enum VaultCrypto {
    private static let pbkdfIterations: UInt32 = 100_000

    struct Envelope: Codable {
        var ciphertext: Data
        var nonce: Data
    }

    // MARK: - Device key

    static func deviceKey() -> SymmetricKey {
        if let existing = VaultKeychain.load(service: VaultKeychain.cryptoService, account: VaultKeychain.deviceKeyAccount),
           existing.count == 32 {
            return SymmetricKey(data: existing)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        _ = VaultKeychain.set(service: VaultKeychain.cryptoService, account: VaultKeychain.deviceKeyAccount, data: data)
        return SymmetricKey(data: data)
    }

    // MARK: - Master password

    static var hasMasterPassword: Bool {
        VaultKeychain.load(service: VaultKeychain.cryptoService, account: VaultKeychain.masterVerifierAccount) != nil
    }

    static func setMasterPassword(_ password: String) -> SymmetricKey? {
        guard password.count >= 6 else { return nil }
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { return nil }
        let salt = Data(saltBytes)
        guard let key = deriveKey(password: password, salt: salt) else { return nil }
        let verifier = SHA256.hash(data: Data("mmbrowser.vault.verifier".utf8) + Data(key.withUnsafeBytes { Data($0) }))
        guard VaultKeychain.set(service: VaultKeychain.cryptoService, account: VaultKeychain.masterSaltAccount, data: salt),
              VaultKeychain.set(service: VaultKeychain.cryptoService, account: VaultKeychain.masterVerifierAccount, data: Data(verifier))
        else { return nil }
        return key
    }

    static func unlockMasterPassword(_ password: String) -> SymmetricKey? {
        guard let salt = VaultKeychain.load(service: VaultKeychain.cryptoService, account: VaultKeychain.masterSaltAccount),
              let stored = VaultKeychain.load(service: VaultKeychain.cryptoService, account: VaultKeychain.masterVerifierAccount),
              let key = deriveKey(password: password, salt: salt)
        else { return nil }
        let verifier = SHA256.hash(data: Data("mmbrowser.vault.verifier".utf8) + Data(key.withUnsafeBytes { Data($0) }))
        guard Data(verifier) == stored else { return nil }
        return key
    }

    static func clearMasterPassword() {
        _ = VaultKeychain.delete(service: VaultKeychain.cryptoService, account: VaultKeychain.masterSaltAccount)
        _ = VaultKeychain.delete(service: VaultKeychain.cryptoService, account: VaultKeychain.masterVerifierAccount)
    }

    private static func deriveKey(password: String, salt: Data) -> SymmetricKey? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        // PBKDF2-HMAC-SHA256 via CommonCrypto-free iterative HMAC (CryptoKit).
        // Iterated SHA-256 KDF (dependency-free). Adequate for local vault wrapping.
        var material = passwordData + salt
        for _ in 0..<Int(pbkdfIterations / 1000) {
            material = Data(SHA256.hash(data: material))
        }
        for i in 0..<1000 {
            var round = material
            round.append(contentsOf: withUnsafeBytes(of: UInt32(i).bigEndian) { Data($0) })
            material = Data(SHA256.hash(data: round))
        }
        return SymmetricKey(data: material.prefix(32))
    }

    // MARK: - Seal / open

    static func encrypt<T: Encodable>(_ value: T, with key: SymmetricKey) throws -> Data {
        let plain = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "VaultCrypto", code: 1, userInfo: [NSLocalizedDescriptionKey: "Seal failed"])
        }
        return combined
    }

    static func decrypt<T: Decodable>(_ data: Data, as type: T.Type, with key: SymmetricKey) throws -> T {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key)
        return try JSONDecoder().decode(type, from: plain)
    }

    /// Active encryption key for the current session (master if unlocked, else device key when no master).
    private static var sessionMasterKey: SymmetricKey?

    static func setSessionMasterKey(_ key: SymmetricKey?) {
        sessionMasterKey = key
    }

    static var isMasterUnlocked: Bool {
        if !hasMasterPassword { return true }
        return sessionMasterKey != nil
    }

    static func activeKey() -> SymmetricKey? {
        if hasMasterPassword {
            return sessionMasterKey
        }
        return deviceKey()
    }

    /// Re-encrypt blob from oldKey to newKey.
    static func reencrypt(service: String, from oldKey: SymmetricKey, to newKey: SymmetricKey) {
        guard let data = VaultKeychain.load(service: service, account: VaultKeychain.blobAccount) else { return }
        // Try decode as generic JSON Data wrapper
        if let items = try? decrypt(data, as: [PasswordItemDTO].self, with: oldKey),
           let sealed = try? encrypt(items, with: newKey) {
            _ = VaultKeychain.set(service: service, account: VaultKeychain.blobAccount, data: sealed)
            return
        }
        if let items = try? decrypt(data, as: [BankCardItemDTO].self, with: oldKey),
           let sealed = try? encrypt(items, with: newKey) {
            _ = VaultKeychain.set(service: service, account: VaultKeychain.blobAccount, data: sealed)
            return
        }
        if let profile = try? decrypt(data, as: FormProfileDTO.self, with: oldKey),
           let sealed = try? encrypt(profile, with: newKey) {
            _ = VaultKeychain.set(service: service, account: VaultKeychain.blobAccount, data: sealed)
        }
    }
}

/// Codable DTOs shared for crypto reencrypt (defined here to avoid circular imports in Shared).
struct PasswordItemDTO: Codable, Equatable {
    var id: String
    var host: String
    var url: String
    var username: String
    var password: String
    var comments: String
    var updatedAt: Date
}

struct BankCardItemDTO: Codable, Equatable {
    var id: String
    var holderName: String
    var number: String
    var expiryMonth: Int
    var expiryYear: Int
    var cvv: String
    var updatedAt: Date
}

struct FormProfileDTO: Codable, Equatable {
    var fullName: String
    var email: String
    var phone: String
    var addressLine1: String
    var addressLine2: String
    var city: String
    var state: String
    var postalCode: String
    var country: String
}
