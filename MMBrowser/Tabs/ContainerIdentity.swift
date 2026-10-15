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
            case .automatic: return "Default"
            case .mobile: return "Phone"
            case .desktop: return "Computer"
            case .custom: return "Custom"
        }
    }
}

/// Per-tab user agent; account identity only seeds defaults for newly created tabs.
struct TabUserAgentSettings: Equatable, Codable {
    var userAgentMode: UserAgentMode
    var customUserAgent: String?
    var customProfile: CustomUserAgentProfile?

    static let incognitoToolbarDefault = TabUserAgentSettings(userAgentMode: .mobile, customUserAgent: nil)

    static func defaultForNewTab(in container: BrowserContainer) -> TabUserAgentSettings {
        var profile = container.identity.customProfile
        var customUA = container.identity.customUserAgent
        if container.identity.userAgentMode == .custom, profile == nil {
            profile = .default
            customUA = CustomUserAgentProfile.default.userAgentString
        }
        return TabUserAgentSettings(
            userAgentMode: container.identity.userAgentMode,
            customUserAgent: customUA,
            customProfile: profile
        )
    }

    init(userAgentMode: UserAgentMode, customUserAgent: String?, customProfile: CustomUserAgentProfile? = nil) {
        self.userAgentMode = userAgentMode
        self.customUserAgent = customUserAgent
        self.customProfile = customProfile
    }

    var looksLikeComputer: Bool {
        switch userAgentMode {
        case .desktop:
            return true
        case .custom:
            return customProfile?.isMobile == false
        case .automatic, .mobile:
            return false
        }
    }

    init(from identity: IdentityProfile) {
        self.init(
            userAgentMode: identity.userAgentMode,
            customUserAgent: identity.customUserAgent,
            customProfile: identity.customProfile
        )
    }

    func copying(from source: TabUserAgentSettings) -> TabUserAgentSettings {
        TabUserAgentSettings(
            userAgentMode: source.userAgentMode,
            customUserAgent: source.customUserAgent,
            customProfile: source.customProfile
        )
    }

    /// Migrates legacy `preferDesktop` toggles from persisted sessions.
    static func migrated(preferDesktop: Bool) -> TabUserAgentSettings {
        TabUserAgentSettings(
            userAgentMode: preferDesktop ? .desktop : .automatic,
            customUserAgent: nil
        )
    }
}

struct IdentityProfile: Codable, Equatable {
    var localeIdentifier: String?
    var userAgentMode: UserAgentMode
    var customUserAgent: String?
    var customProfile: CustomUserAgentProfile?
    var stripTrackingParams: Bool

    static let `default` = IdentityProfile(
        localeIdentifier: nil,
        userAgentMode: .mobile,
        customUserAgent: nil,
        customProfile: nil,
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
    case whatsapp
    case instagram
    case telegram
    case facebook
    case shop
    case work
    case custom

    /// One-tap presets on the Accounts sheet.
    static let quickAddTemplates: [ContainerTemplate] = [
        .whatsapp, .instagram, .telegram, .facebook
    ]

    var displayName: String {
        switch self {
        case .whatsapp: return "WhatsApp"
        case .instagram: return "Instagram"
        case .telegram: return "Telegram"
        case .facebook: return "Facebook"
        case .shop: return "Shop"
        case .work: return "Work"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .whatsapp: return "WhatsApp Web session with its own cookies."
        case .instagram: return "Instagram web login isolated from other accounts."
        case .telegram: return "Telegram Web session that won’t mix with others."
        case .facebook: return "Facebook web login in a dedicated identity."
        case .shop: return "Separate storefront or seller logins."
        case .work: return "Desktop sites for email and docs."
        case .custom: return "Configure everything yourself."
        }
    }

    var suggestedName: String { displayName }

    /// Site to open after a one-tap create (web version).
    var homeURL: URL? {
        switch self {
        case .whatsapp: return URL(string: "https://web.whatsapp.com")
        case .instagram: return URL(string: "https://www.instagram.com")
        case .telegram: return URL(string: "https://web.telegram.org")
        case .facebook: return URL(string: "https://www.facebook.com")
        case .shop, .work, .custom: return nil
        }
    }

    var quickAddTag: Int {
        switch self {
        case .whatsapp: return 1
        case .instagram: return 2
        case .telegram: return 3
        case .facebook: return 4
        case .shop: return 5
        case .work: return 6
        case .custom: return 0
        }
    }

    static func fromQuickAddTag(_ tag: Int) -> ContainerTemplate? {
        quickAddTemplates.first { $0.quickAddTag == tag }
    }

    func makeContainer(name: String, sortIndex: Int, colorIndex: Int) -> BrowserContainer {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? suggestedName : trimmed
        let preset = SpoofLocationPreset.all[sortIndex % SpoofLocationPreset.all.count]

        switch self {
        case .whatsapp:
            // WhatsApp Web requires a Computer UA for the real web client (QR login).
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
                identity: IdentityProfile(
                    localeIdentifier: "en-US",
                    userAgentMode: .desktop,
                    customUserAgent: nil,
                    customProfile: nil,
                    stripTrackingParams: true
                ),
                templateID: rawValue
            )
        case .instagram, .telegram, .facebook:
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
                identity: IdentityProfile(
                    localeIdentifier: "en-US",
                    userAgentMode: .mobile,
                    customUserAgent: nil,
                    customProfile: nil,
                    stripTrackingParams: true
                ),
                templateID: rawValue
            )
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
                pinnedSites: [],
                persistence: .persistent,
                identity: IdentityProfile(
                    localeIdentifier: "en-US",
                    userAgentMode: .mobile,
                    customUserAgent: nil,
                    customProfile: nil,
                    stripTrackingParams: true
                ),
                templateID: rawValue
            )
        case .shop:
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
                identity: IdentityProfile(
                    localeIdentifier: "en-US",
                    userAgentMode: .mobile,
                    customUserAgent: nil,
                    customProfile: nil,
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

    /// Homepage cards live in `NavigationDirectory` so every account shares one grid (no pinned row).
    static func defaultPinned(forName name: String) -> [NavigationSite] {
        _ = name
        return []
    }

    static func defaultPinned(forTemplateID templateID: String?) -> [NavigationSite] {
        _ = templateID
        return []
    }
}
