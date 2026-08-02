import Foundation

struct BrowserContainer: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    /// Shared `WKWebsiteDataStore(forIdentifier:)` for all normal tabs in this container.
    var sessionID: UUID
    var sortIndex: Int

    static func makeDefaults() -> [BrowserContainer] {
        [
            BrowserContainer(id: UUID(), name: "Default", sessionID: UUID(), sortIndex: 0),
            BrowserContainer(id: UUID(), name: "Work", sessionID: UUID(), sortIndex: 1),
            BrowserContainer(id: UUID(), name: "Personal", sessionID: UUID(), sortIndex: 2)
        ]
    }
}
