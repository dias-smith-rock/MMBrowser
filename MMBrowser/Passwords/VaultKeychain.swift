import Foundation
import Security

/// Shared Keychain helper for the main app and Credential Provider extension.
enum VaultKeychain {
    static let appGroupID = "group.com.goodcraft.browser"
    static let accessGroup: String? = nil // Uses default team access group when entitlements set

    static let passwordsService = "com.goodcraft.browser.vault.passwords"
    static let bankCardsService = "com.goodcraft.browser.vault.bankcards"
    static let formProfileService = "com.goodcraft.browser.vault.formprofile"
    static let cryptoService = "com.goodcraft.browser.vault.crypto"

    static let blobAccount = "blob"
    static let deviceKeyAccount = "device.key"
    static let masterSaltAccount = "master.salt"
    static let masterVerifierAccount = "master.verifier"

    @discardableResult
    static func set(service: String, account: String, data: Data) -> Bool {
        _ = delete(service: service, account: account)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(service: String, account: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
