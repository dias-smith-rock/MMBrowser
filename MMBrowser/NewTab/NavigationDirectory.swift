import Foundation

struct NavigationSite: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String
    /// Asset catalog name when known (preset logos); nil for user-added sites.
    var logoAssetName: String?

    var url: URL? { URL(string: urlString) }

    init(id: UUID = UUID(), title: String, urlString: String, logoAssetName: String? = nil) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.logoAssetName = logoAssetName
    }
}

struct NavigationCategory: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var sites: [NavigationSite]
    var isHome: Bool

    init(id: UUID = UUID(), title: String, sites: [NavigationSite], isHome: Bool = false) {
        self.id = id
        self.title = title
        self.sites = sites
        self.isHome = isHome
    }
}

/// Built-in seed catalog (also used by “Restore Defaults”).
enum NavigationDirectory {
    static let defaultCategories: [NavigationCategory] = [
        NavigationCategory(
            title: "AI & Tech",
            sites: [
                NavigationSite(title: "ChatGPT", urlString: "https://chatgpt.com", logoAssetName: "nav_chatgpt"),
                NavigationSite(title: "Claude", urlString: "https://claude.ai", logoAssetName: "nav_claude"),
                NavigationSite(title: "Gemini", urlString: "https://gemini.google.com", logoAssetName: "nav_gemini"),
                NavigationSite(title: "GitHub", urlString: "https://github.com", logoAssetName: "nav_github")
            ]
        ),
        NavigationCategory(
            title: "Social Media",
            sites: [
                NavigationSite(title: "Facebook", urlString: "https://www.facebook.com", logoAssetName: "nav_facebook"),
                NavigationSite(title: "Instagram", urlString: "https://www.instagram.com", logoAssetName: "nav_instagram"),
                NavigationSite(title: "X", urlString: "https://x.com", logoAssetName: "nav_x"),
                NavigationSite(title: "LinkedIn", urlString: "https://www.linkedin.com", logoAssetName: "nav_linkedin")
            ]
        ),
        NavigationCategory(
            title: "News",
            sites: [
                NavigationSite(title: "BBC", urlString: "https://www.bbc.com", logoAssetName: "nav_bbc"),
                NavigationSite(title: "CNN", urlString: "https://www.cnn.com", logoAssetName: "nav_cnn"),
                NavigationSite(title: "Reuters", urlString: "https://www.reuters.com", logoAssetName: "nav_reuters"),
                NavigationSite(title: "The Guardian", urlString: "https://www.theguardian.com", logoAssetName: "nav_guardian")
            ]
        ),
        NavigationCategory(
            title: "Music",
            sites: [
                NavigationSite(title: "Spotify", urlString: "https://open.spotify.com", logoAssetName: "nav_spotify"),
                NavigationSite(title: "YouTube Music", urlString: "https://music.youtube.com", logoAssetName: "nav_youtubemusic"),
                NavigationSite(title: "YouTube", urlString: "https://www.youtube.com", logoAssetName: "nav_youtube"),
                NavigationSite(title: "SoundCloud", urlString: "https://soundcloud.com", logoAssetName: "nav_soundcloud")
            ]
        ),
        NavigationCategory(
            title: "Gossip",
            sites: [
                NavigationSite(title: "TMZ", urlString: "https://www.tmz.com", logoAssetName: "nav_tmz"),
                NavigationSite(title: "People", urlString: "https://people.com", logoAssetName: "nav_people"),
                NavigationSite(title: "BuzzFeed", urlString: "https://www.buzzfeed.com", logoAssetName: "nav_buzzfeed"),
                NavigationSite(title: "Daily Mail", urlString: "https://www.dailymail.co.uk", logoAssetName: "nav_dailymail")
            ]
        )
    ]

    /// Former 5th-slot presets removed in favor of a permanent "+" edit entry.
    static let retiredFifthSiteURLKeys: Set<String> = [
        "https://huggingface.co",
        "https://www.reddit.com",
        "https://reddit.com",
        "https://techcrunch.com",
        "https://bandcamp.com",
        "https://www.eonline.com",
        "https://eonline.com"
    ]

