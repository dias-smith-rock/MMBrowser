import Foundation
import Security
import CryptoKit

/// Per-space passcode / pattern lock. Session unlock is in-memory only.
enum SpaceLockStore {
    private static let service = "com.mmbrowser.spacelock"
    private static let methodKeyPrefix = "spacelock.method."
    private static let d = UserDefaults.standard

    /// Spaces unlocked for the current foreground session.
    private static var unlockedIDs = Set<UUID>()

    // MARK: - Configuration

    static func isConfigured(_ containerID: UUID) -> Bool {
        method(for: containerID) != .none
    }

    static func method(for containerID: UUID) -> AppLockPrimaryMethod {
        AppLockPrimaryMethod(rawValue: d.string(forKey: methodKey(containerID)) ?? "") ?? .none
    }

    /// True when the space has a lock and has not been unlocked this session.
    static func requiresUnlock(_ containerID: UUID) -> Bool {
        isConfigured(containerID) && !unlockedIDs.contains(containerID)
    }

    static func markUnlocked(_ containerID: UUID) {
        unlockedIDs.insert(containerID)
    }

    static func revokeUnlock(_ containerID: UUID) {
        unlockedIDs.remove(containerID)
    }

    /// Call when the app leaves the foreground so spaces require unlock again.
    static func revokeAllUnlocks() {
        unlockedIDs.removeAll()
    }

    // MARK: - PIN / Pattern

    static func setPIN(_ pin: String, for containerID: UUID) -> Bool {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return false }
        guard let salt = ensureSalt(for: containerID),
              let hash = sha256Hex(salt + pin) else { return false }
        _ = delete(account: patternAccount(containerID))
        guard set(account: pinAccount(containerID), value: hash) else { return false }
        d.set(AppLockPrimaryMethod.pin.rawValue, forKey: methodKey(containerID))
        markUnlocked(containerID)
        return true
    }

    static func verifyPIN(_ pin: String, for containerID: UUID) -> Bool {
        guard method(for: containerID) == .pin,
              let salt = load(account: saltAccount(containerID)),
              let stored = load(account: pinAccount(containerID)),
              let hash = sha256Hex(salt + pin) else { return false }
        return hash == stored
    }

    static func setPattern(_ indices: [Int], for containerID: UUID) -> Bool {
        guard indices.count >= 4,
              Set(indices).count == indices.count,
              indices.allSatisfy({ (0...8).contains($0) }) else { return false }
        let encoded = indices.map(String.init).joined(separator: "-")
        guard let salt = ensureSalt(for: containerID),
              let hash = sha256Hex(salt + encoded) else { return false }
        _ = delete(account: pinAccount(containerID))
        guard set(account: patternAccount(containerID), value: hash) else { return false }
        d.set(AppLockPrimaryMethod.pattern.rawValue, forKey: methodKey(containerID))
        markUnlocked(containerID)
        return true
    }

    static func verifyPattern(_ indices: [Int], for containerID: UUID) -> Bool {
        guard method(for: containerID) == .pattern,
              let salt = load(account: saltAccount(containerID)),
              let stored = load(account: patternAccount(containerID)) else { return false }
        let encoded = indices.map(String.init).joined(separator: "-")
        guard let hash = sha256Hex(salt + encoded) else { return false }
        return hash == stored
    }

    static func removeLock(for containerID: UUID) {
        _ = delete(account: pinAccount(containerID))
        _ = delete(account: patternAccount(containerID))
        _ = delete(account: saltAccount(containerID))
        d.removeObject(forKey: methodKey(containerID))
        unlockedIDs.remove(containerID)
    }

    // MARK: - Keys

    private static func methodKey(_ id: UUID) -> String { methodKeyPrefix + id.uuidString }
    private static func saltAccount(_ id: UUID) -> String { "\(id.uuidString).salt" }
    private static func pinAccount(_ id: UUID) -> String { "\(id.uuidString).pin.hash" }
    private static func patternAccount(_ id: UUID) -> String { "\(id.uuidString).pattern.hash" }

    // MARK: - Hashing / Keychain

    private static func ensureSalt(for containerID: UUID) -> String? {
        let account = saltAccount(containerID)
        if let existing = load(account: account) { return existing }
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        let salt = bytes.map { String(format: "%02x", $0) }.joined()
        guard set(account: account, value: salt) else { return nil }
        return salt
    }

    private static func sha256Hex(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

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
