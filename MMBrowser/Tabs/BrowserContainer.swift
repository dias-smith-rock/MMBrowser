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
        let presets = SpoofLocationPreset.all
        let names = ["Personal", "Work", "Social 1", "Social 2"]
        // Personal → Ask; others Spoof with rotating cities.
        return names.enumerated().map { offset, name in
            let preset = presets[offset % presets.count]
            if offset == 0 {
                return BrowserContainer(
                    id: UUID(),
                    name: name,
                    sessionID: UUID(),
                    sortIndex: offset,
                    colorIndex: offset,
                    locationMode: .ask,
                    latitude: preset.latitude,
                    longitude: preset.longitude,
                    timeZoneIdentifier: preset.timeZoneIdentifier,
                    locationPresetID: preset.id
                )
            }
            return BrowserContainer(
                id: UUID(),
                name: name,
                sessionID: UUID(),
                sortIndex: offset,
                colorIndex: offset,
                location: preset
            )
        }
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
        locationPresetID: String? = nil
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
    }

    init(id: UUID, name: String, sessionID: UUID, sortIndex: Int, colorIndex: Int? = nil, customColorHex: String? = nil, location preset: SpoofLocationPreset) {
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
            locationPresetID: preset.id
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sessionID, sortIndex, colorIndex, customColorHex
        case locationMode, latitude, longitude, timeZoneIdentifier, locationPresetID
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
    }
}
