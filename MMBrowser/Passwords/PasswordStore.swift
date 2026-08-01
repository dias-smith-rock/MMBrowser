import Foundation
import CryptoKit

struct PasswordItem: Codable, Equatable {
    var id: String
    var host: String
    var url: String
    var username: String
    var password: String
    var comments: String
    var updatedAt: Date

    var dto: PasswordItemDTO {
        PasswordItemDTO(
            id: id, host: host, url: url, username: username,
            password: password, comments: comments, updatedAt: updatedAt
        )
    }

    static func from(_ dto: PasswordItemDTO) -> PasswordItem {
        PasswordItem(
            id: dto.id, host: dto.host, url: dto.url, username: dto.username,
            password: dto.password, comments: dto.comments, updatedAt: dto.updatedAt
        )
    }
}

final class PasswordStore {
    static let shared = PasswordStore()
    private init() {}

    private var cache: [PasswordItem]?

    var all: [PasswordItem] { load() }

    func items(matching query: String) -> [PasswordItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = all.sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.host.lowercased().contains(q)
                || $0.url.lowercased().contains(q)
                || $0.username.lowercased().contains(q)
                || $0.comments.lowercased().contains(q)
        }
    }

    func items(forHost host: String) -> [PasswordItem] {
        let key = Self.normalizeHost(host)
        return all.filter {
            Self.normalizeHost($0.host) == key
                || Self.normalizeHost(URL(string: $0.url)?.host ?? "") == key
        }
    }

    @discardableResult
    func add(site: String, username: String, password: String, comments: String = "") -> PasswordItem? {
        var items = load()
        let item = PasswordItem(
            id: UUID().uuidString,
            host: Self.host(from: site),
            url: Self.normalizedURLString(from: site),
            username: username,
            password: password,
            comments: comments,
            updatedAt: Date()
        )
        items.append(item)
        guard persist(items) else { return nil }
        return item
    }

    @discardableResult
    func update(_ item: PasswordItem) -> Bool {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return false }
        var next = item
        let site = item.url.isEmpty ? item.host : item.url
        next.host = Self.host(from: site)
        next.url = Self.normalizedURLString(from: site)
        next.updatedAt = Date()
        items[idx] = next
        return persist(items)
    }

    @discardableResult
    func remove(id: String) -> Bool {
        var items = load()
        items.removeAll { $0.id == id }
        return persist(items)
    }

    @discardableResult
    func removeAll() -> Bool {
        persist([])
    }

    func reload() {
        cache = nil
        _ = load()
    }

    private func load() -> [PasswordItem] {
        if let cache { return cache }
        guard let key = VaultCrypto.activeKey() else {
            cache = []
            return []
        }
        guard let data = VaultKeychain.load(service: VaultKeychain.passwordsService, account: VaultKeychain.blobAccount) else {
            cache = []
            return []
        }
        do {
            let items = try VaultCrypto.decrypt(data, as: [PasswordItemDTO].self, with: key).map(PasswordItem.from)
            cache = items
            return items
        } catch {
            cache = []
            return []
        }
    }

    @discardableResult
    private func persist(_ items: [PasswordItem]) -> Bool {
        guard let key = VaultCrypto.activeKey() else { return false }
        do {
            let sealed = try VaultCrypto.encrypt(items.map(\.dto), with: key)
            let ok = VaultKeychain.set(service: VaultKeychain.passwordsService, account: VaultKeychain.blobAccount, data: sealed)
            if ok { cache = items }
            return ok
        } catch {
            return false
        }
    }

    static func host(from site: String) -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return normalizeHost(host)
        }
        if let url = URL(string: "https://\(trimmed)"), let host = url.host, !host.isEmpty {
            return normalizeHost(host)
        }
        return normalizeHost(trimmed)
    }

    static func normalizedURLString(from site: String) -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    static func normalizeHost(_ host: String) -> String {
        host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
