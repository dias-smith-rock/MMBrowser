import Foundation
import UIKit

protocol TabManagerDelegate: AnyObject {
    func tabManagerDidUpdate(_ manager: TabManager)
    func tabManager(_ manager: TabManager, didSelect tab: BrowserTab)
}

final class TabManager {
    weak var delegate: TabManagerDelegate?

    private(set) var tabs: [BrowserTab] = []
    private(set) var selectedIndex: Int = 0
    private(set) var containers: [BrowserContainer] = []
    /// Last focused normal-tab container; restored across launches even when tabs are closed on exit.
    private(set) var lastActiveContainerID: UUID?

    private let sessionKey = "mmbrowser.tabs.session"
    private let containersKey = "mmbrowser.containers"
    private let lastContainerKey = "mmbrowser.containers.lastActive"
    /// Marks migration from Default/Work/Personal → FB-1… then → Personal/Work/Social.
    private let containersPresetKey = "mmbrowser.containers.preset.v2"
    private let containersPresetV3Key = "mmbrowser.containers.preset.v3"
    /// Set when tabs were intentionally closed on exit; cleared on next launch.
    private let cleanExitKey = "mmbrowser.tabs.cleanExit"
    private let defaults = UserDefaults.standard

    var selectedTab: BrowserTab? {
        guard tabs.indices.contains(selectedIndex) else { return nil }
        return tabs[selectedIndex]
    }

    var normalTabs: [BrowserTab] { tabs.filter { !$0.isIncognito } }
    var incognitoTabs: [BrowserTab] { tabs.filter { $0.isIncognito } }

    var sortedContainers: [BrowserContainer] {
        containers.sorted { $0.sortIndex < $1.sortIndex }
    }

    var defaultContainer: BrowserContainer {
        sortedContainers.first ?? containers[0]
    }

    /// Prefer last active container when it still exists; otherwise Default.
    var resolvedLastActiveContainerID: UUID {
        if let id = lastActiveContainerID, container(id: id) != nil { return id }
        return defaultContainer.id
    }

    /// Switch browsing identity: select most-recent tab in the account, or open a new tab.
    @discardableResult
    func switchToAccount(_ id: UUID) -> BrowserTab? {
        guard container(id: id) != nil else { return nil }
        lastActiveContainerID = id
        defaults.set(id.uuidString, forKey: lastContainerKey)

        let candidates = normalTabs
            .filter { $0.containerID == id }
            .sorted { $0.lastAccessed > $1.lastAccessed }
        if let best = candidates.first {
            selectTab(id: best.id)
            return best
        }
        return addTab(incognito: false, select: true, containerID: id)
    }

    func accountColor(for tab: BrowserTab) -> UIColor {
        if let c = container(id: tab.containerID) {
            return AccountColor.color(for: c)
        }
        return AccountColor.color(at: 0)
    }

    func accountColor(forContainer id: UUID) -> UIColor {
        if let c = container(id: id) {
            return AccountColor.color(for: c)
        }
        return AccountColor.color(at: 0)
    }

    init() {
        loadPersistedContainers()
        let cleanExit = defaults.bool(forKey: cleanExitKey)
        defaults.set(false, forKey: cleanExitKey)

        // Only skip restore after an intentional "close tabs on exit" cleanup.
        // Abnormal termination keeps the last persisted session for crash recovery.
        if cleanExit {
            clearPersistedSession()
            tabs = [BrowserTab(containerID: resolvedLastActiveContainerID)]
            selectedIndex = 0
            noteActiveContainer(from: selectedTab)
            return
        }

        if restorePersistedSession() {
            noteActiveContainer(from: selectedTab)
            return
        }

        tabs = [BrowserTab(containerID: resolvedLastActiveContainerID)]
        selectedIndex = 0
        noteActiveContainer(from: selectedTab)
    }

    func container(id: UUID) -> BrowserContainer? {
        containers.first { $0.id == id }
    }

