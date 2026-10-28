import Foundation

/// Per-site exception to global Block Ads & Trackers. Does not change other Spaces' settings.
enum SiteBlockingStore {
    private static let key = "blocking.allowedHosts"
    static let changed = Notification.Name("mmbrowser.siteBlocking.changed")

    static func hostKey(for url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func isAllowed(_ host: String) -> Bool {
        allowedHosts.contains(normalize(host))
    }

    /// Global switch and this host's exception.
    static func isProtectionOn(for url: URL?) -> Bool {
        guard AppSettings.trackerProtectionEnabled else { return false }
        guard let host = hostKey(for: url) else { return true }
        return !isAllowed(host)
    }

    static func setAllowed(_ host: String, allowed: Bool) {
        var hosts = allowedHosts
        let key = normalize(host)
        if allowed { hosts.insert(key) } else { hosts.remove(key) }
        UserDefaults.standard.set(Array(hosts), forKey: Self.key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    private static var allowedHosts: Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).map(normalize))
    }

    private static func normalize(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}
