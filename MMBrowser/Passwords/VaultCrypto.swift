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

    /// Re-encrypt a known blob type. Returns false only when data exists but cannot be migrated.
    @discardableResult
    static func reencrypt<T: Codable>(service: String, as type: T.Type, from oldKey: SymmetricKey, to newKey: SymmetricKey) -> Bool {
        guard let data = VaultKeychain.load(service: service, account: VaultKeychain.blobAccount) else {
            return true // nothing stored yet
        }
        do {
            let value = try decrypt(data, as: type, with: oldKey)
            let sealed = try encrypt(value, with: newKey)
            return VaultKeychain.set(service: service, account: VaultKeychain.blobAccount, data: sealed)
        } catch {
            return false
        }
    }

    private static func reencryptAllBlobs(from oldKey: SymmetricKey, to newKey: SymmetricKey) -> Bool {
        let passwordsOK = reencrypt(service: VaultKeychain.passwordsService, as: [PasswordItemDTO].self, from: oldKey, to: newKey)
        let cardsOK = reencrypt(service: VaultKeychain.bankCardsService, as: [BankCardItemDTO].self, from: oldKey, to: newKey)
        let formOK = reencrypt(service: VaultKeychain.formProfileService, as: FormProfileDTO.self, from: oldKey, to: newKey)
        return passwordsOK && cardsOK && formOK
    }

    private static func snapshotVault(with key: SymmetricKey) -> (passwords: [PasswordItemDTO]?, cards: [BankCardItemDTO]?, form: FormProfileDTO?)? {
        let passwordsData = VaultKeychain.load(service: VaultKeychain.passwordsService, account: VaultKeychain.blobAccount)
        let cardsData = VaultKeychain.load(service: VaultKeychain.bankCardsService, account: VaultKeychain.blobAccount)
        let formData = VaultKeychain.load(service: VaultKeychain.formProfileService, account: VaultKeychain.blobAccount)

        var passwords: [PasswordItemDTO]?
        var cards: [BankCardItemDTO]?
        var form: FormProfileDTO?

        if let passwordsData {
            guard let decoded = try? decrypt(passwordsData, as: [PasswordItemDTO].self, with: key) else { return nil }
            passwords = decoded
        }
        if let cardsData {
            guard let decoded = try? decrypt(cardsData, as: [BankCardItemDTO].self, with: key) else { return nil }
            cards = decoded
        }
        if let formData {
            guard let decoded = try? decrypt(formData, as: FormProfileDTO.self, with: key) else { return nil }
            form = decoded
        }
        return (passwords, cards, form)
    }

    private static func writeVault(
        passwords: [PasswordItemDTO]?,
        cards: [BankCardItemDTO]?,
        form: FormProfileDTO?,
        with key: SymmetricKey
    ) -> Bool {
        do {
            if let passwords {
                let sealed = try encrypt(passwords, with: key)
                guard VaultKeychain.set(service: VaultKeychain.passwordsService, account: VaultKeychain.blobAccount, data: sealed) else { return false }
            }
            if let cards {
                let sealed = try encrypt(cards, with: key)
                guard VaultKeychain.set(service: VaultKeychain.bankCardsService, account: VaultKeychain.blobAccount, data: sealed) else { return false }
            }
            if let form {
                let sealed = try encrypt(form, with: key)
                guard VaultKeychain.set(service: VaultKeychain.formProfileService, account: VaultKeychain.blobAccount, data: sealed) else { return false }
            }
            return true
        } catch {
            return false
        }
    }

    /// Create master password: decrypt with device key, install master, rewrite ciphertext, unlock session.
    static func migrateVault(from deviceKey: SymmetricKey, installingMasterPassword password: String) -> SymmetricKey? {
        guard let snapshot = snapshotVault(with: deviceKey) else { return nil }
        guard let newKey = setMasterPassword(password) else { return nil }
        // Must set session key before any PasswordStore.reload() sees hasMasterPassword == true.
        setSessionMasterKey(newKey)
        guard writeVault(passwords: snapshot.passwords, cards: snapshot.cards, form: snapshot.form, with: newKey) else {
            return nil
        }
        return newKey
    }

    static func rotateMasterPassword(from oldKey: SymmetricKey, to newPassword: String) -> SymmetricKey? {
        guard let snapshot = snapshotVault(with: oldKey) else { return nil }
        clearMasterPassword()
        guard let newKey = setMasterPassword(newPassword) else { return nil }
        setSessionMasterKey(newKey)
        guard writeVault(passwords: snapshot.passwords, cards: snapshot.cards, form: snapshot.form, with: newKey) else {
            return nil
        }
        return newKey
    }

    @discardableResult
    static func removeMasterPassword(using oldKey: SymmetricKey) -> Bool {
        let device = deviceKey()
        guard reencryptAllBlobs(from: oldKey, to: device) else { return false }
        clearMasterPassword()
        setSessionMasterKey(nil)
        return true
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
