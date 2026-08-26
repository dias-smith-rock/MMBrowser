import Foundation

enum URLTrackingCleaner {
    private static let stripKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gbraid", "wbraid", "mc_eid", "igshid", "si"
    ]

    static func cleaned(_ url: URL, enabled: Bool) -> URL {
        cleanedWithCount(url, enabled: enabled).url
    }

    static func cleanedWithCount(_ url: URL, enabled: Bool) -> (url: URL, strippedCount: Int) {
        guard enabled,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              !items.isEmpty else { return (url, 0) }

        let filtered = items.filter { !stripKeys.contains($0.name.lowercased()) }
        let stripped = items.count - filtered.count
        guard stripped > 0 else { return (url, 0) }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return (components.url ?? url, stripped)
    }
}
