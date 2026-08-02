import Foundation
import WebKit

/// Persistent per-tab (or shared-lineage) website data stores via `WKWebsiteDataStore(forIdentifier:)`.
enum TabSessionStore {
    static func dataStore(for sessionID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: sessionID)
    }

    /// Removes the data store when no remaining normal tab references `sessionID`.
    static func removeIfOrphaned(sessionID: UUID, among tabs: [BrowserTab]) {
        let stillReferenced = tabs.contains { !$0.isIncognito && $0.sessionID == sessionID }
        guard !stillReferenced else { return }
        WKWebsiteDataStore.remove(forIdentifier: sessionID) { _ in }
    }

    /// Clears the given data types from every identifier store plus `default()`.
    static func clear(types: Set<String>, completion: (() -> Void)? = nil) {
        guard !types.isEmpty else {
            completion?()
            return
        }

        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { identifiers in
            let group = DispatchGroup()

            group.enter()
            clear(types: types, in: .default()) {
                group.leave()
            }

            for id in identifiers {
                group.enter()
                clear(types: types, in: WKWebsiteDataStore(forIdentifier: id)) {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                completion?()
            }
        }
    }

    private static func clear(types: Set<String>, in store: WKWebsiteDataStore, completion: @escaping () -> Void) {
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) {
                completion()
            }
        }
    }
}
