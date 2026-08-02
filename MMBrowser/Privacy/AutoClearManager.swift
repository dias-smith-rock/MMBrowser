import Foundation
import WebKit

/// Clears selected browsing data when the app backgrounds / exits, per Clear Option settings.
enum AutoClearManager {
    /// - Parameter runSessionCleanup: When true, also posts `.clearOptionSessionCleanup` (close tabs).
    ///   Pass `false` on cold launch so onboarding / first UI is not dismissed.
    static func performScheduledClear(runSessionCleanup: Bool = true, completion: (() -> Void)? = nil) {
        let clearHistory = AppSettings.autoClearHistory
        let clearCookies = AppSettings.autoClearCookies
        let clearLocalStorage = AppSettings.autoClearLocalStorage
        let clearCache = AppSettings.autoClearCache

        if clearHistory {
            HistoryStore.shared.clear()
        }

        var types = Set<String>()
        if clearCookies {
            types.insert(WKWebsiteDataTypeCookies)
        }
        if clearLocalStorage {
            types.formUnion([
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeSessionStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases
            ])
        }
        if clearCache {
            types.formUnion([
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache
            ])
        }

        let finish = {
            // Only close tabs when that Clear Option is enabled.
            if runSessionCleanup, AppSettings.closeAllTabsOnExit {
                NotificationCenter.default.post(name: .clearOptionSessionCleanup, object: nil)
            }
            completion?()
        }

        guard !types.isEmpty else {
            finish()
            return
        }

        TabSessionStore.clear(types: types) {
            finish()
        }
    }

    /// Immediately clear one category when the user turns its auto-clear switch on.
    static func clearNow(history: Bool = false, cookies: Bool = false, localStorage: Bool = false, cache: Bool = false, completion: (() -> Void)? = nil) {
        if history { HistoryStore.shared.clear() }
        var types = Set<String>()
        if cookies { types.insert(WKWebsiteDataTypeCookies) }
        if localStorage {
            types.formUnion([
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeSessionStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases
            ])
        }
        if cache {
            types.formUnion([
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache
            ])
        }
        guard !types.isEmpty else {
            completion?()
            return
        }
        TabSessionStore.clear(types: types, completion: completion)
    }
}
