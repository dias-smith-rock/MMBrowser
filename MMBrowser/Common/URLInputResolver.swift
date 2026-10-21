import Foundation

enum URLInputResolver {
    enum Kind {
        case emptyHome
        case url
        case search
    }

    struct Resolved {
        let url: URL
        let kind: Kind
    }

    static func resolve(_ raw: String) -> URL {
        classify(raw).url
    }

    static func classify(_ raw: String) -> Resolved {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let home = URL(string: SearchEngineManager.current.homeURL)
                ?? URL(string: "https://www.google.com")!
            return Resolved(url: home, kind: .emptyHome)
        }

        if let url = URL(string: trimmed), let scheme = url.scheme, (scheme == "http" || scheme == "https"), url.host != nil {
            return Resolved(url: url, kind: .url)
        }

        let looksLikeURL = trimmed.contains(".")
            && !trimmed.contains(" ")
            && !trimmed.hasPrefix("?")

        if looksLikeURL {
            let hostPart = trimmed.hasPrefix("//") ? String(trimmed.dropFirst(2)) : trimmed
            let https = URL(string: "https://\(hostPart)")
                ?? URL(string: "https://www.google.com")!
            return Resolved(url: https, kind: .url)
        }

        return Resolved(
            url: SearchEngineManager.current.searchURL(for: trimmed),
            kind: .search
        )
    }
}
