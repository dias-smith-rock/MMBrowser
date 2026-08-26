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
        case .whatsapp, .instagram, .telegram, .facebook:
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
                pinnedSites: messagingPinnedSites,
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
                pinnedSites: Self.workPinnedSites,
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
                pinnedSites: Self.shopPinnedSites,
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

    private var messagingPinnedSites: [NavigationSite] {
        switch self {
        case .whatsapp:
            return Self.messagingSuitePinnedSites(primaryTitle: "WhatsApp", primaryURL: "https://web.whatsapp.com")
        case .instagram:
            return Self.messagingSuitePinnedSites(primaryTitle: "Instagram", primaryURL: "https://www.instagram.com", primaryLogo: "nav_instagram")
        case .telegram:
            return Self.messagingSuitePinnedSites(primaryTitle: "Telegram", primaryURL: "https://web.telegram.org")
        case .facebook:
            return Self.messagingSuitePinnedSites(primaryTitle: "Facebook", primaryURL: "https://www.facebook.com", primaryLogo: "nav_facebook")
        default:
            return []
        }
    }

    /// Related messaging / social destinations (≥6), with the template’s primary site first.
    private static func messagingSuitePinnedSites(
        primaryTitle: String,
        primaryURL: String,
        primaryLogo: String? = nil
    ) -> [NavigationSite] {
        var sites = [
            NavigationSite(title: primaryTitle, urlString: primaryURL, logoAssetName: primaryLogo)
        ]
        let extras: [NavigationSite] = [
            NavigationSite(title: "WhatsApp", urlString: "https://web.whatsapp.com"),
            NavigationSite(title: "Instagram", urlString: "https://www.instagram.com", logoAssetName: "nav_instagram"),
            NavigationSite(title: "Facebook", urlString: "https://www.facebook.com", logoAssetName: "nav_facebook"),
            NavigationSite(title: "Messenger", urlString: "https://www.messenger.com"),
            NavigationSite(title: "Telegram", urlString: "https://web.telegram.org"),
            NavigationSite(title: "X", urlString: "https://x.com", logoAssetName: "nav_x"),
            NavigationSite(title: "LinkedIn", urlString: "https://www.linkedin.com", logoAssetName: "nav_linkedin")
        ]
        for site in extras where site.urlString != primaryURL {
            sites.append(site)
            if sites.count >= 6 { break }
        }
        return sites
    }

    static func defaultPinned(forName name: String) -> [NavigationSite] {
        let key = name.lowercased()
        if key.contains("work") { return workPinnedSites }
        if key.contains("shop") || key.contains("store") { return shopPinnedSites }
        if key.contains("whatsapp") {
            return messagingSuitePinnedSites(primaryTitle: "WhatsApp", primaryURL: "https://web.whatsapp.com")
        }
        if key.contains("instagram") {
            return messagingSuitePinnedSites(
                primaryTitle: "Instagram",
                primaryURL: "https://www.instagram.com",
                primaryLogo: "nav_instagram"
            )
        }
        if key.contains("telegram") {
            return messagingSuitePinnedSites(primaryTitle: "Telegram", primaryURL: "https://web.telegram.org")
        }
        if key.contains("facebook") {
            return messagingSuitePinnedSites(
                primaryTitle: "Facebook",
                primaryURL: "https://www.facebook.com",
                primaryLogo: "nav_facebook"
            )
        }
        return []
    }

    static func defaultPinned(forTemplateID templateID: String?) -> [NavigationSite] {
        guard let templateID, let template = ContainerTemplate(rawValue: templateID) else { return [] }
        switch template {
        case .work: return workPinnedSites
        case .shop: return shopPinnedSites
        case .whatsapp, .instagram, .telegram, .facebook:
            return template.messagingPinnedSites
        case .custom:
            return []
        }
    }

    private static let workPinnedSites: [NavigationSite] = [
        NavigationSite(title: "Gmail", urlString: "https://mail.google.com"),
        NavigationSite(title: "Drive", urlString: "https://drive.google.com"),
        NavigationSite(title: "Docs", urlString: "https://docs.google.com"),
        NavigationSite(title: "Calendar", urlString: "https://calendar.google.com"),
        NavigationSite(title: "LinkedIn", urlString: "https://www.linkedin.com", logoAssetName: "nav_linkedin"),
        NavigationSite(title: "Outlook", urlString: "https://outlook.office.com"),
        NavigationSite(title: "Slack", urlString: "https://app.slack.com"),
        NavigationSite(title: "Notion", urlString: "https://www.notion.so")
    ]

    private static let shopPinnedSites: [NavigationSite] = [
        NavigationSite(title: "Shopify", urlString: "https://www.shopify.com"),
        NavigationSite(title: "Etsy", urlString: "https://www.etsy.com"),
        NavigationSite(title: "Amazon", urlString: "https://sellercentral.amazon.com"),
        NavigationSite(title: "eBay", urlString: "https://www.ebay.com/sh/landing"),
        NavigationSite(title: "PayPal", urlString: "https://www.paypal.com"),
        NavigationSite(title: "Woo", urlString: "https://woocommerce.com")
    ]
}
