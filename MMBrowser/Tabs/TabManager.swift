import Foundation

protocol TabManagerDelegate: AnyObject {
    func tabManagerDidUpdate(_ manager: TabManager)
    func tabManager(_ manager: TabManager, didSelect tab: BrowserTab)
}

final class TabManager {
    weak var delegate: TabManagerDelegate?

    private(set) var tabs: [BrowserTab] = []
    private(set) var selectedIndex: Int = 0
    private(set) var groupNames: [String] = ["Default", "Work", "Personal"]

    private let sessionKey = "mmbrowser.tabs.session"
    private let defaults = UserDefaults.standard

    var selectedTab: BrowserTab? {
        guard tabs.indices.contains(selectedIndex) else { return nil }
        return tabs[selectedIndex]
    }

    var normalTabs: [BrowserTab] { tabs.filter { !$0.isIncognito } }
    var incognitoTabs: [BrowserTab] { tabs.filter { $0.isIncognito } }

    init() {
        if !AppSettings.closeAllTabsOnExit, restorePersistedSession() {
            return
        }
        clearPersistedSession()
        tabs = [BrowserTab()]
        selectedIndex = 0
    }

    @discardableResult
    func addTab(incognito: Bool = false, select: Bool = true) -> BrowserTab {
        let tab = BrowserTab(isIncognito: incognito)
        tabs.append(tab)
        if select {
            selectedIndex = tabs.count - 1
            tab.lastAccessed = Date()
            delegate?.tabManager(self, didSelect: tab)
        }
        notifyUpdated()
        return tab
    }

    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        tabs[index].lastAccessed = Date()
        delegate?.tabManager(self, didSelect: tabs[index])
        notifyUpdated()
    }

    /// Swipe between tabs in list order. Returns whether selection changed.
    @discardableResult
    func selectAdjacentTab(offset: Int) -> Bool {
        let newIndex = selectedIndex + offset
        guard tabs.indices.contains(newIndex), newIndex != selectedIndex else { return false }
        selectedIndex = newIndex
        tabs[newIndex].lastAccessed = Date()
        delegate?.tabManager(self, didSelect: tabs[newIndex])
        notifyUpdated()
        return true
    }

    func recentBrowsedTabs(limit: Int = 1) -> [BrowserTab] {
        tabs
            .filter { !$0.isIncognito && !$0.isNewTabPage && $0.url != nil }
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .prefix(limit)
            .map { $0 }
    }

    /// Closes every private tab and wipes their WebViews / snapshots.
    func closeAllIncognitoTabs() {
        let privateTabs = incognitoTabs
        guard !privateTabs.isEmpty else { return }
        for tab in privateTabs {
            tab.webController?.cleanup()
            tab.webController = nil
            tab.snapshot = nil
            TabSnapshotStore.remove(for: tab.id)
        }
        tabs.removeAll { $0.isIncognito }
        if tabs.isEmpty {
            tabs = [BrowserTab(isIncognito: false)]
            selectedIndex = 0
            delegate?.tabManager(self, didSelect: tabs[0])
        } else {
            selectedIndex = min(selectedIndex, tabs.count - 1)
            if let selected = selectedTab {
                selected.lastAccessed = Date()
                delegate?.tabManager(self, didSelect: selected)
            }
        }
        notifyUpdated()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        let wasIncognito = closing.isIncognito
        closing.webController?.cleanup()
        closing.webController = nil
        closing.snapshot = nil
        TabSnapshotStore.remove(for: closing.id)
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = BrowserTab(isIncognito: false)
            tabs = [replacement]
            selectedIndex = 0
            delegate?.tabManager(self, didSelect: replacement)
        } else {
            selectedIndex = min(index, tabs.count - 1)
            if let selected = selectedTab {
                selected.lastAccessed = Date()
                delegate?.tabManager(self, didSelect: selected)
            }
        }

        // Last private tab closed — ensure no leftover private WebViews/snapshots.
        if wasIncognito, incognitoTabs.isEmpty {
            for tab in tabs where tab.isIncognito {
                tab.webController?.cleanup()
                tab.webController = nil
                tab.snapshot = nil
            }
        }
        notifyUpdated()
    }

    /// Close every tab and leave a single fresh New Tab (used by Close All Tabs on Exit).
    func closeAllTabsAndReset() {
        for tab in tabs {
            tab.webController?.cleanup()
            tab.webController = nil
            tab.snapshot = nil
            TabSnapshotStore.remove(for: tab.id)
        }
        let fresh = BrowserTab(isIncognito: false)
        tabs = [fresh]
        selectedIndex = 0
        clearPersistedSession()
        delegate?.tabManager(self, didSelect: fresh)
        notifyUpdated()
    }

    func clearAllSnapshots() {
        for tab in tabs {
            tab.snapshot = nil
            TabSnapshotStore.remove(for: tab.id)
        }
        delegate?.tabManagerDidUpdate(self)
    }

    func tabs(matching query: String, incognito: Bool) -> [BrowserTab] {
        let base = incognito ? incognitoTabs : normalTabs
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q) || ($0.url?.absoluteString.lowercased().contains(q) ?? false) || $0.groupName.lowercased().contains(q)
        }
    }

    func moveTab(_ id: UUID, toGroup name: String) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.groupName = name
        if !groupNames.contains(name) { groupNames.append(name) }
        notifyUpdated()
    }

    func invalidateAllWebViews() {
        for tab in tabs {
            tab.webController?.cleanup()
            tab.webController = nil
        }
        delegate?.tabManagerDidUpdate(self)
        if let selected = selectedTab {
            delegate?.tabManager(self, didSelect: selected)
        }
    }

    // MARK: - Persistence (when Close All Tabs on Exit is off)

    private func notifyUpdated() {
        delegate?.tabManagerDidUpdate(self)
        persistSessionIfNeeded()
    }

    /// Saves normal tabs so they survive relaunch when auto-close-tabs is disabled.
    func persistSessionIfNeeded() {
        if AppSettings.closeAllTabsOnExit {
            clearPersistedSession()
            return
        }
        let normal = normalTabs
        guard !normal.isEmpty else {
            clearPersistedSession()
            return
        }
        let selectedID = selectedTab.flatMap { $0.isIncognito ? nil : $0.id }
        let index = selectedID.flatMap { id in normal.firstIndex(where: { $0.id == id }) } ?? 0
        let payload = PersistedSession(
            tabs: normal.map {
                PersistedTab(
                    id: $0.id,
                    title: $0.title,
                    urlString: $0.url?.absoluteString,
                    isNewTabPage: $0.isNewTabPage,
                    lastAccessed: $0.lastAccessed,
                    groupName: $0.groupName,
                    preferDesktop: $0.preferDesktop
                )
            },
            selectedIndex: index,
            groupNames: groupNames
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: sessionKey)
        }
        // Persist in-memory previews and drop orphans.
        var keep = Set<UUID>()
        for tab in normal {
            keep.insert(tab.id)
            if let snapshot = tab.snapshot, AppSettings.showTabsPreviewImages {
                TabSnapshotStore.save(snapshot, for: tab.id)
            }
        }
        TabSnapshotStore.removeAll(except: keep)
    }

    func clearPersistedSession() {
        defaults.removeObject(forKey: sessionKey)
        TabSnapshotStore.removeAll()
    }

    @discardableResult
    private func restorePersistedSession() -> Bool {
        guard let data = defaults.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(PersistedSession.self, from: data),
              !session.tabs.isEmpty else {
            return false
        }
        tabs = session.tabs.map {
            let url = $0.urlString.flatMap(URL.init(string:))
            let tab = BrowserTab(
                id: $0.id,
                title: $0.title,
                url: url,
                isNewTabPage: url == nil,
                lastAccessed: $0.lastAccessed,
                groupName: $0.groupName,
                preferDesktop: $0.preferDesktop
            )
            if AppSettings.showTabsPreviewImages {
                tab.snapshot = TabSnapshotStore.load(for: $0.id)
            }
            return tab
        }
        groupNames = session.groupNames.isEmpty ? ["Default", "Work", "Personal"] : session.groupNames
        selectedIndex = min(max(0, session.selectedIndex), tabs.count - 1)
        return true
    }
}

private struct PersistedSession: Codable {
    var tabs: [PersistedTab]
    var selectedIndex: Int
    var groupNames: [String]
}

private struct PersistedTab: Codable {
    let id: UUID
    var title: String
    var urlString: String?
    var isNewTabPage: Bool
    var lastAccessed: Date
    var groupName: String
    var preferDesktop: Bool
}
