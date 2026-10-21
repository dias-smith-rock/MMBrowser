import Foundation
import FirebaseRemoteConfig

/// Fetches and caches Remote Config feature flags.
final class RemoteConfigManager {
    static let shared = RemoteConfigManager()

    enum Key: String {
        /// JSON: `{"domains":["*"]}` — hosts whose Watch Later media must play online.
        case watchLaterBlacklist = "watch_later_blacklist"
    }

    /// In-app default matches Firebase console: all domains require online media playback.
    static let watchLaterBlacklistDefaultJSON = #"{"domains":["*"]}"#

    private let remoteConfig = RemoteConfig.remoteConfig()
    private var didStart = false

    private init() {}

    func start() {
        guard !didStart else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        didStart = true

        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 12 * 60 * 60
        #endif
        remoteConfig.configSettings = settings

        remoteConfig.setDefaults([
            Key.watchLaterBlacklist.rawValue: NSString(string: Self.watchLaterBlacklistDefaultJSON)
        ] as [String: NSObject])

        fetchAndActivate()
    }

    func fetchAndActivate() {
        guard didStart else { return }
        remoteConfig.fetchAndActivate { status, error in
            #if DEBUG
            if let error {
                print("[RemoteConfig] fetch error: \(error.localizedDescription)")
            } else {
                print("[RemoteConfig] fetch status: \(status.rawValue)")
            }
            #endif
            NotificationCenter.default.post(name: .remoteConfigDidUpdate, object: nil)
        }
    }

    func stringValue(for key: Key, default defaultValue: String = "") -> String {
        let value = remoteConfig.configValue(forKey: key.rawValue).stringValue ?? ""
        return value.isEmpty ? defaultValue : value
    }

    func boolValue(for key: Key, default defaultValue: Bool) -> Bool {
        let raw = remoteConfig.configValue(forKey: key.rawValue)
        // Unset keys fall back to defaults set above.
        if raw.source == .static {
            return defaultValue
        }
        return raw.boolValue
    }

    /// Domain patterns from `watch_later_blacklist` (supports `*`, `*.example.com`, exact hosts).
    /// Always fail closed: missing / invalid / unfetched config → `["*"]` (all hosts need network).
    var watchLaterBlacklistDomains: [String] {
        // Remote Config not started (no plist / pre-bootstrap) → all media online-only.
        guard didStart else { return ["*"] }
        let raw = stringValue(
            for: .watchLaterBlacklist,
            default: Self.watchLaterBlacklistDefaultJSON
        )
        return Self.parseWatchLaterBlacklistDomains(from: raw)
    }

    /// `true` when media for this page must use the network (blacklist hit).
    /// Default / unfetched / unknown host → `true` (cannot play offline).
    func watchLaterRequiresOnlineMedia(for url: URL?) -> Bool {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return true }
        let patterns = watchLaterBlacklistDomains
        // Empty list must not open the gate — treat as fully blacklisted.
        if patterns.isEmpty { return true }
        return patterns.contains { Self.host(host, matchesPattern: $0) }
    }

    static func parseWatchLaterBlacklistDomains(from json: String) -> [String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["*"]
        }
        let list = (obj["domains"] as? [Any]) ?? []
        let domains = list.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Explicit empty `domains` array still fails closed until ops publish a real allow-list.
        return domains.isEmpty ? ["*"] : domains
    }

    /// Wildcard host match: `*`, `*.example.com`, `example.com`, or simple `*` globs.
    static func host(_ host: String, matchesPattern pattern: String) -> Bool {
        let h = host.lowercased()
        let p = pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return false }
        if p == "*" { return true }
        if p.hasPrefix("*.") {
            let suffix = String(p.dropFirst(2))
            guard !suffix.isEmpty else { return true }
            return h == suffix || h.hasSuffix("." + suffix)
        }
        if p.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: p)
                .replacingOccurrences(of: "\\*", with: ".*")
            return h.range(of: "^\(escaped)$", options: .regularExpression) != nil
        }
        return h == p || h.hasSuffix("." + p)
    }
}

/// Combines Remote Config blacklist + copyright rules for Watch Later media.
enum WatchLaterMediaPolicy {
    /// Offline local media playback / save is allowed only when not blacklisted and not copyright-blocked.
    /// Fail closed: until Remote Config says otherwise, every host needs the network for media.
    static func allowsOfflineMedia(on url: URL?) -> Bool {
        if OfflineMediaCopyrightPolicy.restrictsAudioVideo(on: url) { return false }
        // Includes: not started, fetch failed, default `{"domains":["*"]}`.
        if RemoteConfigManager.shared.watchLaterRequiresOnlineMedia(for: url) { return false }
        return true
    }

    static let onlineMediaRequiredNotice =
        "Media on this site requires a network connection. Use Open Live to play."
}

extension Notification.Name {
    static let remoteConfigDidUpdate = Notification.Name("mmbrowser.remoteConfigDidUpdate")
}
