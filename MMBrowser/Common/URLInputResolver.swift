import Foundation

enum URLInputResolver {
    static func resolve(_ raw: String) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return URL(string: SearchEngineManager.current.homeURL)!
        }

        if let url = URL(string: trimmed), let scheme = url.scheme, (scheme == "http" || scheme == "https"), url.host != nil {
            return url
        }

        let looksLikeURL = trimmed.contains(".")
            && !trimmed.contains(" ")
            && !trimmed.hasPrefix("?")

        if looksLikeURL {
            let hostPart = trimmed.hasPrefix("//") ? String(trimmed.dropFirst(2)) : trimmed
            let https = URL(string: "https://\(hostPart)")!
            if AppSettings.httpsOnly {
                return https
            }
            return https
        }

        return SearchEngineManager.current.searchURL(for: trimmed)
    }
}