    func containerName(for tab: BrowserTab) -> String {
        container(id: tab.containerID)?.name ?? defaultContainer.name
    }

    func sessionID(for tab: BrowserTab) -> UUID {
        container(id: tab.containerID)?.sessionID ?? defaultContainer.sessionID
    }

    /// - Parameter containerID: Container for a normal tab. Defaults to the selected tab's container, or Default.
    @discardableResult
    func addTab(incognito: Bool = false, select: Bool = true, containerID: UUID? = nil) -> BrowserTab {
        let resolvedContainerID: UUID = {
            if let containerID, container(id: containerID) != nil { return containerID }
            if let selected = selectedTab, !selected.isIncognito {
                return selected.containerID
            }
            return defaultContainer.id
        }()
        let tab = BrowserTab(isIncognito: incognito, containerID: resolvedContainerID)
        tabs.append(tab)
        if select {
            selectedIndex = tabs.count - 1
            tab.lastAccessed = Date()
            noteActiveContainer(from: tab)
            delegate?.tabManager(self, didSelect: tab)
        }
        notifyUpdated()
        return tab
    }

    func selectTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
        tabs[index].lastAccessed = Date()
        noteActiveContainer(from: tabs[index])
        delegate?.tabManager(self, didSelect: tabs[index])
        notifyUpdated()
    }

    /// Indices of tabs that address-bar swipe may move between (same pool + same container for normal tabs).
    private func swipePoolIndices(around tab: BrowserTab) -> [Int] {
        tabs.indices.filter { index in
            let candidate = tabs[index]
            guard candidate.isIncognito == tab.isIncognito else { return false }
            if tab.isIncognito { return true }
            return candidate.containerID == tab.containerID
        }
    }

    func tabIndex(adjacentOffset offset: Int) -> Int? {
        guard let current = selectedTab else { return nil }
        let pool = swipePoolIndices(around: current)
        guard let pos = pool.firstIndex(of: selectedIndex) else { return nil }
        let next = pos + offset
        guard pool.indices.contains(next) else { return nil }
        return pool[next]
    }

    func canSelectAdjacentTab(offset: Int) -> Bool {
        tabIndex(adjacentOffset: offset) != nil
    }

    func tab(adjacentOffset offset: Int) -> BrowserTab? {
        guard let index = tabIndex(adjacentOffset: offset) else { return nil }
        return tabs[index]
    }

    @discardableResult
    func selectAdjacentTab(offset: Int) -> Bool {
        guard let newIndex = tabIndex(adjacentOffset: offset), newIndex != selectedIndex else { return false }
        selectedIndex = newIndex
        tabs[newIndex].lastAccessed = Date()
        noteActiveContainer(from: tabs[newIndex])
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

    func closeAllIncognitoTabs() {
        let privateTabs = incognitoTabs
        guard !privateTabs.isEmpty else { return }
        for tab in privateTabs {
            tab.clearNavigationHistory()
            tab.webController?.cleanup()
            tab.webController = nil
            tab.snapshot = nil
            TabSnapshotStore.remove(for: tab.id)
        }
        tabs.removeAll { $0.isIncognito }
        if tabs.isEmpty {
            let replacement = BrowserTab(containerID: resolvedLastActiveContainerID)
            tabs = [replacement]
            selectedIndex = 0
            noteActiveContainer(from: replacement)
            delegate?.tabManager(self, didSelect: replacement)
        } else {
            selectedIndex = min(selectedIndex, tabs.count - 1)
            if let selected = selectedTab {
                selected.lastAccessed = Date()
                noteActiveContainer(from: selected)
                delegate?.tabManager(self, didSelect: selected)
            }
        }
        notifyUpdated()
    }

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        let wasIncognito = closing.isIncognito
        closing.clearNavigationHistory()
        closing.webController?.cleanup()
        closing.webController = nil
        closing.snapshot = nil
        TabSnapshotStore.remove(for: closing.id)
        tabs.remove(at: index)

        if tabs.isEmpty {
            let replacement = BrowserTab(containerID: resolvedLastActiveContainerID)
            tabs = [replacement]
            selectedIndex = 0
            noteActiveContainer(from: replacement)
            delegate?.tabManager(self, didSelect: replacement)
        } else {
            selectedIndex = min(index, tabs.count - 1)
            if let selected = selectedTab {
                selected.lastAccessed = Date()
                noteActiveContainer(from: selected)
                delegate?.tabManager(self, didSelect: selected)
            }
        }

        if wasIncognito, incognitoTabs.isEmpty {
            for tab in tabs where tab.isIncognito {
                tab.webController?.cleanup()
                tab.webController = nil
                tab.snapshot = nil
            }
        }
        notifyUpdated()
    }

    func closeAllTabsAndReset() {
        for tab in tabs {
            tab.clearNavigationHistory()
            tab.webController?.cleanup()
            tab.webController = nil
            tab.snapshot = nil
            TabSnapshotStore.remove(for: tab.id)
        }
        let fresh = BrowserTab(containerID: resolvedLastActiveContainerID)
        tabs = [fresh]
        selectedIndex = 0
        noteActiveContainer(from: fresh)
        markCleanExitAndClearSession()
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
            let name = containerName(for: $0)
            return $0.title.lowercased().contains(q)
                || ($0.url?.absoluteString.lowercased().contains(q) ?? false)
                || name.lowercased().contains(q)
        }
    }

    // MARK: - Containers

    @discardableResult
    func addContainer(_ draft: BrowserContainer) -> BrowserContainer? {
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if containers.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return nil
        }
        let nextIndex = (containers.map(\.sortIndex).max() ?? -1) + 1
        let container = BrowserContainer(
            id: UUID(),
            name: trimmed,
            sessionID: UUID(),
            sortIndex: nextIndex,
            colorIndex: draft.colorIndex >= 0 ? draft.colorIndex : nextIndex,
            customColorHex: draft.customColorHex,
            locationMode: draft.locationMode,
            latitude: draft.latitude,
            longitude: draft.longitude,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            locationPresetID: draft.locationPresetID
        )
        containers.append(container)
        notifyUpdated()
        return container
    }

    @discardableResult
    func addContainer(name: String) -> BrowserContainer? {
        let preset = SpoofLocationPreset.all[containers.count % SpoofLocationPreset.all.count]
        return addContainer(
            BrowserContainer(
                id: UUID(),
                name: name,
                sessionID: UUID(),
                sortIndex: 0,
                location: preset
            )
        )
    }

    @discardableResult
    func renameContainer(id: UUID, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = containers.firstIndex(where: { $0.id == id }) else { return false }
        if containers.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return false
        }
        containers[index].name = trimmed
        notifyUpdated()
        return true
    }

    /// Updates name and location settings. Rebuilds WebViews in that container when location changes.
    @discardableResult
    func updateContainer(_ updated: BrowserContainer) -> Bool {
        let trimmed = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = containers.firstIndex(where: { $0.id == updated.id }) else { return false }
        if containers.contains(where: { $0.id != updated.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return false
        }
        let previous = containers[index]
        let next = BrowserContainer(
            id: previous.id,
            name: trimmed,
            sessionID: previous.sessionID,
            sortIndex: previous.sortIndex,
            colorIndex: updated.colorIndex,
            customColorHex: updated.customColorHex,
            locationMode: updated.locationMode,
            latitude: updated.latitude,
            longitude: updated.longitude,
            timeZoneIdentifier: updated.timeZoneIdentifier,
            locationPresetID: updated.locationPresetID
        )
        containers[index] = next
        let locationChanged =
            previous.locationMode != next.locationMode
            || abs(previous.latitude - next.latitude) > 0.0000001
            || abs(previous.longitude - next.longitude) > 0.0000001
            || previous.timeZoneIdentifier != next.timeZoneIdentifier
        notifyUpdated()
        if locationChanged {
            invalidateWebViews(inContainer: previous.id)
        }
        return true
    }

    func invalidateWebViews(inContainer containerID: UUID) {
        var touched = false
        for tab in tabs where !tab.isIncognito && tab.containerID == containerID {
            tab.webController?.cleanup()
            tab.webController = nil
            touched = true
        }
        guard touched else { return }
        delegate?.tabManagerDidUpdate(self)
        if let selected = selectedTab {
            delegate?.tabManager(self, didSelect: selected)
        }
    }

    func reorderContainers(ids: [UUID]) {
        guard Set(ids) == Set(containers.map(\.id)), ids.count == containers.count else { return }
        var byID = Dictionary(uniqueKeysWithValues: containers.map { ($0.id, $0) })
        var reordered: [BrowserContainer] = []
        for (offset, id) in ids.enumerated() {
            guard var item = byID[id] else { continue }
            item.sortIndex = offset
            reordered.append(item)
        }
        containers = reordered
        notifyUpdated()
    }

    /// Moves tabs into the default container, then removes the container and its session store.
    @discardableResult
    func deleteContainer(id: UUID) -> Bool {
        guard containers.count > 1,
              let index = containers.firstIndex(where: { $0.id == id }) else { return false }
        let removed = containers[index]
        let fallback = containers.first(where: { $0.id != id }) ?? defaultContainer
        for tab in tabs where !tab.isIncognito && tab.containerID == id {
            let oldSession = sessionID(for: tab)
            tab.containerID = fallback.id
            if oldSession != fallback.sessionID {
                tab.webController?.cleanup()
                tab.webController = nil
                tab.clearSessionAvatar()
            }
        }
        containers.remove(at: index)
        reindexContainers()
        if lastActiveContainerID == id {
            lastActiveContainerID = fallback.id
        }
        TabSessionStore.removeIfOrphaned(sessionID: removed.sessionID, containers: containers)
        notifyUpdated()
        return true
    }

    func moveTab(_ id: UUID, toContainer containerID: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }),
              let destination = container(id: containerID),
              tab.containerID != containerID else { return }
        let oldSession = sessionID(for: tab)
        tab.containerID = destination.id
        if oldSession != destination.sessionID {
            tab.webController?.cleanup()
            tab.webController = nil
            tab.clearSessionAvatar()
        }
        if selectedTab?.id == id {
            noteActiveContainer(from: tab)
        }
        notifyUpdated()
    }

    /// Compatibility wrapper used by older call sites that still pass a container name.
    func moveTab(_ id: UUID, toGroup name: String) {
        if let match = containers.first(where: { $0.name == name }) {
            moveTab(id, toContainer: match.id)
            return
        }
        if let created = addContainer(name: name) {
            moveTab(id, toContainer: created.id)
        }
    }

    private func reindexContainers() {
        let sorted = sortedContainers
        containers = sorted.enumerated().map { offset, item in
            var copy = item
            copy.sortIndex = offset
            return copy
        }
    }

    func reorderTab(id: UUID, toDisplayIndex dest: Int, incognito: Bool) {
        let poolIndices = tabs.indices.filter { tabs[$0].isIncognito == incognito }
        guard let fromPool = poolIndices.firstIndex(where: { tabs[$0].id == id }),
              poolIndices.indices.contains(dest),
              fromPool != dest else { return }

        var pool = poolIndices.map { tabs[$0] }
        let item = pool.remove(at: fromPool)
        pool.insert(item, at: dest)

        let selectedID = selectedTab?.id
        var merged: [BrowserTab] = []
        merged.reserveCapacity(tabs.count)
        var poolCursor = 0
        for tab in tabs {
            if tab.isIncognito == incognito {
                merged.append(pool[poolCursor])
                poolCursor += 1
            } else {
                merged.append(tab)
            }
        }
        tabs = merged
        if let selectedID, let idx = tabs.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = idx
        }
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

    // MARK: - Persistence

    private func notifyUpdated() {
        persistContainers()
        delegate?.tabManagerDidUpdate(self)
        persistSessionIfNeeded()
    }

    private func noteActiveContainer(from tab: BrowserTab?) {
        guard let tab, !tab.isIncognito else { return }
        lastActiveContainerID = tab.containerID
        if let id = lastActiveContainerID {
            defaults.set(id.uuidString, forKey: lastContainerKey)
        }
    }

    private func loadPersistedContainers() {
        if let data = defaults.data(forKey: containersKey),
           let saved = try? JSONDecoder().decode([BrowserContainer].self, from: data),
           !saved.isEmpty {
            let deduped = Self.deduplicatedContainers(saved)
            let collapsedDuplicates = deduped.count != saved.count
            containers = deduped
            reindexContainers()
            migrateLegacyDefaultContainersIfNeeded()
            migrateAccountNamesV3IfNeeded()
            if collapsedDuplicates {
                persistContainers()
            }
        } else {
            containers = BrowserContainer.makeDefaults()
            persistContainers()
            defaults.set(true, forKey: containersPresetKey)
            defaults.set(true, forKey: containersPresetV3Key)
        }
        if let raw = defaults.string(forKey: lastContainerKey),
           let id = UUID(uuidString: raw),
           container(id: id) != nil {
            lastActiveContainerID = id
        } else {
            lastActiveContainerID = defaultContainer.id
            defaults.set(defaultContainer.id.uuidString, forKey: lastContainerKey)
        }
    }

    /// Rename factory Default/Work/Personal chips to FB-1/FB-2/Ins-1 and add Ins-2.
    private func migrateLegacyDefaultContainersIfNeeded() {
        let legacyNames: Set<String> = ["default", "work", "personal"]
        let currentNames = Set(containers.map { $0.name.lowercased() })
        guard currentNames == legacyNames else {
            if !defaults.bool(forKey: containersPresetKey) {
                defaults.set(true, forKey: containersPresetKey)
            }
            return
        }

        let rename: [String: String] = [
            "default": "FB-1",
            "work": "FB-2",
            "personal": "Ins-1"
        ]
        for i in containers.indices {
            let key = containers[i].name.lowercased()
            if let next = rename[key] {
                containers[i].name = next
            }
        }

        let desiredOrder = ["FB-1", "FB-2", "Ins-1", "Ins-2"]
        let existing = Set(containers.map(\.name))
        for (offset, name) in desiredOrder.enumerated() where !existing.contains(name) {
            let preset = SpoofLocationPreset.all[offset % SpoofLocationPreset.all.count]
            containers.append(
                BrowserContainer(
                    id: UUID(),
                    name: name,
                    sessionID: UUID(),
                    sortIndex: containers.count,
                    location: preset
                )
            )
        }

        var ordered: [BrowserContainer] = []
        for name in desiredOrder {
            if let match = containers.first(where: { $0.name == name }) {
                ordered.append(match)
            }
        }
        for container in containers where !desiredOrder.contains(container.name) {
            ordered.append(container)
        }
        containers = ordered
        reindexContainers()
        persistContainers()
        defaults.set(true, forKey: containersPresetKey)
    }

    private static let legacyAccountNames: Set<String> = [
        "Default", "default", "FB-1", "FB-2", "Ins-1", "Ins-2"
    ]

    private static let accountRenameV3: [String: String] = [
        "FB-1": "Social 1",
        "FB-2": "Social 2",
        "Ins-1": "Work",
        "Ins-2": "Personal"
    ]

    /// Collapse duplicate UUIDs (can appear after name-only session reconcile). Prefer non-legacy names.
    private static func deduplicatedContainers(_ items: [BrowserContainer]) -> [BrowserContainer] {
        var byID: [UUID: BrowserContainer] = [:]
        var order: [UUID] = []
        for item in items.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if let existing = byID[item.id] {
                let existingLegacy = legacyAccountNames.contains(existing.name)
                let incomingLegacy = legacyAccountNames.contains(item.name)
                if existingLegacy && !incomingLegacy {
                    byID[item.id] = item
                }
                continue
            }
            order.append(item.id)
            byID[item.id] = item
        }
        return order.enumerated().map { offset, id in
            var copy = byID[id]!
            copy.sortIndex = offset
            return copy
        }
    }

    /// Rename factory FB-1/Ins-* chips to Personal/Work/Social; assign colorIndex if missing.
    private func migrateAccountNamesV3IfNeeded() {
        defer {
            // Ensure every container has a stable colorIndex after load.
            for i in containers.indices where containers[i].colorIndex < 0 {
                containers[i].colorIndex = containers[i].sortIndex
            }
        }
        var changed = false
        // Apply leftover legacy renames even after the v3 flag is set (session can reintroduce FB-1).
        for i in containers.indices {
            if let next = Self.accountRenameV3[containers[i].name] {
                let taken = containers.contains {
                    $0.id != containers[i].id && $0.name.caseInsensitiveCompare(next) == .orderedSame
                }
                if !taken {
                    containers[i].name = next
                    changed = true
                }
            }
        }
        if !defaults.bool(forKey: containersPresetV3Key) {
            for i in containers.indices {
                if containers[i].colorIndex == containers[i].sortIndex || containers[i].colorIndex == 0 {
                    let preferred: [String: Int] = [
                        "Personal": 0, "Work": 1, "Social 1": 2, "Social 2": 3
                    ]
                    if let idx = preferred[containers[i].name] {
                        containers[i].colorIndex = idx
                        changed = true
                    }
                }
            }
            defaults.set(true, forKey: containersPresetV3Key)
        }
        if changed {
            reindexContainers()
            persistContainers()
        }
    }

    private func persistContainers() {
        let payload = sortedContainers
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: containersKey)
        }
        if let id = lastActiveContainerID ?? Optional(defaultContainer.id) {
            defaults.set(id.uuidString, forKey: lastContainerKey)
        }
    }

    func persistSessionIfNeeded() {
        persistContainers()
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
                    containerID: $0.containerID,
                    title: $0.title,
                    urlString: $0.url?.absoluteString,
                    isNewTabPage: $0.isNewTabPage,
                    lastAccessed: $0.lastAccessed,
                    preferDesktop: $0.preferDesktop,
                    historyURLs: $0.navigationHistory.urls,
                    historyIndex: $0.navigationHistory.index,
                    groupName: containerName(for: $0)
                )
            },
            selectedIndex: index,
            containers: sortedContainers
        )
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: sessionKey)
        }
        // Flush promptly so a sudden termination still has the latest tab/container map.
        defaults.synchronize()
        var keep = Set<UUID>()
        for tab in normal {
            keep.insert(tab.id)
            if let snapshot = tab.snapshot, AppSettings.showTabsPreviewImages {
                TabSnapshotStore.save(snapshot, for: tab.id)
            }
        }
        TabSnapshotStore.removeAll(except: keep)
    }

    /// Intentional leave with "Close All Tabs on Exit" — next launch starts fresh.
    func markCleanExitAndClearSession() {
        defaults.set(true, forKey: cleanExitKey)
        clearPersistedSession()
        defaults.synchronize()
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

        // Session-embedded containers are authoritative for tab.containerID matching.
        // Separately persisted containers may have been regenerated with new UUIDs.
        if !session.containers.isEmpty {
            containers = reconcileContainers(
                primary: session.containers,
                secondary: containers
            )
        } else if containers.isEmpty {
            containers = Self.migrateContainers(from: session)
        }
        containers = Self.deduplicatedContainers(containers)
        reindexContainers()
        migrateLegacyDefaultContainersIfNeeded()
        // Session may still carry pre-v3 names (FB-1); containers disk already migrated.
        migrateAccountNamesV3IfNeeded()
        persistContainers()

        let fallbackID = resolvedLastActiveContainerID
        tabs = session.tabs.map {
            let url = $0.urlString.flatMap(URL.init(string:))
            let containerID = $0.resolvedContainerID(
                containers: containers,
                sessionContainers: session.containers,
                fallback: fallbackID
            )
            let tab = BrowserTab(
                id: $0.id,
                containerID: containerID,
                title: $0.title,
                url: url,
                isNewTabPage: url == nil,
                lastAccessed: $0.lastAccessed,
                preferDesktop: $0.preferDesktop,
                historyURLs: $0.historyURLs,
                historyIndex: $0.historyIndex
            )
            if AppSettings.showTabsPreviewImages {
                tab.snapshot = TabSnapshotStore.load(for: $0.id)
            }
            return tab
        }

        // Restore the previously selected tab when possible; otherwise prefer last active container.
        let selectedID = session.tabs.indices.contains(session.selectedIndex)
            ? session.tabs[session.selectedIndex].id
            : nil
        if let selectedID, let selectedIdx = tabs.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = selectedIdx
        } else if let lastID = lastActiveContainerID,
                  let preferred = tabs.firstIndex(where: { !$0.isIncognito && $0.containerID == lastID }) {
            selectedIndex = preferred
        } else {
            selectedIndex = min(max(0, session.selectedIndex), tabs.count - 1)
        }
        return true
    }

    /// Keep primary (session) IDs/sessionIDs so saved tabs still resolve; append extras by id+name.
    /// Same UUID under a renamed label (FB-1 → Social 1) must not be appended as a second row.
    private func reconcileContainers(primary: [BrowserContainer], secondary: [BrowserContainer]) -> [BrowserContainer] {
        var byID: [UUID: BrowserContainer] = [:]
        var order: [UUID] = []
        for item in primary.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            guard byID[item.id] == nil else { continue }
            order.append(item.id)
            byID[item.id] = item
        }
        var knownNames = Set(byID.values.map { $0.name.lowercased() })
        for extra in secondary.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if var existing = byID[extra.id] {
                // Same account: keep session identity, adopt migrated display name/color from disk.
                if Self.legacyAccountNames.contains(existing.name),
                   !Self.legacyAccountNames.contains(extra.name) {
                    knownNames.remove(existing.name.lowercased())
                    existing.name = extra.name
                    existing.colorIndex = extra.colorIndex
                    existing.customColorHex = extra.customColorHex
                    byID[extra.id] = existing
                    knownNames.insert(extra.name.lowercased())
                }
                continue
            }
            if knownNames.contains(extra.name.lowercased()) { continue }
            byID[extra.id] = extra
            order.append(extra.id)
            knownNames.insert(extra.name.lowercased())
        }
        return order.enumerated().map { offset, id in
            var copy = byID[id]!
            copy.sortIndex = offset
            return copy
        }
    }

    /// Tab count shown on the toolbar badge for the current browsing context.
    func toolbarTabCount(incognito: Bool) -> Int {
        if incognito {
            return max(incognitoTabs.count, 1)
        }
        let containerID = selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? resolvedLastActiveContainerID
        return max(normalTabs.filter { $0.containerID == containerID }.count, 1)
    }

    private static func migrateContainers(from session: PersistedSession) -> [BrowserContainer] {
        var names = session.legacyGroupNames
        if names.isEmpty { names = ["FB-1", "FB-2", "Ins-1", "Ins-2"] }
        if !names.contains(where: { $0.caseInsensitiveCompare("FB-1") == .orderedSame }) {
            names.insert("FB-1", at: 0)
        }
        return names.enumerated().map { offset, name in
            let preset = SpoofLocationPreset.all[offset % SpoofLocationPreset.all.count]
            return BrowserContainer(
                id: UUID(),
                name: name,
                sessionID: UUID(),
                sortIndex: offset,
                location: preset
            )
        }
    }
}

