import UIKit

final class BrowserTab {
    let id: UUID
    var title: String
    var url: URL?
    var isIncognito: Bool
    var isNewTabPage: Bool
    var lastAccessed: Date
    var snapshot: UIImage?
    var webController: WebViewController?
    var groupName: String
    var preferDesktop: Bool

    init(isIncognito: Bool = false) {
        self.id = UUID()
        self.title = "New Tab"
        self.url = nil
        self.isIncognito = isIncognito
        self.isNewTabPage = true
        self.lastAccessed = Date()
        self.snapshot = nil
        self.webController = nil
        self.groupName = "Default"
        self.preferDesktop = false
    }

    /// Restores a previously persisted (non-incognito) tab.
    init(
        id: UUID,
        title: String,
        url: URL?,
        isNewTabPage: Bool,
        lastAccessed: Date,
        groupName: String,
        preferDesktop: Bool
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.isIncognito = false
        self.isNewTabPage = isNewTabPage
        self.lastAccessed = lastAccessed
        self.snapshot = nil
        self.webController = nil
        self.groupName = groupName
        self.preferDesktop = preferDesktop
    }

    var displayHost: String {
        if isNewTabPage { return "" }
        return url?.host ?? title
    }
}
