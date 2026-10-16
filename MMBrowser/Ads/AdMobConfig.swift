import Foundation

/// AdMob app / unit IDs and feature gates.
/// Debug and Release share the same gates and Remote Config unit IDs.
enum AdMobConfig {
    /// New installs see no ads for this many days from first launch.
    static let newUserAdFreeDays = 3

    /// `true` while within the new-user ad-free window.
    static var isInNewUserAdFreePeriod: Bool {
        let elapsed = Date().timeIntervalSince(AppSettings.firstLaunchDate)
        return elapsed < TimeInterval(newUserAdFreeDays * 24 * 60 * 60)
    }

    static var adsEnabled: Bool {
        if isInNewUserAdFreePeriod { return false }
        return RemoteConfigManager.shared.isAdsEnabled
    }

    static var appOpenAdUnitID: String {
        RemoteConfigManager.shared.stringValue(for: .appOpenAdUnitID)
    }

    static var interstitialAdUnitID: String {
        RemoteConfigManager.shared.stringValue(for: .interstitialAdUnitID)
    }

    static var coldStartEnabled: Bool {
        RemoteConfigManager.shared.isColdStartAdsEnabled
    }

    static var hotStartEnabled: Bool {
        RemoteConfigManager.shared.isHotStartAdsEnabled
    }

    static let appOpenAdTimeout: TimeInterval = 4 * 60 * 60
    static let presentationRetryDelayMs = 300
    static let maxPresentationRetries = 3
}
