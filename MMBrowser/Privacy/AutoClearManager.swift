import Foundation
import WebKit

/// Clears selected browsing data when the app backgrounds / exits, per Clear Option settings.
enum AutoClearManager {
    static func performScheduledClear(completion: (() -> Void)? = nil) {
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

        guard !types.isEmpty else {
            NotificationCenter.default.post(name: .clearOptionSessionCleanup, object: nil)
            completion?()
            return
        }

        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .clearOptionSessionCleanup, object: nil)
                    completion?()
                }
            }
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
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                DispatchQueue.main.async { completion?() }
            }
        }
    }
}