    static func makeSeedCategories(includingHome homeSites: [NavigationSite] = []) -> [NavigationCategory] {
        var result: [NavigationCategory] = [
            NavigationCategory(title: "Home", sites: homeSites, isHome: true)
        ]
        result.append(contentsOf: defaultCategories.map {
            NavigationCategory(
                id: UUID(),
                title: $0.title,
                sites: $0.sites.map {
                    NavigationSite(
                        id: UUID(),
                        title: $0.title,
                        urlString: $0.urlString,
                        logoAssetName: $0.logoAssetName
                    )
                },
                isHome: false
            )
        })
        return result
    }
}

/// Persisted editable homepage navigation (categories + sites), scoped per account container.
final class NavigationStore {
    static let shared = NavigationStore()

    private let key = "mmbrowser.navigation.byContainer.v1"
    private let migratedKey = "mmbrowser.navigation.migratedShortcuts.v1"
    private let retiredFifthKey = "mmbrowser.navigation.retiredFifth.v1"
    private let defaults = UserDefaults.standard
    private var byContainer: [UUID: [NavigationCategory]] = [:]

    private struct Payload: Codable {
        var containers: [Entry]
    }

    private struct Entry: Codable {
        var containerID: UUID
        var categories: [NavigationCategory]
    }

    private init() {
        load()
    }

    func categories(for containerID: UUID) -> [NavigationCategory] {
        let resolved = ContainerScope.resolveContainerID(containerID)
        ensureLoaded(containerID: resolved)
        return byContainer[resolved] ?? NavigationDirectory.makeSeedCategories()
    }

    func remove(containerID: UUID) {
        byContainer.removeValue(forKey: containerID)
        saveAll()
    }

    private func ensureLoaded(containerID: UUID) {
        if byContainer[containerID] != nil { return }
        var cats = NavigationDirectory.makeSeedCategories()
        migrateShortcutsIntoHomeIfNeeded(categories: &cats)
        removeRetiredFifthSitesIfNeeded(categories: &cats)
        byContainer[containerID] = cats
        saveAll()
    }

    private func mutate(containerID: UUID, _ block: (inout [NavigationCategory]) -> Void) {
        let resolved = ContainerScope.resolveContainerID(containerID)
        ensureLoaded(containerID: resolved)
        var cats = byContainer[resolved] ?? NavigationDirectory.makeSeedCategories()
        block(&cats)
        byContainer[resolved] = cats
        persistAndNotify()
    }

    func homeCategoryIndex(for containerID: UUID) -> Int? {
        categories(for: containerID).firstIndex(where: \.isHome)
    }

    func containsOnHome(url: URL, containerID: UUID) -> Bool {
        guard let home = categories(for: containerID).first(where: \.isHome) else { return false }
        let key = normalizeURLKey(url.absoluteString)
        return home.sites.contains { normalizeURLKey($0.urlString) == key }
    }

    @discardableResult
    func addToHome(title: String, url: URL, containerID: UUID, logoAssetName: String? = nil) -> Bool {
        var added = false
        mutate(containerID: containerID) { categories in
            ensureHomeCategory(in: &categories)
            guard let idx = categories.firstIndex(where: \.isHome) else { return }
            let key = normalizeURLKey(url.absoluteString)
            if categories[idx].sites.contains(where: { normalizeURLKey($0.urlString) == key }) { return }
            categories[idx].sites.append(
                NavigationSite(title: title, urlString: url.absoluteString, logoAssetName: logoAssetName)
            )
            added = true
        }
        return added
    }

    @discardableResult
    func addGroupToHome(categoryID: UUID, containerID: UUID) -> Int {
        var added = 0
        mutate(containerID: containerID) { categories in
            guard let source = categories.first(where: { $0.id == categoryID }), !source.isHome else { return }
            ensureHomeCategory(in: &categories)
            guard let homeIdx = categories.firstIndex(where: \.isHome) else { return }
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
        }
        return added
    }

