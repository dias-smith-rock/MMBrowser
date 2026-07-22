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

    var displayHost: String {
        if isNewTabPage { return "" }
        return url?.host ?? title
    }
}
