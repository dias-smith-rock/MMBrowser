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

    var selectedTab: BrowserTab? {
        guard tabs.indices.contains(selectedIndex) else { return nil }
        return tabs[selectedIndex]
    }

    var normalTabs: [BrowserTab] { tabs.filter { !$0.isIncognito } }
    var incognitoTabs: [BrowserTab] { tabs.filter { $0.isIncognito } }

    init() {
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
        delegate?.tabManagerDidUpdate(self)
        return tab
    }

    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        tabs[index].lastAccessed = Date()
        delegate?.tabManager(self, didSelect: tabs[index])
        delegate?.tabManagerDidUpdate(self)
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        closing.webController?.cleanup()
        closing.webController = nil
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = BrowserTab(isIncognito: closing.isIncognito)
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
        delegate?.tabManagerDidUpdate(self)
    }

    func recentBrowsedTabs(limit: Int = 1) -> [BrowserTab] {
        tabs
            .filter { !$0.isNewTabPage && $0.url != nil }
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .prefix(limit)
            .map { $0 }
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
        delegate?.tabManagerDidUpdate(self)
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
}
