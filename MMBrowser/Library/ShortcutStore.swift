import Foundation

struct ShortcutItem: Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String

    var url: URL? { URL(string: urlString) }
}

final class ShortcutStore {
    static let shared = ShortcutStore()

    private let key = "mmbrowser.shortcuts.items"
    private let defaults = UserDefaults.standard
    private(set) var items: [ShortcutItem] = []

    private init() {
        load()
        if items.isEmpty {
            items = [
                ShortcutItem(id: UUID(), title: "Google", urlString: "https://www.google.com"),
                ShortcutItem(id: UUID(), title: "YouTube", urlString: "https://www.youtube.com"),
                ShortcutItem(id: UUID(), title: "Wikipedia", urlString: "https://www.wikipedia.org"),
                ShortcutItem(id: UUID(), title: "Sogou Search", urlString: "https://www.sogou.com")
            ]
            save()
        }
    }

    func add(title: String, url: URL) {
        items.append(ShortcutItem(id: UUID(), title: title, urlString: url.absoluteString))
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func replaceAll(_ newItems: [ShortcutItem]) {
        items = newItems
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ShortcutItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
