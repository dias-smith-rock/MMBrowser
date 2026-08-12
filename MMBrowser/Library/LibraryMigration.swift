import Foundation

/// One-time library/container shape migrations. No legacy "Imported" account — app was never shipped with global library data.
enum LibraryMigration {
    private static let defaults = UserDefaults.standard

    /// Former migration bucket UUID; stripped from existing installs/dev devices.
    private static let removedLegacyImportedID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    /// Call after containers are loaded in TabManager.
    static func runIfNeeded(containers: inout [BrowserContainer]) {
        removeLegacyImportedContainer(in: &containers)
        migrateLibraryV4(defaultContainerID: containers.first?.id)
        migrateContainersV5(containers: &containers)
    }

    private static func removeLegacyImportedContainer(in containers: inout [BrowserContainer]) {
        let before = containers.count
        containers.removeAll { $0.id == removedLegacyImportedID }
        guard containers.count != before else { return }
        purgeLibraryData(for: removedLegacyImportedID)
        if let data = try? JSONEncoder().encode(containers.sorted { $0.sortIndex < $1.sortIndex }) {
            defaults.set(data, forKey: "mmbrowser.containers")
        }
        defaults.removeObject(forKey: "mmbrowser.containers.legacyEnsured.v1")
    }

    private static func purgeLibraryData(for containerID: UUID) {
        func filterHistory() {
            let key = "mmbrowser.history.items.v2"
            guard let data = defaults.data(forKey: key),
                  var items = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
            items.removeAll { $0.containerID == containerID }
            if let encoded = try? JSONEncoder().encode(items) {
                defaults.set(encoded, forKey: key)
            }
        }
        func filterBookmarks() {
            let key = "mmbrowser.bookmarks.items.v2"
            guard let data = defaults.data(forKey: key),
                  var items = try? JSONDecoder().decode([BookmarkItem].self, from: data) else { return }
            items.removeAll { $0.containerID == containerID }
            if let encoded = try? JSONEncoder().encode(items) {
                defaults.set(encoded, forKey: key)
            }
        }
        func filterNavigation() {
            let key = "mmbrowser.navigation.byContainer.v1"
            guard let data = defaults.data(forKey: key),
                  var payload = try? JSONDecoder().decode(ContainerNavigationPayload.self, from: data) else { return }
            payload.containers.removeAll { $0.containerID == containerID }
            if let encoded = try? JSONEncoder().encode(payload) {
                defaults.set(encoded, forKey: key)
            }
        }
        filterHistory()
        filterBookmarks()
        filterNavigation()
    }

    private static func migrateLibraryV4(defaultContainerID: UUID?) {
        guard !defaults.bool(forKey: ContainerScope.libraryMigratedV4Key) else { return }
        guard let defaultID = defaultContainerID else {
            defaults.set(true, forKey: ContainerScope.libraryMigratedV4Key)
            return
        }

        migrateHistory(to: defaultID, oldKey: "mmbrowser.history.items", newKey: "mmbrowser.history.items.v2")
        migrateBookmarks(to: defaultID, defaultContainerID: defaultID, oldKey: "mmbrowser.bookmarks.items", newKey: "mmbrowser.bookmarks.items.v2")
        migrateNavigation(defaultContainerID: defaultID, oldKey: "mmbrowser.navigation.categories.v1", newKey: "mmbrowser.navigation.byContainer.v1")

        defaults.set(true, forKey: ContainerScope.libraryMigratedV4Key)
    }

    private struct LegacyHistoryItem: Codable {
        let id: UUID
        var title: String
        var urlString: String
        var date: Date
    }

    private struct LegacyBookmarkItem: Codable {
        let id: UUID
        var title: String
        var urlString: String
    }

    private static func migrateHistory(to containerID: UUID, oldKey: String, newKey: String) {
        guard let data = defaults.data(forKey: oldKey),
              let old = try? JSONDecoder().decode([LegacyHistoryItem].self, from: data) else {
            defaults.set(Data(), forKey: newKey)
            return
        }
        defaults.set(data, forKey: oldKey + ".backup")
        let migrated = old.map {
            HistoryItem(id: $0.id, containerID: containerID, title: $0.title, urlString: $0.urlString, date: $0.date)
        }
        if let encoded = try? JSONEncoder().encode(migrated) {
            defaults.set(encoded, forKey: newKey)
        }
    }

    private static func migrateBookmarks(to containerID: UUID, defaultContainerID: UUID, oldKey: String, newKey: String) {
        guard let data = defaults.data(forKey: oldKey),
              let old = try? JSONDecoder().decode([LegacyBookmarkItem].self, from: data) else {
            seedDefaultBookmarks(for: defaultContainerID, key: newKey)
            return
        }
        defaults.set(data, forKey: oldKey + ".backup")
        let migrated = old.map {
            BookmarkItem(id: $0.id, containerID: containerID, title: $0.title, urlString: $0.urlString)
        }
        if let encoded = try? JSONEncoder().encode(migrated) {
            defaults.set(encoded, forKey: newKey)
        }
    }

    private static func seedDefaultBookmarks(for containerID: UUID, key: String) {
        let seeds = [
            BookmarkItem(id: UUID(), containerID: containerID, title: "Google", urlString: "https://www.google.com"),
            BookmarkItem(id: UUID(), containerID: containerID, title: "YouTube", urlString: "https://www.youtube.com")
        ]
        if let encoded = try? JSONEncoder().encode(seeds) {
            defaults.set(encoded, forKey: key)
        }
    }

    private struct ContainerNavigationPayload: Codable {
        var containers: [ContainerNavigationEntry]
    }

    private struct ContainerNavigationEntry: Codable {
        var containerID: UUID
        var categories: [NavigationCategory]
    }

    private static func migrateNavigation(defaultContainerID: UUID, oldKey: String, newKey: String) {
        var entries: [ContainerNavigationEntry] = []
        if let data = defaults.data(forKey: oldKey),
           let old = try? JSONDecoder().decode([NavigationCategory].self, from: data) {
            defaults.set(data, forKey: oldKey + ".backup")
            entries.append(ContainerNavigationEntry(containerID: defaultContainerID, categories: old))
        } else {
            entries.append(ContainerNavigationEntry(
                containerID: defaultContainerID,
                categories: NavigationDirectory.makeSeedCategories()
            ))
        }
        let payload = ContainerNavigationPayload(containers: entries)
        if let encoded = try? JSONEncoder().encode(payload) {
            defaults.set(encoded, forKey: newKey)
        }
    }

    private static func migrateContainersV5(containers: inout [BrowserContainer]) {
        guard !defaults.bool(forKey: ContainerScope.containersMigratedV5Key) else { return }
        var changed = false
        for i in containers.indices {
            if containers[i].pinnedSites.isEmpty {
                containers[i].pinnedSites = ContainerTemplate.defaultPinned(forName: containers[i].name)
                changed = true
            }
            if containers[i].identity == .default,
               containers[i].locationMode == .spoof,
               let presetID = containers[i].locationPresetID,
               let preset = SpoofLocationPreset.all.first(where: { $0.id == presetID }) {
                containers[i].identity.localeIdentifier = IdentityProfile.suggestedLocale(for: preset)
                changed = true
            }
        }
        defaults.set(true, forKey: ContainerScope.containersMigratedV5Key)
        if changed, let data = try? JSONEncoder().encode(containers.sorted { $0.sortIndex < $1.sortIndex }) {
            defaults.set(data, forKey: "mmbrowser.containers")
        }
    }
}
