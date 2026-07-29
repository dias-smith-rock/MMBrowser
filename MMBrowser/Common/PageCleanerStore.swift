import Foundation

struct PageCleanerRule: Codable, Equatable {
    let id: UUID
    var host: String
    /// `nil` = domain-wide; otherwise exact URL (fragment stripped).
    var urlString: String?
    var selector: String
    var label: String
    var createdAt: Date

    var isURLScoped: Bool { urlString != nil }
}

final class PageCleanerStore {
    static let shared = PageCleanerStore()

    private let key = "mmbrowser.pagecleaner.rules"
    private let defaults = UserDefaults.standard
    private(set) var items: [PageCleanerRule] = []

    private init() {
        load()
    }

    static func canonicalURLString(_ url: URL) -> String {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.fragment = nil
        return comps?.string ?? url.absoluteString
    }

    func rules(matching url: URL) -> [PageCleanerRule] {
        guard let host = url.host?.lowercased() else { return [] }
        let canon = Self.canonicalURLString(url)
        return items.filter { rule in
            guard rule.host.lowercased() == host else { return false }
            if let scoped = rule.urlString {
                return scoped == canon
            }
            return true
        }
    }

    /// Groups rules by host, hosts sorted A→Z, rules newest first.
    func groupedByHost() -> [(host: String, rules: [PageCleanerRule])] {
        let map = Dictionary(grouping: items, by: { $0.host.lowercased() })
        return map.keys.sorted().map { host in
            let rules = (map[host] ?? []).sorted { $0.createdAt > $1.createdAt }
            return (host: host, rules: rules)
        }
    }

    @discardableResult
    func add(host: String, urlString: String?, selector: String, label: String) -> PageCleanerRule? {
        let normalizedHost = host.lowercased()
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty, !trimmedSelector.isEmpty else { return nil }

        if items.contains(where: {
            $0.host.lowercased() == normalizedHost
                && $0.urlString == urlString
                && $0.selector == trimmedSelector
        }) {
            return nil
        }

        let rule = PageCleanerRule(
            id: UUID(),
            host: normalizedHost,
            urlString: urlString,
            selector: trimmedSelector,
            label: label.isEmpty ? trimmedSelector : label,
            createdAt: Date()
        )
        items.insert(rule, at: 0)
        save()
        return rule
    }

    func remove(id: UUID) {
        let before = items.count
        items.removeAll { $0.id == id }
        guard items.count != before else { return }
        save()
    }

    func removeAll(host: String) {
        let normalized = host.lowercased()
        let before = items.count
        items.removeAll { $0.host.lowercased() == normalized }
        guard items.count != before else { return }
        save()
    }

    func removeAll() {
        guard !items.isEmpty else { return }
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PageCleanerRule].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .pageCleanerRulesChanged, object: nil)
    }
}

extension Notification.Name {
    static let pageCleanerRulesChanged = Notification.Name("mmbrowser.pagecleaner.changed")
}
