import Foundation

struct HistoryItem: Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var date: Date

    var url: URL? { URL(string: urlString) }
}

final class HistoryStore {
    static let shared = HistoryStore()

    private let key = "mmbrowser.history.items"
    private let defaults = UserDefaults.standard
    private(set) var items: [HistoryItem] = []

    private init() {
        load()
    }

    func add(title: String, url: URL, calendar: Calendar = .current) {
        // Always record during the session. When Clear Option → History is on,
        // AutoClearManager wipes this list on background / next launch.
        if url.absoluteString.hasPrefix("about:") { return }
        let now = Date()
        let item = HistoryItem(
            id: UUID(),
            title: title.isEmpty ? url.host ?? url.absoluteString : title,
            urlString: url.absoluteString,
            date: now
        )
        // Dedupe only within the same local day so a revisit on a later day
        // still appears under today's history while older days keep their entries.
        items.removeAll {
            $0.urlString == item.urlString && calendar.isDate($0.date, inSameDayAs: now)
        }
        items.insert(item, at: 0)
        if items.count > 300 { items = Array(items.prefix(300)) }
        save()
    }

    func clear() {
        items = []
        save()
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

    /// Removes history entries for a host, optionally limited to one local calendar day.
    func remove(host: String, onDayOf day: Date? = nil, calendar: Calendar = .current) {
        let key = host.lowercased()
        items.removeAll { item in
            guard Self.hostKey(for: item.urlString) == key else { return false }
            guard let day else { return true }
            return calendar.isDate(item.date, inSameDayAs: day)
        }
        save()
    }

    /// Removes every history entry whose local calendar day matches `day`.
    func remove(onDayOf day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        items.removeAll { $0.date >= start && $0.date < end }
        save()
    }

    /// Groups items by local day, newest day first; items within a day newest first.
    func sectionsByDay(calendar: Calendar = .current) -> [(day: Date, items: [HistoryItem])] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let dayItems = (grouped[day] ?? []).sorted { $0.date > $1.date }
            return (day, dayItems)
        }
    }

    /// Day → domain groups (newest hosts first by latest visit inside group).
    func sectionsByDayThenHost(calendar: Calendar = .current) -> [(day: Date, groups: [(host: String, items: [HistoryItem])])] {
        sectionsByDay(calendar: calendar).map { day, dayItems in
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

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
