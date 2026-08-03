import Foundation

/// Persisted editable homepage navigation (categories + sites).
final class NavigationStore {
    static let shared = NavigationStore()

    private let key = "mmbrowser.navigation.categories.v1"
    private let migratedKey = "mmbrowser.navigation.migratedShortcuts.v1"
    private let defaults = UserDefaults.standard
    private(set) var categories: [NavigationCategory] = []

    private init() {
        load()
        if categories.isEmpty {
            categories = NavigationDirectory.makeSeedCategories()
            migrateShortcutsIntoHomeIfNeeded()
            save()
        } else {
            ensureHomeCategory()
            migrateShortcutsIntoHomeIfNeeded()
        }
    }

    var homeCategoryIndex: Int? {
        categories.firstIndex(where: \.isHome)
    }

    func containsOnHome(url: URL) -> Bool {
        guard let home = categories.first(where: \.isHome) else { return false }
        let key = normalizeURLKey(url.absoluteString)
        return home.sites.contains { normalizeURLKey($0.urlString) == key }
    }

    @discardableResult
    func addToHome(title: String, url: URL, logoAssetName: String? = nil) -> Bool {
        ensureHomeCategory()
        guard let idx = homeCategoryIndex else { return false }
        let key = normalizeURLKey(url.absoluteString)
        if categories[idx].sites.contains(where: { normalizeURLKey($0.urlString) == key }) {
            return false
        }
        categories[idx].sites.append(
            NavigationSite(title: title, urlString: url.absoluteString, logoAssetName: logoAssetName)
        )
        persistAndNotify()
        return true
    }

    /// Merge all sites from a category into Home (deduped by URL).
    @discardableResult
    func addGroupToHome(categoryID: UUID) -> Int {
        guard let source = categories.first(where: { $0.id == categoryID }), !source.isHome else { return 0 }
        ensureHomeCategory()
        guard let homeIdx = homeCategoryIndex else { return 0 }
        var added = 0
        var existing = Set(categories[homeIdx].sites.map { normalizeURLKey($0.urlString) })
        for site in source.sites {
            let key = normalizeURLKey(site.urlString)
            guard !existing.contains(key) else { continue }
            categories[homeIdx].sites.append(
                NavigationSite(title: site.title, urlString: site.urlString, logoAssetName: site.logoAssetName)
            )
            existing.insert(key)
            added += 1
        }
        if added > 0 { persistAndNotify() }
        return added
    }

    func addSite(toCategoryID categoryID: UUID, title: String, urlString: String) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[idx].sites.append(NavigationSite(title: title, urlString: urlString))
        persistAndNotify()
    }

    func removeSite(categoryID: UUID, siteID: UUID) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        categories[idx].sites.removeAll { $0.id == siteID }
        persistAndNotify()
    }

    func moveSite(categoryID: UUID, from: Int, to: Int) {
        guard let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        var sites = categories[idx].sites
        guard from >= 0, from < sites.count, to >= 0, to < sites.count, from != to else { return }
        let item = sites.remove(at: from)
        sites.insert(item, at: to)
        categories[idx].sites = sites
        persistAndNotify()
    }

    func moveCategory(from: Int, to: Int) {
        guard from >= 0, from < categories.count, to >= 0, to < categories.count, from != to else { return }
        // Home stays pinned at index 0.
        guard !categories[from].isHome else { return }
        var target = to
        if target < 1 { target = 1 }
        let item = categories.remove(at: from)
        if target > categories.count { target = categories.count }
        categories.insert(item, at: target)
        ensureHomeCategory()
        persistAndNotify()
    }

    func deleteCategory(id: UUID) {
        guard let cat = categories.first(where: { $0.id == id }), !cat.isHome else { return }
        categories.removeAll { $0.id == id }
        persistAndNotify()
    }

    func restoreDefaults() {
        let homeSites = categories.first(where: \.isHome)?.sites ?? []
        categories = NavigationDirectory.makeSeedCategories(includingHome: homeSites)
        persistAndNotify()
    }

    private func ensureHomeCategory() {
        if let idx = homeCategoryIndex, idx != 0 {
            let home = categories.remove(at: idx)
            categories.insert(home, at: 0)
            save()
        } else if homeCategoryIndex == nil {
            categories.insert(NavigationCategory(title: "Home", sites: [], isHome: true), at: 0)
            save()
        }
    }

    private func migrateShortcutsIntoHomeIfNeeded() {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        ensureHomeCategory()
        guard let homeIdx = homeCategoryIndex else { return }
        var existing = Set(categories[homeIdx].sites.map { normalizeURLKey($0.urlString) })
        var changed = false
        for item in ShortcutStore.shared.items {
            let key = normalizeURLKey(item.urlString)
            guard !existing.contains(key) else { continue }
            categories[homeIdx].sites.append(
                NavigationSite(title: item.title, urlString: item.urlString)
            )
            existing.insert(key)
            changed = true
        }
        if changed { save() }
    }

    private func normalizeURLKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persistAndNotify() {
        save()
        NotificationCenter.default.post(name: .navigationDirectoryChanged, object: nil)
        NotificationCenter.default.post(name: .homeSettingsChanged, object: nil)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([NavigationCategory].self, from: data) else { return }
        categories = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(categories) {
            defaults.set(data, forKey: key)
        }
    }
}
