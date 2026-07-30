import Foundation
import Security
import CryptoKit

enum AppLockSecretStore {
    private static let service = "com.mmbrowser.applock"
    private static let saltAccount = "salt"
    private static let pinHashAccount = "pin.hash"
    private static let patternHashAccount = "pattern.hash"

    // MARK: - Public API

    static func setPIN(_ pin: String) -> Bool {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return false }
        guard let salt = ensureSalt(),
              let hash = sha256Hex(salt + pin) else { return false }
        _ = delete(account: patternHashAccount)
        AppLockSettings.primaryMethod = .pin
        return set(account: pinHashAccount, value: hash)
    }

    static func verifyPIN(_ pin: String) -> Bool {
        guard AppLockSettings.primaryMethod == .pin,
              let salt = load(account: saltAccount),
              let stored = load(account: pinHashAccount),
              let hash = sha256Hex(salt + pin) else { return false }
        return hash == stored
    }

    static func hasPIN() -> Bool {
        AppLockSettings.primaryMethod == .pin && load(account: pinHashAccount) != nil
    }

    /// Pattern as ordered unique indices 0...8, at least 4 points.
    static func setPattern(_ indices: [Int]) -> Bool {
        guard indices.count >= 4,
              Set(indices).count == indices.count,
              indices.allSatisfy({ (0...8).contains($0) }) else { return false }
        let encoded = indices.map(String.init).joined(separator: "-")
        guard let salt = ensureSalt(),
              let hash = sha256Hex(salt + encoded) else { return false }
        _ = delete(account: pinHashAccount)
        AppLockSettings.primaryMethod = .pattern
        return set(account: patternHashAccount, value: hash)
    }

    static func verifyPattern(_ indices: [Int]) -> Bool {
        guard AppLockSettings.primaryMethod == .pattern,
              let salt = load(account: saltAccount),
              let stored = load(account: patternHashAccount) else { return false }
        let encoded = indices.map(String.init).joined(separator: "-")
        guard let hash = sha256Hex(salt + encoded) else { return false }
        return hash == stored
    }

    static func hasPattern() -> Bool {
        AppLockSettings.primaryMethod == .pattern && load(account: patternHashAccount) != nil
    }

    static func clearSecrets() {
        _ = delete(account: pinHashAccount)
        _ = delete(account: patternHashAccount)
        _ = delete(account: saltAccount)
        AppLockSettings.primaryMethod = .none
    }

    // MARK: - Hashing

    private static func ensureSalt() -> String? {
        if let existing = load(account: saltAccount) { return existing }
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        let salt = bytes.map { String(format: "%02x", $0) }.joined()
        guard set(account: saltAccount, value: salt) else { return nil }
        return salt
    }

    private static func sha256Hex(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain

    private static func set(account: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        _ = delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
