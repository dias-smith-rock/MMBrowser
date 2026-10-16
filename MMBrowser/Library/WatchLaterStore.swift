import Foundation

struct WatchLaterItem: Codable, Equatable {
    let id: UUID
    var containerID: UUID
    var title: String
    var urlString: String
    var date: Date

    var url: URL? { URL(string: urlString) }

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

/// Per-space Watch Later list. Same persistence style as browsing history.
final class WatchLaterStore {
    static let shared = WatchLaterStore()

    private let key = "mmbrowser.watchLater.items.v1"
    private let defaults = UserDefaults.standard
    private(set) var items: [WatchLaterItem] = []
    private let perContainerLimit = 500

    private init() {
        load()
    }

    func items(containerID: UUID) -> [WatchLaterItem] {
        items.filter { $0.containerID == containerID }
    }

    @discardableResult
    func add(title: String, url: URL, containerID: UUID) -> Bool {
        if url.absoluteString.hasPrefix("about:") { return false }
        let resolved = ContainerScope.resolveContainerID(containerID)
        let urlString = url.absoluteString
        if items.contains(where: { $0.containerID == resolved && $0.urlString == urlString }) {
            return false
        }
        let item = WatchLaterItem(
            containerID: resolved,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (url.host ?? url.absoluteString)
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            urlString: urlString,
            date: Date()
        )
        items.insert(item, at: 0)
        trim(containerID: resolved)
        saveNow()
        return true
    }

    @discardableResult
    func update(id: UUID, title: String, url: URL) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        let urlString = url.absoluteString
        guard !urlString.isEmpty, !urlString.hasPrefix("about:") else { return false }
        let containerID = items[index].containerID
        if items.contains(where: { $0.id != id && $0.containerID == containerID && $0.urlString == urlString }) {
            return false
        }
        items[index].title = trimmedTitle
        items[index].urlString = urlString
        saveNow()
        return true
    }

    func clear(containerID: UUID) {
        items.removeAll { $0.containerID == containerID }
        saveNow()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        saveNow()
    }

    func remove(onDayOf day: Date, containerID: UUID, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        items.removeAll { item in
            item.containerID == containerID && item.date >= start && item.date < end
        }
        saveNow()
    }

    func sectionsByDay(containerID: UUID, calendar: Calendar = .current) -> [(day: Date, items: [WatchLaterItem])] {
        let grouped = Dictionary(grouping: items(containerID: containerID)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let dayItems = (grouped[day] ?? []).sorted { $0.date > $1.date }
            return (day, dayItems)
        }
    }

    private func trim(containerID: UUID) {
        var count = 0
        items = items.filter { item in
            guard item.containerID == containerID else { return true }
            count += 1
            return count <= perContainerLimit
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WatchLaterItem].self, from: data) else { return }
        items = decoded
    }

    private func saveNow() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
