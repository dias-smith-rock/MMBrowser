import Foundation

struct BookmarkItem: Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String

    var url: URL? { URL(string: urlString) }
}

enum BookmarkSort: String, CaseIterable {
    case manual
    case titleAsc
    case titleDesc
    case hostAsc

    var displayName: String {
        switch self {
        case .manual: return "Manual Order"
        case .titleAsc: return "Title A–Z"
        case .titleDesc: return "Title Z–A"
        case .hostAsc: return "Site A–Z"
        }
    }
}

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let key = "mmbrowser.bookmarks.items"
    private let sortKey = "mmbrowser.bookmarks.sort"
    private let defaults = UserDefaults.standard
    private(set) var items: [BookmarkItem] = []
    private(set) var sort: BookmarkSort = .manual

    private init() {
        if let raw = defaults.string(forKey: sortKey),
           let value = BookmarkSort(rawValue: raw) {
            sort = value
        }
        load()
        if items.isEmpty {
            items = [
                BookmarkItem(id: UUID(), title: "Google", urlString: "https://www.google.com"),
                BookmarkItem(id: UUID(), title: "YouTube", urlString: "https://www.youtube.com")
            ]
            save()
        }
        applySort(persist: false)
    }

    /// Returns `true` when a new bookmark was stored; `false` if this URL was already bookmarked.
    @discardableResult
    func add(title: String, url: URL) -> Bool {
        let key = Self.canonicalKey(for: url)
        if items.contains(where: { Self.canonicalKey(forURLString: $0.urlString) == key }) {
            return false
        }
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items.insert(
            BookmarkItem(
                id: UUID(),
                title: displayTitle.isEmpty ? (url.host ?? "Bookmark") : displayTitle,
                urlString: url.absoluteString
            ),
            at: 0
        )
        if sort != .manual {
            applySort(persist: false)
        }
        save()
        return true
    }

    func contains(url: URL) -> Bool {
        let key = Self.canonicalKey(for: url)
        return items.contains { Self.canonicalKey(forURLString: $0.urlString) == key }
    }

    /// Updates title/URL. Returns `false` when the new URL clashes with another bookmark.
    @discardableResult
    func update(id: UUID, title: String, urlString: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL), url.scheme != nil else {
            return false
        }
        let key = Self.canonicalKey(for: url)
        if items.contains(where: { $0.id != id && Self.canonicalKey(forURLString: $0.urlString) == key }) {
            return false
        }
        items[index].title = trimmedTitle.isEmpty ? (url.host ?? "Bookmark") : trimmedTitle
        items[index].urlString = url.absoluteString
        if sort != .manual {
            applySort(persist: false)
        }
        save()
        return true
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func moveItem(from source: Int, to destination: Int) {
        guard items.indices.contains(source) else { return }
        // Switching to manual order when the user reorders.
        sort = .manual
        defaults.set(sort.rawValue, forKey: sortKey)
        let item = items.remove(at: source)
        let dest = min(max(destination, 0), items.count)
        items.insert(item, at: dest)
        save()
    }

    func setSort(_ sort: BookmarkSort) {
        self.sort = sort
        defaults.set(sort.rawValue, forKey: sortKey)
        applySort(persist: true)
    }

    private func applySort(persist: Bool) {
        switch sort {
        case .manual:
            break
        case .titleAsc:
            items.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .titleDesc:
            items.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
            }
        case .hostAsc:
            items.sort {
                hostKey($0).localizedCaseInsensitiveCompare(hostKey($1)) == .orderedAscending
            }
        }
        if persist { save() }
    }

    private func hostKey(_ item: BookmarkItem) -> String {
        (item.url?.host ?? item.urlString).lowercased()
    }

    /// Normalize for duplicate checks: lowercase scheme/host, drop `www.`, drop fragment, trim trailing `/`.
    private static func canonicalKey(forURLString string: String) -> String {
        guard let url = URL(string: string) else { return string.lowercased() }
        return canonicalKey(for: url)
    }

    private static func canonicalKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        var host = (components.host ?? "").lowercased()
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        components.host = host.isEmpty ? nil : host
        var path = components.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path.isEmpty { path = "/" }
        components.path = path
        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([BookmarkItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
