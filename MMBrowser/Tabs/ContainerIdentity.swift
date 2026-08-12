import Foundation

/// Account data always persists until the account is deleted.
enum ContainerPersistence: String, Codable, CaseIterable {
    case persistent

    var displayName: String { "Persistent" }

    var detail: String {
        "Keeps cookies and data until you delete this account."
    }

    init(from decoder: Decoder) throws {
        // Accept legacy "ephemeral" (and any unknown) as persistent.
        _ = try decoder.singleValueContainer().decode(String.self)
        self = .persistent
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Self.persistent.rawValue)
    }
}

enum UserAgentMode: String, Codable, CaseIterable {
    case automatic
    case mobile
    case desktop
    case custom

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .mobile: return "Mobile"
        case .desktop: return "Desktop"
        case .custom: return "Custom"
        }
    }
}

struct IdentityProfile: Codable, Equatable {
    var localeIdentifier: String?
    var userAgentMode: UserAgentMode
    var customUserAgent: String?
    var stripTrackingParams: Bool

    static let `default` = IdentityProfile(
        localeIdentifier: nil,
        userAgentMode: .automatic,
        customUserAgent: nil,
        stripTrackingParams: true
    )

    static func suggestedLocale(for preset: SpoofLocationPreset) -> String {
        switch preset.id {
        case "nyc", "la": return "en-US"
        case "london": return "en-GB"
        case "paris": return "fr-FR"
        case "berlin": return "de-DE"
        case "tokyo": return "ja-JP"
        case "singapore": return "en-SG"
        case "sydney": return "en-AU"
        default: return "en-US"
        }
    }
}

enum ContainerTemplate: String, CaseIterable {
    case work
    case social
    case custom

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .social: return "Social"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .work: return "Desktop sites, ask for location, persistent session."
        case .social: return "Mobile sites, optional location spoof, Shorts-friendly."
        case .custom: return "Configure everything yourself."
        }
    }

    func makeContainer(name: String, sortIndex: Int, colorIndex: Int) -> BrowserContainer {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? displayName : trimmed
        let preset = SpoofLocationPreset.all[sortIndex % SpoofLocationPreset.all.count]

        switch self {
        case .work:
            return BrowserContainer(
                id: UUID(),
                name: displayName,
                sessionID: UUID(),
                sortIndex: sortIndex,
                colorIndex: colorIndex,
                locationMode: .ask,
                latitude: preset.latitude,
                longitude: preset.longitude,
                timeZoneIdentifier: preset.timeZoneIdentifier,
                locationPresetID: preset.id,
                pinnedSites: Self.workPinnedSites,
                persistence: .persistent,
                identity: IdentityProfile(
                    localeIdentifier: "en-US",
                    userAgentMode: .desktop,
                    customUserAgent: nil,
                    stripTrackingParams: true
                ),
                templateID: rawValue
            )
        case .social:
            return BrowserContainer(
                id: UUID(),
                name: displayName,
                sessionID: UUID(),
                sortIndex: sortIndex,
                colorIndex: colorIndex,
                location: preset,
                pinnedSites: Self.socialPinnedSites,
                persistence: .persistent,
                identity: IdentityProfile(
                    localeIdentifier: IdentityProfile.suggestedLocale(for: preset),
                    userAgentMode: .mobile,
                    customUserAgent: nil,
                    stripTrackingParams: true
                ),
                templateID: rawValue
            )
        case .custom:
            return BrowserContainer(
                id: UUID(),
                name: displayName,
                sessionID: UUID(),
                sortIndex: sortIndex,
                colorIndex: colorIndex,
                locationMode: .ask,
                latitude: preset.latitude,
                longitude: preset.longitude,
                timeZoneIdentifier: preset.timeZoneIdentifier,
                locationPresetID: preset.id,
                pinnedSites: [],
                persistence: .persistent,
                identity: .default,
                templateID: rawValue
            )
        }
    }

    static func defaultPinned(forName name: String) -> [NavigationSite] {
        let key = name.lowercased()
        if key.contains("work") { return workPinnedSites }
        if key.contains("social") { return socialPinnedSites }
        return []
    }

    private static let workPinnedSites: [NavigationSite] = [
        NavigationSite(title: "Gmail", urlString: "https://mail.google.com", logoAssetName: nil),
        NavigationSite(title: "Google", urlString: "https://www.google.com", logoAssetName: "nav_google"),
        NavigationSite(title: "LinkedIn", urlString: "https://www.linkedin.com", logoAssetName: "nav_linkedin")
    ]

    private static let socialPinnedSites: [NavigationSite] = [
        NavigationSite(title: "X", urlString: "https://x.com", logoAssetName: "nav_x"),
        NavigationSite(title: "Instagram", urlString: "https://www.instagram.com", logoAssetName: "nav_instagram"),
        NavigationSite(title: "YouTube", urlString: "https://www.youtube.com", logoAssetName: "nav_youtube")
    ]
}
