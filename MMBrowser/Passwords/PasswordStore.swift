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

    /// Matches by exact host first, then by registrable domain so a saved
    /// `google.com` entry also covers `accounts.google.com`.
    func items(forHost host: String) -> [PasswordItem] {
        let key = Self.normalizeHost(host)
        guard !key.isEmpty else { return [] }

        func hosts(of item: PasswordItem) -> [String] {
            [Self.normalizeHost(item.host), Self.normalizeHost(URL(string: item.url)?.host ?? "")]
                .filter { !$0.isEmpty }
        }

        let exact = all.filter { hosts(of: $0).contains(key) }
        if !exact.isEmpty { return exact }

        let domain = Self.registrableDomain(key)
        guard !domain.isEmpty else { return [] }
        return all.filter { item in
            hosts(of: item).contains { Self.registrableDomain($0) == domain }
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
            // Locked / mid-migration — never cache an empty vault.
            return []
        }
        guard let data = VaultKeychain.load(service: VaultKeychain.passwordsService, account: VaultKeychain.blobAccount) else {
            cache = []
            return []
        }
        if let items = try? VaultCrypto.decrypt(data, as: [PasswordItemDTO].self, with: key).map(PasswordItem.from) {
            cache = items
            return items
        }
        // Recovery: blob may still be sealed with the device key after a failed master migration.
        if VaultCrypto.hasMasterPassword {
            let device = VaultCrypto.deviceKey()
            if let items = try? VaultCrypto.decrypt(data, as: [PasswordItemDTO].self, with: device).map(PasswordItem.from) {
                _ = persist(items) // rewrite under the active master key
                return items
            }
        }
        return []
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
        var value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if value.hasPrefix("www.") {
            value.removeFirst(4)
        }
        return value
    }

    /// Second-level public suffixes where the registrable domain needs three labels.
    private static let compoundSuffixes: Set<String> = [
        "co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go", "in", "id"
    ]

    /// Approximate eTLD+1 (no Public Suffix List dependency).
    static func registrableDomain(_ host: String) -> String {
        let labels = normalizeHost(host).split(separator: ".").map(String.init)
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        if compoundSuffixes.contains(labels[labels.count - 2]), labels[labels.count - 1].count <= 3 {
            return labels.suffix(3).joined(separator: ".")
        }
        return labels.suffix(2).joined(separator: ".")
    }
}
