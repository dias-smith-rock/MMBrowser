import Foundation

struct BookmarkItem: Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String

    var url: URL? { URL(string: urlString) }
}

final class BookmarkStore {
    static let shared = BookmarkStore()

    private let key = "mmbrowser.bookmarks.items"
    private let defaults = UserDefaults.standard
    private(set) var items: [BookmarkItem] = []

    private init() {
        load()
        if items.isEmpty {
            items = [
                BookmarkItem(id: UUID(), title: "Google", urlString: "https://www.google.com"),
                BookmarkItem(id: UUID(), title: "YouTube", urlString: "https://www.youtube.com")
            ]
            save()
        }
    }

    func add(title: String, url: URL) {
        if items.contains(where: { $0.urlString == url.absoluteString }) { return }
        items.insert(BookmarkItem(id: UUID(), title: title.isEmpty ? (url.host ?? "Bookmark") : title, urlString: url.absoluteString), at: 0)
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
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
