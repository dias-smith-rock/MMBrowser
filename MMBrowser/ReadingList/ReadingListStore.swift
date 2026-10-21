import Foundation

struct ReadingListItem: Codable, Equatable {
    let id: UUID
    var containerID: UUID
    var title: String
    var urlString: String
    var savedAt: Date
    var offlineFileName: String?

    var url: URL? { URL(string: urlString) }

    var offlineURL: URL? {
        guard let name = offlineFileName else { return nil }
        return ReadingListStore.directory(for: containerID).appendingPathComponent(name)
    }

    enum CodingKeys: String, CodingKey {
        case id, containerID, title, urlString, savedAt, offlineFileName
    }

    init(
        id: UUID = UUID(),
        containerID: UUID,
        title: String,
        urlString: String,
        savedAt: Date,
        offlineFileName: String? = nil
    ) {
        self.id = id
        self.containerID = containerID
        self.title = title
        self.urlString = urlString
        self.savedAt = savedAt
        self.offlineFileName = offlineFileName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        urlString = try c.decode(String.self, forKey: .urlString)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        offlineFileName = try c.decodeIfPresent(String.self, forKey: .offlineFileName)
        containerID = try c.decodeIfPresent(UUID.self, forKey: .containerID)
            ?? ContainerScope.resolveContainerID(nil)
    }
}

final class ReadingListStore {
    static let shared = ReadingListStore()
    private let key = "mmbrowser.readinglist.v2"
    private let legacyKey = "mmbrowser.readinglist"
    private let migratedKey = "mmbrowser.readinglist.migrated.v2"
    private(set) var items: [ReadingListItem] = []

    static var rootDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadingList", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func directory(for containerID: UUID) -> URL {
        let url = rootDirectory.appendingPathComponent(containerID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        load()
        migrateLegacyIfNeeded()
    }

    func items(containerID: UUID) -> [ReadingListItem] {
        let resolved = ContainerScope.resolveContainerID(containerID)
        return items.filter { $0.containerID == resolved }
    }

    func add(title: String, url: URL, pdfData: Data?, containerID: UUID) {
        let resolved = ContainerScope.resolveContainerID(containerID)
        let fileName: String?
        if let pdfData {
            let name = UUID().uuidString + ".pdf"
            try? pdfData.write(to: Self.directory(for: resolved).appendingPathComponent(name))
            fileName = name
        } else {
            fileName = nil
        }
        let item = ReadingListItem(
            id: UUID(),
            containerID: resolved,
            title: title.isEmpty ? (url.host ?? "Saved") : title,
            urlString: url.absoluteString,
            savedAt: Date(),
            offlineFileName: fileName
        )
        items.removeAll { $0.containerID == resolved && $0.urlString == url.absoluteString }
        items.insert(item, at: 0)
        save()
    }

    func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }) {
            deleteFiles(item)
        }
        items.removeAll { $0.id == id }
        save()
    }

    func clear(containerID: UUID) {
        let removed = items.filter { $0.containerID == containerID }
        items.removeAll { $0.containerID == containerID }
        removed.forEach(deleteFiles)
        save()
        try? FileManager.default.removeItem(at: Self.directory(for: containerID))
    }

    private func deleteFiles(_ item: ReadingListItem) {
        if let url = item.offlineURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func migrateLegacyIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        let fallback = ContainerScope.resolveContainerID(nil)
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([ReadingListItem].self, from: data) {
            for var item in legacy {
                // Move flat files into the default Space folder when present.
                if let name = item.offlineFileName {
                    let old = Self.rootDirectory.appendingPathComponent(name)
                    let destDir = Self.directory(for: item.containerID == fallback ? fallback : item.containerID)
                    let dest = destDir.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: old.path),
                       !FileManager.default.fileExists(atPath: dest.path) {
                        try? FileManager.default.moveItem(at: old, to: dest)
                    }
                }
                if !items.contains(where: { $0.id == item.id }) {
                    items.append(item)
                }
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        // Ensure every item has a folder-backed file when still in root.
        for index in items.indices {
            guard let name = items[index].offlineFileName else { continue }
            let rootFile = Self.rootDirectory.appendingPathComponent(name)
            let dest = Self.directory(for: items[index].containerID).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: rootFile.path),
               !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.moveItem(at: rootFile, to: dest)
            }
        }
        save()
        UserDefaults.standard.set(true, forKey: migratedKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ReadingListItem].self, from: data) {
            items = decoded
            return
        }
        // Fall through to legacy key during first launch of v2.
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let decoded = try? JSONDecoder().decode([ReadingListItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
