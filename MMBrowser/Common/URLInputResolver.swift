import Foundation

enum URLInputResolver {
    static func resolve(_ raw: String) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return URL(string: "https://www.google.com")!
        }

        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host != nil {
            return url
        }

        let looksLikeURL = trimmed.contains(".")
            && !trimmed.contains(" ")
            && !trimmed.hasPrefix("?")

        if looksLikeURL {
            let withScheme = trimmed.hasPrefix("//") ? "https:\(trimmed)" : "https://\(trimmed)"
            if let url = URL(string: withScheme) {
                return url
            }
        }

        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.google.com/search?q=\(query)")!
    }
}
