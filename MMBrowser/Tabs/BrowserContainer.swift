import Foundation

struct BrowserContainer: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    /// Shared `WKWebsiteDataStore(forIdentifier:)` for all normal tabs in this container.
    var sessionID: UUID
    var sortIndex: Int
    /// Index into `AccountColor.palette` when `customColorHex` is nil.
    var colorIndex: Int
    /// Optional `#RRGGBB` override; when set, wins over `colorIndex`.
    var customColorHex: String?
    /// Per-container Geolocation API behavior for sites in this container.
    var locationMode: LocationPrivacyMode
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String
    var locationPresetID: String?
    /// Quick-launch sites shown on the account home row and account switcher.
    var pinnedSites: [NavigationSite]
    /// Persistent vs auto-delete when last tab closes.
    var persistence: ContainerPersistence
    /// Locale, user agent, and URL tracking settings for this account.
    var identity: IdentityProfile
    /// Template used when creating this account (`work`, `social`, etc.).
    var templateID: String?

    var locationSummary: String {
        switch locationMode {
        case .deny: return "Deny"
        case .ask: return "Ask"
        case .spoof:
            if let presetID = locationPresetID,
               let preset = SpoofLocationPreset.all.first(where: { $0.id == presetID }) {
                return preset.name
            }
            if let preset = SpoofLocationPreset.all.first(where: {
                abs($0.latitude - latitude) < 0.0001 && abs($0.longitude - longitude) < 0.0001
            }) {
                return preset.name
            }
            return String(format: "%.2f, %.2f", latitude, longitude)
        }
    }

    static func makeDefaults() -> [BrowserContainer] {
        let personal = ContainerTemplate.custom.makeContainer(
            name: "Personal",
            sortIndex: 0,
            colorIndex: 0
        ).with {
            $0.locationMode = .ask
            $0.identity = .default
            $0.pinnedSites = ContainerTemplate.defaultPinned(forName: "Personal")
        }
        // Work uses the work template (desktop UA, ask location).
        let work = ContainerTemplate.work.makeContainer(
            name: "Work",
            sortIndex: 1,
            colorIndex: 1
        )
        return [personal, work]
    }

    private func with(_ mutate: (inout BrowserContainer) -> Void) -> BrowserContainer {
        var copy = self
        mutate(&copy)
        return copy
    }

    init(
        id: UUID,
        name: String,
        sessionID: UUID,
        sortIndex: Int,
        colorIndex: Int? = nil,
        customColorHex: String? = nil,
        locationMode: LocationPrivacyMode = .spoof,
        latitude: Double,
        longitude: Double,
        timeZoneIdentifier: String,
        locationPresetID: String? = nil,
        pinnedSites: [NavigationSite] = [],
        persistence: ContainerPersistence = .persistent,
        identity: IdentityProfile = .default,
        templateID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sessionID = sessionID
        self.sortIndex = sortIndex
        self.colorIndex = colorIndex ?? sortIndex
        self.customColorHex = customColorHex
        self.locationMode = locationMode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.locationPresetID = locationPresetID
        self.pinnedSites = pinnedSites
        self.persistence = persistence
        self.identity = identity
        self.templateID = templateID
    }

    init(id: UUID, name: String, sessionID: UUID, sortIndex: Int, colorIndex: Int? = nil, customColorHex: String? = nil, location preset: SpoofLocationPreset, pinnedSites: [NavigationSite] = [], persistence: ContainerPersistence = .persistent, identity: IdentityProfile = .default, templateID: String? = nil) {
        self.init(
            id: id,
            name: name,
            sessionID: sessionID,
            sortIndex: sortIndex,
            colorIndex: colorIndex ?? sortIndex,
            customColorHex: customColorHex,
            locationMode: .spoof,
            latitude: preset.latitude,
            longitude: preset.longitude,
            timeZoneIdentifier: preset.timeZoneIdentifier,
            locationPresetID: preset.id,
            pinnedSites: pinnedSites,
            persistence: persistence,
            identity: identity,
            templateID: templateID
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sessionID, sortIndex, colorIndex, customColorHex
        case locationMode, latitude, longitude, timeZoneIdentifier, locationPresetID
        case pinnedSites, persistence, identity, templateID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        sortIndex = try c.decode(Int.self, forKey: .sortIndex)
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? sortIndex
        customColorHex = try c.decodeIfPresent(String.self, forKey: .customColorHex)

        let fallback = SpoofLocationPreset.all[0]
        if let raw = try c.decodeIfPresent(String.self, forKey: .locationMode),
           let mode = LocationPrivacyMode(rawValue: raw) {
            locationMode = mode
        } else {
            locationMode = .spoof
        }
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? fallback.latitude
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? fallback.longitude
        timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? fallback.timeZoneIdentifier
        locationPresetID = try c.decodeIfPresent(String.self, forKey: .locationPresetID)
        pinnedSites = try c.decodeIfPresent([NavigationSite].self, forKey: .pinnedSites) ?? []
        persistence = try c.decodeIfPresent(ContainerPersistence.self, forKey: .persistence) ?? .persistent
        identity = try c.decodeIfPresent(IdentityProfile.self, forKey: .identity) ?? .default
        templateID = try c.decodeIfPresent(String.self, forKey: .templateID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(sortIndex, forKey: .sortIndex)
        try c.encode(colorIndex, forKey: .colorIndex)
        try c.encodeIfPresent(customColorHex, forKey: .customColorHex)
        try c.encode(locationMode.rawValue, forKey: .locationMode)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try c.encodeIfPresent(locationPresetID, forKey: .locationPresetID)
        try c.encode(pinnedSites, forKey: .pinnedSites)
        try c.encode(persistence, forKey: .persistence)
        try c.encode(identity, forKey: .identity)
        try c.encodeIfPresent(templateID, forKey: .templateID)
    }
}
