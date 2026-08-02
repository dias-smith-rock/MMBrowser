import Foundation

struct BrowserContainer: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    /// Shared `WKWebsiteDataStore(forIdentifier:)` for all normal tabs in this container.
    var sessionID: UUID
    var sortIndex: Int
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
        let defaultPreset = presets[0] // New York
        let workPreset = presets.first(where: { $0.id == "london" }) ?? presets[2]
        let personalPreset = presets.first(where: { $0.id == "tokyo" }) ?? presets[5]
        return [
            BrowserContainer(
                id: UUID(),
                name: "Default",
                sessionID: UUID(),
                sortIndex: 0,
                location: defaultPreset
            ),
            BrowserContainer(
                id: UUID(),
                name: "Work",
                sessionID: UUID(),
                sortIndex: 1,
                location: workPreset
            ),
            BrowserContainer(
                id: UUID(),
                name: "Personal",
                sessionID: UUID(),
                sortIndex: 2,
                location: personalPreset
            )
        ]
    }

    init(
        id: UUID,
        name: String,
        sessionID: UUID,
        sortIndex: Int,
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
        self.locationMode = locationMode
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.locationPresetID = locationPresetID
    }

    init(id: UUID, name: String, sessionID: UUID, sortIndex: Int, location preset: SpoofLocationPreset) {
        self.init(
            id: id,
            name: name,
            sessionID: sessionID,
            sortIndex: sortIndex,
            locationMode: .spoof,
            latitude: preset.latitude,
            longitude: preset.longitude,
            timeZoneIdentifier: preset.timeZoneIdentifier,
            locationPresetID: preset.id
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, sessionID, sortIndex
        case locationMode, latitude, longitude, timeZoneIdentifier, locationPresetID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        sortIndex = try c.decode(Int.self, forKey: .sortIndex)

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
        try c.encode(locationMode.rawValue, forKey: .locationMode)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try c.encodeIfPresent(locationPresetID, forKey: .locationPresetID)
    }
}
