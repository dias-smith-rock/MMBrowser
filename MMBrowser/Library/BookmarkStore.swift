import Foundation

struct BookmarkItem: Codable, Equatable {
    let id: UUID
    var containerID: UUID
    var title: String
    var urlString: String

    var url: URL? { URL(string: urlString) }

    enum CodingKeys: String, CodingKey {
        case id, containerID, title, urlString
    }

    init(id: UUID = UUID(), containerID: UUID, title: String, urlString: String) {
        self.id = id
        self.containerID = containerID
        self.title = title
        self.urlString = urlString
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        urlString = try c.decode(String.self, forKey: .urlString)
        containerID = try c.decodeIfPresent(UUID.self, forKey: .containerID)
            ?? ContainerScope.resolveContainerID(nil)
    }
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

    private let key = "mmbrowser.bookmarks.items.v2"
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
        applySort(persist: false)
    }

    func items(containerID: UUID) -> [BookmarkItem] {
        items.filter { $0.containerID == containerID }
    }

    @discardableResult
    func add(title: String, url: URL, containerID: UUID) -> Bool {
        let resolved = ContainerScope.resolveContainerID(containerID)
        let key = Self.canonicalKey(for: url)
        if items.contains(where: {
            $0.containerID == resolved && Self.canonicalKey(forURLString: $0.urlString) == key
        }) {
            return false
        }
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items.insert(
            BookmarkItem(
                containerID: resolved,
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

    func contains(url: URL, containerID: UUID) -> Bool {
        let resolved = ContainerScope.resolveContainerID(containerID)
        let key = Self.canonicalKey(for: url)
        return items.contains {
            $0.containerID == resolved && Self.canonicalKey(forURLString: $0.urlString) == key
        }
    }

    @discardableResult
    func update(id: UUID, title: String, urlString: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL), url.scheme != nil else {
            return false
        }
        let containerID = items[index].containerID
        let key = Self.canonicalKey(for: url)
        if items.contains(where: {
            $0.id != id && $0.containerID == containerID && Self.canonicalKey(forURLString: $0.urlString) == key
        }) {
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

    func remove(host: String, containerID: UUID? = nil) {
        let key = host.lowercased()
        items.removeAll { item in
            if let containerID, item.containerID != containerID { return false }
            return Self.hostKey(forURLString: item.urlString) == key
        }
        save()
    }

    func clear() {
        items = []
        save()
    }

    func clear(containerID: UUID) {
        items.removeAll { $0.containerID == containerID }
        save()
    }

    func groupsByHost(containerID: UUID? = nil) -> [(host: String, items: [BookmarkItem])] {
        let base = containerID.map { items(containerID: $0) } ?? items
        var order: [String] = []
        var map: [String: [BookmarkItem]] = [:]
        for item in base {
            let host = Self.hostKey(forURLString: item.urlString)
            if map[host] == nil {
                order.append(host)
                map[host] = []
            }
            map[host, default: []].append(item)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    static func hostKey(forURLString string: String) -> String {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty else {
            return string.lowercased()
        }
        return host.lowercased()
    }

    func moveItem(from source: Int, to destination: Int, containerID: UUID) {
        let scoped = items(containerID: containerID)
        guard scoped.indices.contains(source) else { return }
        sort = .manual
        defaults.set(sort.rawValue, forKey: sortKey)
        guard let globalSource = items.firstIndex(where: { $0.id == scoped[source].id }) else { return }
        let item = items.remove(at: globalSource)
        let scopedAfterRemove = items(containerID: containerID)
        let dest = min(max(destination, 0), scopedAfterRemove.count)
        if dest >= scopedAfterRemove.count {
            items.append(item)
        } else {
            let anchorID = scopedAfterRemove[dest].id
            if let globalDest = items.firstIndex(where: { $0.id == anchorID }) {
                items.insert(item, at: globalDest)
            } else {
                items.append(item)
            }
        }
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
