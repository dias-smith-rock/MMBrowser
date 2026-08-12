import Foundation

struct HistoryItem: Codable, Equatable {
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

final class HistoryStore {
    static let shared = HistoryStore()

    private let key = "mmbrowser.history.items.v2"
    private let defaults = UserDefaults.standard
    private(set) var items: [HistoryItem] = []
    private var saveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 1.5
    private let perContainerLimit = 300

    private init() {
        load()
    }

    func items(containerID: UUID) -> [HistoryItem] {
        items.filter { $0.containerID == containerID }
    }

    func add(title: String, url: URL, containerID: UUID, calendar: Calendar = .current) {
        if url.absoluteString.hasPrefix("about:") { return }
        let resolved = ContainerScope.resolveContainerID(containerID)
        let now = Date()
        let item = HistoryItem(
            containerID: resolved,
            title: title.isEmpty ? url.host ?? url.absoluteString : title,
            urlString: url.absoluteString,
            date: now
        )
        items.removeAll {
            $0.containerID == resolved
                && $0.urlString == item.urlString
                && calendar.isDate($0.date, inSameDayAs: now)
        }
        items.insert(item, at: 0)
        trim(containerID: resolved)
        scheduleSave()
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