    func addSite(toCategoryID categoryID: UUID, containerID: UUID, title: String, urlString: String) {
        mutate(containerID: containerID) { categories in
            guard let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
            categories[idx].sites.append(NavigationSite(title: title, urlString: urlString))
        }
    }

    func removeSite(categoryID: UUID, siteID: UUID, containerID: UUID) {
        mutate(containerID: containerID) { categories in
            guard let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
            categories[idx].sites.removeAll { $0.id == siteID }
        }
    }

    func moveSite(categoryID: UUID, containerID: UUID, from: Int, to: Int, notify: Bool = true) {
        let resolved = ContainerScope.resolveContainerID(containerID)
        ensureLoaded(containerID: resolved)
        guard var categories = byContainer[resolved],
              let idx = categories.firstIndex(where: { $0.id == categoryID }) else { return }
        var sites = categories[idx].sites
        guard from >= 0, from < sites.count, to >= 0, to < sites.count, from != to else { return }
        let item = sites.remove(at: from)
        sites.insert(item, at: to)
        categories[idx].sites = sites
        byContainer[resolved] = categories
        if notify {
            persistAndNotify()
        } else {
            saveAll()
        }
    }

    func moveCategory(containerID: UUID, from: Int, to: Int) {
        mutate(containerID: containerID) { categories in
            guard from >= 0, from < categories.count, to >= 0, to < categories.count, from != to else { return }
            guard !categories[from].isHome else { return }
            var target = to
            if target < 1 { target = 1 }
            let item = categories.remove(at: from)
            if target > categories.count { target = categories.count }
            categories.insert(item, at: target)
            ensureHomeCategory(in: &categories)
        }
    }

    func deleteCategory(id: UUID, containerID: UUID) {
        mutate(containerID: containerID) { categories in
            guard let cat = categories.first(where: { $0.id == id }), !cat.isHome else { return }
            categories.removeAll { $0.id == id }
        }
    }

    func restoreDefaults(containerID: UUID) {
        mutate(containerID: containerID) { categories in
            let homeSites = categories.first(where: \.isHome)?.sites ?? []
            categories = NavigationDirectory.makeSeedCategories(includingHome: homeSites)
        }
    }

    private func ensureHomeCategory(in categories: inout [NavigationCategory]) {
        if let idx = categories.firstIndex(where: \.isHome), idx != 0 {
            let home = categories.remove(at: idx)
            categories.insert(home, at: 0)
        } else if !categories.contains(where: \.isHome) {
            categories.insert(NavigationCategory(title: "Home", sites: [], isHome: true), at: 0)
        }
    }

    private func migrateShortcutsIntoHomeIfNeeded(categories: inout [NavigationCategory]) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        ensureHomeCategory(in: &categories)
        guard let homeIdx = categories.firstIndex(where: \.isHome) else { return }
        var existing = Set(categories[homeIdx].sites.map { normalizeURLKey($0.urlString) })
        for item in ShortcutStore.shared.items {
            let key = normalizeURLKey(item.urlString)
            guard !existing.contains(key) else { continue }
            categories[homeIdx].sites.append(
                NavigationSite(title: item.title, urlString: item.urlString)
            )
            existing.insert(key)
        }
    }

    private func removeRetiredFifthSitesIfNeeded(categories: inout [NavigationCategory]) {
        guard !defaults.bool(forKey: retiredFifthKey) else { return }
        defaults.set(true, forKey: retiredFifthKey)
        let retired = Set(NavigationDirectory.retiredFifthSiteURLKeys.map { normalizeURLKey($0) })
        for i in categories.indices {
            categories[i].sites.removeAll { retired.contains(normalizeURLKey($0.urlString)) }
        }
    }

    private func normalizeURLKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persistAndNotify() {
        saveAll()
        NotificationCenter.default.post(name: .navigationDirectoryChanged, object: nil)
        NotificationCenter.default.post(name: .homeSettingsChanged, object: nil)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        for entry in payload.containers {
            byContainer[entry.containerID] = entry.categories
        }
    }

    private func saveAll() {
        let payload = Payload(containers: byContainer.map { Entry(containerID: $0.key, categories: $0.value) })
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: key)
        }
    }
}
