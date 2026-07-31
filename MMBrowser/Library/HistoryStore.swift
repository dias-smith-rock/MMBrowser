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

    func add(title: String, url: URL) {
        if AppSettings.autoClearHistory { return }
        if url.absoluteString.hasPrefix("about:") { return }
        let item = HistoryItem(id: UUID(), title: title.isEmpty ? url.host ?? url.absoluteString : title, urlString: url.absoluteString, date: Date())
        items.removeAll { $0.urlString == item.urlString }
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
