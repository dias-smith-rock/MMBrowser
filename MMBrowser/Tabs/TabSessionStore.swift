import Foundation
import WebKit

/// Persistent website data stores keyed by container `sessionID`.
enum TabSessionStore {
    static func dataStore(for sessionID: UUID) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: sessionID)
    }

    /// Removes the data store when no container still owns `sessionID`.
    static func removeIfOrphaned(sessionID: UUID, containers: [BrowserContainer]) {
        let stillReferenced = containers.contains { $0.sessionID == sessionID }
        guard !stillReferenced else { return }
        let work = {
            WKWebsiteDataStore.remove(forIdentifier: sessionID) { _ in }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    /// Clears data types in the given Space session stores only.
    static func clear(types: Set<String>, sessionIDs: [UUID], completion: (() -> Void)? = nil) {
        guard !types.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }
        let start = {
            let stores = sessionIDs.map { WKWebsiteDataStore(forIdentifier: $0) }
            clearSequentially(types: types, stores: stores, index: 0) {
                DispatchQueue.main.async { completion?() }
            }
        }
        if Thread.isMainThread { start() } else { DispatchQueue.main.async(execute: start) }
    }

    static func removeRecords(matchingHost host: String, types: Set<String>, sessionID: UUID, completion: @escaping () -> Void) {
        let normalized = host.lowercased()
        let work = {
            let store = WKWebsiteDataStore(forIdentifier: sessionID)
            store.fetchDataRecords(ofTypes: types) { records in
                let matched = records.filter { record in
                    let name = record.displayName.lowercased()
                    return name == normalized || name.hasSuffix("." + normalized) || normalized.hasSuffix("." + name)
                }
                DispatchQueue.main.async {
                    guard !matched.isEmpty else {
                        completion()
                        return
                    }
                    store.removeData(ofTypes: types, for: matched) {
                        DispatchQueue.main.async { completion() }
                    }
                }
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Clears the given data types from every identifier store plus `default()`.
    /// WebKit data-store APIs must run on the main thread and are safer when serialized.
    static func clear(types: Set<String>, completion: (() -> Void)? = nil) {
        guard !types.isEmpty else {
            DispatchQueue.main.async { completion?() }
            return
        }

        let finishOnMain = {
            DispatchQueue.main.async { completion?() }
        }

        let start = {
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { identifiers in
                // Callback may arrive off-main; hop back before touching WebKit stores.
                DispatchQueue.main.async {
                    var stores: [WKWebsiteDataStore] = [.default()]
                    for id in identifiers {
                        stores.append(WKWebsiteDataStore(forIdentifier: id))
                    }
                    clearSequentially(types: types, stores: stores, index: 0, completion: finishOnMain)
                }
            }
        }

        if Thread.isMainThread {
            start()
        } else {
            DispatchQueue.main.async(execute: start)
        }
    }

    private static func clearSequentially(
        types: Set<String>,
        stores: [WKWebsiteDataStore],
        index: Int,
        completion: @escaping () -> Void
    ) {
        guard index < stores.count else {
            completion()
            return
        }
        clear(types: types, in: stores[index]) {
            clearSequentially(types: types, stores: stores, index: index + 1, completion: completion)
        }
    }

    private static func clear(types: Set<String>, in store: WKWebsiteDataStore, completion: @escaping () -> Void) {
        store.fetchDataRecords(ofTypes: types) { records in
            // Keep remove on main as well — WebKit is not reliably thread-safe here.
            DispatchQueue.main.async {
                store.removeData(ofTypes: types, for: records) {
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            }
        }
    }
}
