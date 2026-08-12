import Foundation

enum URLTrackingCleaner {
    private static let stripKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gbraid", "wbraid", "mc_eid", "igshid", "si"
    ]

    static func cleaned(_ url: URL, enabled: Bool) -> URL {
        guard enabled,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              !items.isEmpty else { return url }

        let filtered = items.filter { !stripKeys.contains($0.name.lowercased()) }
        if filtered.count == items.count { return url }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }
}
