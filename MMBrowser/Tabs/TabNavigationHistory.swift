import Foundation

/// Per-tab back/forward stack. Survives WKWebView recreation; cleared when the tab closes.
final class TabNavigationHistory: Codable, Equatable {
    private(set) var urls: [String] = []
    private(set) var index: Int = -1
    /// Next `record` updates the current slot (restore / our own back-forward load) instead of pushing.
    var suppressNextRecord = false

    private static let maxEntries = 50

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < urls.count - 1 }

    var currentURL: URL? {
        guard index >= 0, index < urls.count else { return nil }
        return URL(string: urls[index])
    }

    var isEmpty: Bool { urls.isEmpty || index < 0 }

    static func == (lhs: TabNavigationHistory, rhs: TabNavigationHistory) -> Bool {
        lhs.urls == rhs.urls && lhs.index == rhs.index
    }

    enum CodingKeys: String, CodingKey { case urls, index }

    init() {}

    init(urls: [String], index: Int) {
        self.urls = urls
        if urls.isEmpty {
            self.index = -1
        } else {
            self.index = min(max(0, index), urls.count - 1)
        }
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
        let raw = try c.decodeIfPresent(Int.self, forKey: .index) ?? -1
        if urls.isEmpty {
            index = -1
        } else {
            index = min(max(0, raw), urls.count - 1)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(urls, forKey: .urls)
        try c.encode(index, forKey: .index)
    }

    func clear() {
        urls = []
        index = -1
        suppressNextRecord = false
    }

    func restore(urls: [String], index: Int) {
        self.urls = urls.filter { Self.isPersistable($0) }
        if self.urls.isEmpty {
            self.index = -1
        } else {
            self.index = min(max(0, index), self.urls.count - 1)
        }
        suppressNextRecord = false
    }

    /// Records a committed main-frame URL (or SPA location change).
    func record(_ url: URL) {
        guard let normalized = Self.normalize(url) else { return }

        if suppressNextRecord {
            suppressNextRecord = false
            if index >= 0, index < urls.count {
                urls[index] = normalized
            } else {
                urls = [normalized]
                index = 0
            }
            return
        }

        if index >= 0, index < urls.count, urls[index] == normalized {
            return
        }

        // Replace when only the fragment changed.
        if index >= 0, index < urls.count,
           Self.equalIgnoringFragment(urls[index], normalized) {
            urls[index] = normalized
            return
        }

        if index >= 0, index < urls.count - 1 {
            urls.removeSubrange((index + 1)..<urls.count)
        } else if index < 0 {
            urls = []
        }

        urls.append(normalized)
        index = urls.count - 1
        trimIfNeeded()
    }

    @discardableResult
    func goBack() -> URL? {
        guard canGoBack else { return nil }
        index -= 1
        suppressNextRecord = true
        return currentURL
    }

    @discardableResult
    func goForward() -> URL? {
        guard canGoForward else { return nil }
        index += 1
        suppressNextRecord = true
        return currentURL
    }

    private func trimIfNeeded() {
        guard urls.count > Self.maxEntries else { return }
        let drop = urls.count - Self.maxEntries
        urls.removeFirst(drop)
        index = max(0, index - drop)
    }

    private static func normalize(_ url: URL) -> String? {
        guard isPersistable(url.absoluteString) else { return nil }
        return url.absoluteString
    }

    private static func isPersistable(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        let lower = s.lowercased()
        if lower.hasPrefix("about:") { return false }
        if lower == "about:blank" { return false }
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    private static func equalIgnoringFragment(_ a: String, _ b: String) -> Bool {
        guard var ca = URLComponents(string: a), var cb = URLComponents(string: b) else {
            return a == b
        }
        ca.fragment = nil
        cb.fragment = nil
        return ca.string == cb.string
    }
}
