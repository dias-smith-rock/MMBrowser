import UIKit

final class BrowserTab {
    let id: UUID
    /// Container that owns this tab's website-data session (normal tabs only).
    var containerID: UUID
    var title: String
    var url: URL?
    var isIncognito: Bool
    var isNewTabPage: Bool
    var lastAccessed: Date
    var snapshot: UIImage?
    var webController: WebViewController?
    var preferDesktop: Bool
    /// Best-effort logged-in account avatar from the current page.
    var sessionAvatarURL: URL?
    var sessionAvatar: UIImage?
    /// Back/forward URLs for this tab (persisted for normal tabs).
    let navigationHistory = TabNavigationHistory()

    init(isIncognito: Bool = false, containerID: UUID) {
        self.id = UUID()
        self.containerID = containerID
        self.title = "New Tab"
        self.url = nil
        self.isIncognito = isIncognito
        self.isNewTabPage = true
        self.lastAccessed = Date()
        self.snapshot = nil
        self.webController = nil
        self.preferDesktop = false
        self.sessionAvatarURL = nil
        self.sessionAvatar = nil
    }

    /// Restores a previously persisted (non-incognito) tab.
    init(
        id: UUID,
        containerID: UUID,
        title: String,
        url: URL?,
        isNewTabPage: Bool,
        lastAccessed: Date,
        preferDesktop: Bool,
        historyURLs: [String] = [],
        historyIndex: Int = -1
    ) {
        self.id = id
        self.containerID = containerID
        self.title = title
        self.url = url
        self.isIncognito = false
        self.isNewTabPage = isNewTabPage
        self.lastAccessed = lastAccessed
        self.snapshot = nil
        self.webController = nil
        self.preferDesktop = preferDesktop
        self.sessionAvatarURL = nil
        self.sessionAvatar = nil
        if !historyURLs.isEmpty {
            navigationHistory.restore(urls: historyURLs, index: historyIndex)
        } else if let url, !isNewTabPage {
            navigationHistory.restore(urls: [url.absoluteString], index: 0)
        }
    }

    var displayHost: String {
        if isNewTabPage { return "" }
        return url?.host ?? title
    }

    func clearSessionAvatar() {
        sessionAvatarURL = nil
        sessionAvatar = nil
    }

    func clearNavigationHistory() {
        navigationHistory.clear()
    }
}