private struct PersistedSession: Codable {
    var tabs: [PersistedTab]
    var selectedIndex: Int
    var containers: [BrowserContainer]
    /// Legacy field from string-based groups.
    var groupNames: [String]?

    var legacyGroupNames: [String] { groupNames ?? [] }

    enum CodingKeys: String, CodingKey {
        case tabs, selectedIndex, containers, groupNames
    }

    init(tabs: [PersistedTab], selectedIndex: Int, containers: [BrowserContainer]) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
        self.containers = containers
        self.groupNames = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try c.decode([PersistedTab].self, forKey: .tabs)
        selectedIndex = try c.decode(Int.self, forKey: .selectedIndex)
        containers = try c.decodeIfPresent([BrowserContainer].self, forKey: .containers) ?? []
        groupNames = try c.decodeIfPresent([String].self, forKey: .groupNames)
    }
}

private struct PersistedTab: Codable {
    let id: UUID
    var containerID: UUID?
    var title: String
    var urlString: String?
    var isNewTabPage: Bool
    var lastAccessed: Date
    var preferDesktop: Bool
    var historyURLs: [String]
    var historyIndex: Int
    /// Legacy fields.
    var sessionID: UUID?
    var groupName: String?

    enum CodingKeys: String, CodingKey {
        case id, containerID, title, urlString, isNewTabPage, lastAccessed, preferDesktop
        case historyURLs, historyIndex, sessionID, groupName
    }

