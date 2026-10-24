import Foundation

struct HistoryItem: Codable, Equatable {
    let id: UUID
    var containerID: UUID
    var title: String
    var urlString: String
    var date: Date

    var url: URL? {
        if let u = URL(string: urlString) { return u }
        // Fallback for partially-encoded history strings.
        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let u = URL(string: encoded) {
            return u
        }
        return nil
    }

    /// Prefer a navigable http(s) URL for address-bar suggestion taps.
    var navigationURL: URL? {
        guard let url else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" { return url }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, containerID, title, urlString, date
    }

    init(id: UUID = UUID(), containerID: UUID, title: String, urlString: String, date: Date) {
        self.id = id
        self.containerID = containerID
        self.title = title
        self.urlString = urlString
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        urlString = try c.decode(String.self, forKey: .urlString)
        date = try c.decode(Date.self, forKey: .date)
        containerID = try c.decodeIfPresent(UUID.self, forKey: .containerID)
            ?? ContainerScope.resolveContainerID(nil)
    }
}

final class HistoryStore {
    static let shared = HistoryStore()

    private let key = "mmbrowser.history.items.v2"
    private let defaults = UserDefaults.standard
    private(set) var items: [HistoryItem] = []
    private var saveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 1.5
    private let perContainerLimit = 300
    /// Cap used for address-bar autocomplete (unique URLs, most recent first).
    static let autocompletePoolLimit = 200
    static let autocompleteDisplayLimit = 8

    private init() {
        load()
    }

    func items(containerID: UUID) -> [HistoryItem] {
        items.filter { $0.containerID == containerID }
    }

    func add(title: String, url: URL, containerID: UUID, calendar: Calendar = .current) {
        if url.absoluteString.hasPrefix("about:") { return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return }
        let resolved = ContainerScope.resolveContainerID(containerID)
        let now = Date()
        let item = HistoryItem(
            containerID: resolved,
            title: title.isEmpty ? url.host ?? url.absoluteString : title,
            urlString: url.absoluteString,
            date: now
        )
        // Keep one entry per URL per day for History UI, and always refresh title on revisit.
        items.removeAll {
            $0.containerID == resolved
                && $0.urlString == item.urlString
                && calendar.isDate($0.date, inSameDayAs: now)
        }
        items.insert(item, at: 0)
        trim(containerID: resolved)
        scheduleSave()
    }

    /// Normalize host for suggestion dedupe (`www.youtube.com` / `m.youtube.com` → `youtube.com`).
    static func suggestionDedupeHost(for urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            return urlString.lowercased()
        }
        var h = host
        for prefix in ["www.", "m.", "mobile.", "music."] where h.hasPrefix(prefix) {
            h = String(h.dropFirst(prefix.count))
            break
        }
        return h
    }

    /// Unique recent visits for address-bar suggestions (newest first, max `autocompletePoolLimit`).
    /// Dedupes by registrable-ish host so many YouTube paths only yield one row.
    func recentUniqueVisits(containerID: UUID, limit: Int = HistoryStore.autocompletePoolLimit) -> [HistoryItem] {
        var seen = Set<String>()
        var result: [HistoryItem] = []
        let capped = max(1, min(limit, Self.autocompletePoolLimit))
        for item in items where item.containerID == containerID {
            let key = Self.suggestionDedupeHost(for: item.urlString)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
            if result.count >= capped { break }
        }
        return result
    }

    /// Filter unique recent visits by title / URL / host for omnibox autocomplete.
    func addressBarSuggestions(
        matching query: String,
        containerID: UUID,
        displayLimit: Int = HistoryStore.autocompleteDisplayLimit
    ) -> [HistoryItem] {
        let pool = recentUniqueVisits(containerID: containerID)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cappedDisplay = max(1, min(displayLimit, Self.autocompleteDisplayLimit))
        guard !q.isEmpty else {
            return Array(pool.prefix(cappedDisplay))
        }
        return Array(pool.filter { item in
            if item.title.lowercased().contains(q) { return true }
            if item.urlString.lowercased().contains(q) { return true }
            if let host = item.url?.host?.lowercased(), host.contains(q) { return true }
            if Self.suggestionDedupeHost(for: item.urlString).contains(q) { return true }
            return false
        }.prefix(cappedDisplay))
    }

    private func trim(containerID: UUID) {
        var count = 0
        items = items.filter { item in
            guard item.containerID == containerID else { return true }
            count += 1
            return count <= perContainerLimit
        }
    }

    func clear() {
        items = []
        saveNow()
    }

    func clear(containerID: UUID) {
        items.removeAll { $0.containerID == containerID }
        saveNow()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        saveNow()
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        saveNow()
    }

    func remove(host: String, containerID: UUID? = nil, onDayOf day: Date? = nil, calendar: Calendar = .current) {
        let key = host.lowercased()
        items.removeAll { item in
            if let containerID, item.containerID != containerID { return false }
            guard Self.hostKey(for: item.urlString) == key else { return false }
            guard let day else { return true }
            return calendar.isDate(item.date, inSameDayAs: day)
        }
        saveNow()
    }

    func remove(onDayOf day: Date, containerID: UUID? = nil, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        items.removeAll { item in
            if let containerID, item.containerID != containerID { return false }
            return item.date >= start && item.date < end
        }
        saveNow()
    }

    func sectionsByDay(containerID: UUID? = nil, calendar: Calendar = .current) -> [(day: Date, items: [HistoryItem])] {
        let base = containerID.map { items(containerID: $0) } ?? items
        let grouped = Dictionary(grouping: base) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let dayItems = (grouped[day] ?? []).sorted { $0.date > $1.date }
            return (day, dayItems)
        }
    }

    func sectionsByDayThenHost(containerID: UUID? = nil, calendar: Calendar = .current) -> [(day: Date, groups: [(host: String, items: [HistoryItem])])] {
        sectionsByDay(containerID: containerID, calendar: calendar).map { day, dayItems in
            let byHost = Dictionary(grouping: dayItems) { Self.hostKey(for: $0.urlString) }
            let groups = byHost.keys.sorted { a, b in
                let aDate = byHost[a]?.first?.date ?? .distantPast
                let bDate = byHost[b]?.first?.date ?? .distantPast
                return aDate > bDate
            }.map { host in
                (host, (byHost[host] ?? []).sorted { $0.date > $1.date })
            }
            return (day, groups)
        }
    }

    static func hostKey(for urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return urlString
        }
        return host.lowercased()
    }

    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        saveNow()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: work)
    }

    private func saveNow() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
