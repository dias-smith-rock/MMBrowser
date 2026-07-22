import Foundation

struct ReadingListItem: Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var savedAt: Date
    var offlineFileName: String?

    var url: URL? { URL(string: urlString) }

    var offlineURL: URL? {
        guard let name = offlineFileName else { return nil }
        return ReadingListStore.directory.appendingPathComponent(name)
    }
}

final class ReadingListStore {
    static let shared = ReadingListStore()
    private let key = "mmbrowser.readinglist"
    private(set) var items: [ReadingListItem] = []

    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReadingList", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() { load() }

    func add(title: String, url: URL, pdfData: Data?) {
        let fileName: String?
        if let pdfData = pdfData {
            let name = UUID().uuidString + ".pdf"
            try? pdfData.write(to: Self.directory.appendingPathComponent(name))
            fileName = name
        } else {
            fileName = nil
        }
        let item = ReadingListItem(id: UUID(), title: title.isEmpty ? (url.host ?? "Saved") : title, urlString: url.absoluteString, savedAt: Date(), offlineFileName: fileName)
        items.removeAll { $0.urlString == url.absoluteString }
        items.insert(item, at: 0)
        save()
    }

    func remove(id: UUID) {
        if let item = items.first(where: { $0.id == id }), let name = item.offlineFileName {
            try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(name))
        }
        items.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ReadingListItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
