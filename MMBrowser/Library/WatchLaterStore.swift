import Foundation

struct WatchLaterItem: Codable, Equatable {
    let id: UUID
    var containerID: UUID
    var title: String
    var urlString: String
    var date: Date
    /// A playable video was found on the page when it was saved.
    var hasVideo: Bool
    var pageArchiveName: String?
    var videoFileName: String?
    /// `saving`, `ready`, or `failed`. Empty on older records.
    var cacheState: String

    var url: URL? { URL(string: urlString) }

    var pageArchiveURL: URL? {
        guard let pageArchiveName else { return nil }
        return WatchLaterStore.fileURL(named: pageArchiveName)
    }

    var videoFileURL: URL? {
        guard let videoFileName else { return nil }
        return WatchLaterStore.fileURL(named: videoFileName)
    }

    var hasVideoFile: Bool {
        guard let url = videoFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var hasOfflinePage: Bool {
        guard let url = pageArchiveURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Page snapshot is stored, and the video file is stored when the page had one.
    var isCacheComplete: Bool {
        guard hasOfflinePage else { return false }
        if hasVideo { return hasVideoFile }
        return cacheState == "ready"
    }

    enum CodingKeys: String, CodingKey {
        case id, containerID, title, urlString, date, hasVideo, pageArchiveName, videoFileName, cacheState
    }

    init(
        id: UUID = UUID(),
        containerID: UUID,
        title: String,
        urlString: String,
        date: Date,
        hasVideo: Bool = false,
        pageArchiveName: String? = nil,
        videoFileName: String? = nil,
        cacheState: String = "idle"
    ) {
        self.id = id
        self.containerID = containerID
        self.title = title
        self.urlString = urlString
        self.date = date
        self.hasVideo = hasVideo
        self.pageArchiveName = pageArchiveName
        self.videoFileName = videoFileName
        self.cacheState = cacheState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        urlString = try c.decode(String.self, forKey: .urlString)
        date = try c.decode(Date.self, forKey: .date)
        containerID = try c.decodeIfPresent(UUID.self, forKey: .containerID)
            ?? ContainerScope.resolveContainerID(nil)
        hasVideo = try c.decodeIfPresent(Bool.self, forKey: .hasVideo) ?? false
        pageArchiveName = try c.decodeIfPresent(String.self, forKey: .pageArchiveName)
        videoFileName = try c.decodeIfPresent(String.self, forKey: .videoFileName)
        cacheState = try c.decodeIfPresent(String.self, forKey: .cacheState) ?? "idle"
    }
}

/// Per-space Watch Later list. Same persistence style as browsing history.
final class WatchLaterStore {
    static let shared = WatchLaterStore()
    static let didChangeNotification = Notification.Name("mmbrowser.watchLater.changed")

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
    func add(title: String, url: URL, containerID: UUID) -> WatchLaterItem? {
        if url.absoluteString.hasPrefix("about:") { return nil }
        let resolved = ContainerScope.resolveContainerID(containerID)
        let urlString = url.absoluteString
        if items.contains(where: { $0.containerID == resolved && $0.urlString == urlString }) {
            return nil
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
        return item
    }

    func markCaching(id: UUID, hasVideo: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].hasVideo = hasVideo
        items[index].cacheState = "saving"
        saveNow()
    }

    func markPageArchived(id: UUID, fileName: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pageArchiveName = fileName
        refreshCacheState(at: index)
        saveNow()
    }

    func markVideoSaved(id: UUID, fileName: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].hasVideo = true
        items[index].videoFileName = fileName
        refreshCacheState(at: index)
        saveNow()
    }

    func markCacheFailed(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].cacheState = "failed"
        saveNow()
    }

    private func refreshCacheState(at index: Int) {
        let item = items[index]
        if item.hasOfflinePage && (!item.hasVideo || item.hasVideoFile) {
            items[index].cacheState = "ready"
        } else if item.cacheState != "failed" {
            items[index].cacheState = "saving"
        }
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
        let removed = items.filter { $0.containerID == containerID }
        items.removeAll { $0.containerID == containerID }
        removed.forEach(deleteFiles)
        saveNow()
    }

    func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            deleteFiles(item)
        }
        items.removeAll { $0.id == id }
        saveNow()
    }

    func remove(onDayOf day: Date, containerID: UUID, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let removed = items.filter { item in
            item.containerID == containerID && item.date >= start && item.date < end
        }
        items.removeAll { item in
            item.containerID == containerID && item.date >= start && item.date < end
        }
        removed.forEach(deleteFiles)
        saveNow()
    }

    func sectionsByDay(containerID: UUID, calendar: Calendar = .current) -> [(day: Date, items: [WatchLaterItem])] {
        let grouped = Dictionary(grouping: items(containerID: containerID)) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let dayItems = (grouped[day] ?? []).sorted { $0.date > $1.date }
            return (day, dayItems)
        }
    }

    static func fileURL(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchLater", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func trim(containerID: UUID) {
        var kept: [WatchLaterItem] = []
        var removed: [WatchLaterItem] = []
        var count = 0
        for item in items {
            guard item.containerID == containerID else {
                kept.append(item)
                continue
            }
            count += 1
            if count <= perContainerLimit {
                kept.append(item)
            } else {
                removed.append(item)
            }
        }
        items = kept
        removed.forEach(deleteFiles)
    }

    private func deleteFiles(_ item: WatchLaterItem) {
        if let url = item.pageArchiveURL { try? FileManager.default.removeItem(at: url) }
        if let url = item.videoFileURL { try? FileManager.default.removeItem(at: url) }
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
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
