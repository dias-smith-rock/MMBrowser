import Foundation
import FirebaseRemoteConfig

/// Fetches and caches Remote Config used by ads and feature flags.
final class RemoteConfigManager {
    static let shared = RemoteConfigManager()

    enum Key: String {
        case adsEnabled = "ads_enabled"
        case appOpenAdUnitID = "admob_app_open_unit_id"
        case interstitialAdUnitID = "admob_interstitial_unit_id"
        case coldStartAdsEnabled = "cold_start_ads_enabled"
        case hotStartAdsEnabled = "hot_start_ads_enabled"
    }

    private let remoteConfig = RemoteConfig.remoteConfig()
    private var didStart = false

    private init() {}

    func start() {
        guard !didStart else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        didStart = true

        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0
        #else
        settings.minimumFetchInterval = 12 * 60 * 60
        #endif
        remoteConfig.configSettings = settings

        remoteConfig.setDefaults([
            Key.adsEnabled.rawValue: NSNumber(value: true),
            Key.appOpenAdUnitID.rawValue: NSString(string: ""),
            Key.interstitialAdUnitID.rawValue: NSString(string: ""),
            Key.coldStartAdsEnabled.rawValue: NSNumber(value: true),
            Key.hotStartAdsEnabled.rawValue: NSNumber(value: true)
        ] as [String: NSObject])

        fetchAndActivate()
    }

    func fetchAndActivate() {
        guard didStart else { return }
        remoteConfig.fetchAndActivate { status, error in
            #if DEBUG
            if let error {
                print("[RemoteConfig] fetch error: \(error.localizedDescription)")
            } else {
                print("[RemoteConfig] fetch status: \(status.rawValue)")
            }
            #endif
            NotificationCenter.default.post(name: .remoteConfigDidUpdate, object: nil)
        }
    }

    var isAdsEnabled: Bool {
        boolValue(for: .adsEnabled, default: true)
    }

    var isColdStartAdsEnabled: Bool {
        boolValue(for: .coldStartAdsEnabled, default: true)
    }

    var isHotStartAdsEnabled: Bool {
        boolValue(for: .hotStartAdsEnabled, default: true)
    }

    func stringValue(for key: Key, default defaultValue: String = "") -> String {
        let value = remoteConfig.configValue(forKey: key.rawValue).stringValue ?? ""
        return value.isEmpty ? defaultValue : value
    }

    func boolValue(for key: Key, default defaultValue: Bool) -> Bool {
        let raw = remoteConfig.configValue(forKey: key.rawValue)
        // Unset keys fall back to defaults set above.
        if raw.source == .static {
            return defaultValue
        }
        return raw.boolValue
    }
}

extension Notification.Name {
    static let remoteConfigDidUpdate = Notification.Name("mmbrowser.remoteConfigDidUpdate")
}