    init(
        id: UUID,
        containerID: UUID,
        title: String,
        urlString: String?,
        isNewTabPage: Bool,
        lastAccessed: Date,
        preferDesktop: Bool,
        historyURLs: [String] = [],
        historyIndex: Int = -1,
        groupName: String? = nil
    ) {
        self.id = id
        self.containerID = containerID
        self.title = title
        self.urlString = urlString
        self.isNewTabPage = isNewTabPage
        self.lastAccessed = lastAccessed
        self.preferDesktop = preferDesktop
        self.historyURLs = historyURLs
        self.historyIndex = historyIndex
        self.sessionID = nil
        self.groupName = groupName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        containerID = try c.decodeIfPresent(UUID.self, forKey: .containerID)
        title = try c.decode(String.self, forKey: .title)
        urlString = try c.decodeIfPresent(String.self, forKey: .urlString)
        isNewTabPage = try c.decode(Bool.self, forKey: .isNewTabPage)
        lastAccessed = try c.decode(Date.self, forKey: .lastAccessed)
        preferDesktop = try c.decodeIfPresent(Bool.self, forKey: .preferDesktop) ?? false
        historyURLs = try c.decodeIfPresent([String].self, forKey: .historyURLs) ?? []
        historyIndex = try c.decodeIfPresent(Int.self, forKey: .historyIndex) ?? -1
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName)
    }

    func resolvedContainerID(
        containers: [BrowserContainer],
        sessionContainers: [BrowserContainer] = [],
        fallback: UUID
    ) -> UUID {
        if let containerID, containers.contains(where: { $0.id == containerID }) {
            return containerID
        }
        // Map via the name of the container that originally owned this ID in the saved session.
        if let containerID,
           let named = sessionContainers.first(where: { $0.id == containerID }),
           let match = containers.first(where: { $0.name.caseInsensitiveCompare(named.name) == .orderedSame }) {
            return match.id
        }
        if let groupName,
           let match = containers.first(where: { $0.name.caseInsensitiveCompare(groupName) == .orderedSame }) {
            return match.id
        }
        return fallback
    }
}
