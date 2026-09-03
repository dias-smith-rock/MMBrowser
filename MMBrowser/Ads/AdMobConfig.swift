import Foundation

/// AdMob app / unit IDs and feature gates.
/// Replace production unit IDs in Release (or override via Firebase Remote Config).
enum AdMobConfig {
    /// Sample AdMob App ID — replace with your real App ID in Info.plist (`GADApplicationIdentifier`).
    static let sampleAppID = "ca-app-pub-3940256099942544~1458002511"

    /// New installs see no ads for this many days from first launch.
    static let newUserAdFreeDays = 3

    /// `true` while within the new-user ad-free window.
    static var isInNewUserAdFreePeriod: Bool {
        let elapsed = Date().timeIntervalSince(AppSettings.firstLaunchDate)
        return elapsed < TimeInterval(newUserAdFreeDays * 24 * 60 * 60)
    }

    #if DEBUG
    /// Debug builds never load ads unless you explicitly opt in.
    /// Set UserDefaults `mmbrowser.debug.forceAds` = `true` to test with Google sample units.
    static var adsEnabled: Bool {
        UserDefaults.standard.bool(forKey: "mmbrowser.debug.forceAds")
    }

    static var appOpenAdUnitID: String {
        "ca-app-pub-3940256099942544/5575463023"
    }

    static var interstitialAdUnitID: String {
        "ca-app-pub-3940256099942544/4411468910"
    }
    #else
    static var adsEnabled: Bool {
        if isInNewUserAdFreePeriod { return false }
        return RemoteConfigManager.shared.isAdsEnabled
    }

    static var appOpenAdUnitID: String {
        let remote = RemoteConfigManager.shared.stringValue(for: .appOpenAdUnitID)
        return remote.isEmpty ? "ca-app-pub-XXXXXXXXXXXXXXXX/AAAAAAAAAA" : remote
    }

    static var interstitialAdUnitID: String {
        let remote = RemoteConfigManager.shared.stringValue(for: .interstitialAdUnitID)
        return remote.isEmpty ? "ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB" : remote
    }
    #endif

    static var coldStartEnabled: Bool {
        #if DEBUG
        adsEnabled
        #else
        RemoteConfigManager.shared.isColdStartAdsEnabled
        #endif
    }

    static var hotStartEnabled: Bool {
        #if DEBUG
        adsEnabled
        #else
        RemoteConfigManager.shared.isHotStartAdsEnabled
        #endif
    }

    static let appOpenAdTimeout: TimeInterval = 4 * 60 * 60
    static let presentationRetryDelayMs = 300
    static let maxPresentationRetries = 3
}
