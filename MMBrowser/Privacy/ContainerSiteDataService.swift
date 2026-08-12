import Foundation
import WebKit

struct SiteDataSummary: Equatable {
    var host: String
    var recordCount: Int
    var dataTypes: [String]
}

enum ContainerSiteDataService {
    private static let displayTypes: Set<String> = [
        WKWebsiteDataTypeCookies,
        WKWebsiteDataTypeLocalStorage,
        WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeIndexedDBDatabases,
        WKWebsiteDataTypeWebSQLDatabases,
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache
    ]

    static func fetchSummaries(sessionID: UUID, completion: @escaping ([SiteDataSummary]) -> Void) {
        let store = TabSessionStore.dataStore(for: sessionID)
        store.fetchDataRecords(ofTypes: displayTypes) { records in
            DispatchQueue.main.async {
                var grouped: [String: (count: Int, types: Set<String>)] = [:]
                for record in records {
                    let host = record.displayName.lowercased()
                    var entry = grouped[host] ?? (0, [])
                    entry.count += 1
                    entry.types.formUnion(record.dataTypes)
                    grouped[host] = entry
                }
                let summaries = grouped.map { host, value in
                    SiteDataSummary(host: host, recordCount: value.count, dataTypes: value.types.sorted())
                }.sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
                completion(summaries)
            }
        }
    }

    static func remove(host: String, sessionID: UUID, completion: @escaping () -> Void) {
        let store = TabSessionStore.dataStore(for: sessionID)
        let key = host.lowercased()
        store.fetchDataRecords(ofTypes: displayTypes) { records in
            DispatchQueue.main.async {
                let targets = records.filter { $0.displayName.lowercased() == key }
                guard !targets.isEmpty else {
                    completion()
                    return
                }
                store.removeData(ofTypes: displayTypes, for: targets) {
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }

    static func clearAll(sessionID: UUID, completion: @escaping () -> Void) {
        let store = TabSessionStore.dataStore(for: sessionID)
        store.fetchDataRecords(ofTypes: displayTypes) { records in
            DispatchQueue.main.async {
                guard !records.isEmpty else {
                    completion()
                    return
                }
                store.removeData(ofTypes: displayTypes, for: records) {
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }

    static func estimatedLoggedInDomains(sessionID: UUID, completion: @escaping (Int) -> Void) {
        fetchSummaries(sessionID: sessionID) { summaries in
            let cookieHosts = summaries.filter { $0.dataTypes.contains(WKWebsiteDataTypeCookies) }.count
            completion(cookieHosts)
        }
    }
}
