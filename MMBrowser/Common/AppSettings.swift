import Foundation
import UIKit

/// Gate for “set as default browser”.
/// Requires Apple-approved `com.apple.developer.web-browser` in entitlements + provisioning.
enum DefaultBrowserFeature {
    static let isEnabled = true
}

enum AppSettings {
    private static let d = UserDefaults.standard

    static var trackerProtectionEnabled: Bool {
        get { d.object(forKey: "tp.enabled") == nil ? true : d.bool(forKey: "tp.enabled") }
        set { d.set(newValue, forKey: "tp.enabled"); NotificationCenter.default.post(name: .trackerProtectionChanged, object: nil) }
    }

    /// When true, inject a DOM counter for the address-bar shield badge. Default off (CPU-heavy).
    static var accurateBlockCountEnabled: Bool {
        get { d.bool(forKey: "tp.accurateBlockCount") }
        set {
            d.set(newValue, forKey: "tp.accurateBlockCount")
            NotificationCenter.default.post(name: .accurateBlockCountChanged, object: nil)
        }
    }

    static var hideShortsEnabled: Bool {
        get { d.object(forKey: "shorts.hide") == nil ? true : d.bool(forKey: "shorts.hide") }
        set {
            d.set(newValue, forKey: "shorts.hide")
            NotificationCenter.default.post(name: .shortsFocusChanged, object: nil)
        }
    }

    static var youtubeAdShieldEnabled: Bool {
        get { d.object(forKey: "yt.adshield") == nil ? true : d.bool(forKey: "yt.adshield") }
        set {
            d.set(newValue, forKey: "yt.adshield")
            NotificationCenter.default.post(name: .youtubeAdShieldChanged, object: nil)
        }
    }

    static var backgroundAudioEnabled: Bool {
        get { d.object(forKey: "media.bgAudio") == nil ? true : d.bool(forKey: "media.bgAudio") }
        set {
            d.set(newValue, forKey: "media.bgAudio")
            NotificationCenter.default.post(name: .mediaPlaybackSettingsChanged, object: nil)
        }
    }

    static var pictureInPictureEnabled: Bool {
        get { d.object(forKey: "media.pip") == nil ? true : d.bool(forKey: "media.pip") }
        set {
            d.set(newValue, forKey: "media.pip")
            if !newValue { stickyPictureInPicture = false }
            NotificationCenter.default.post(name: .mediaPlaybackSettingsChanged, object: nil)
        }
    }

    /// When true, newly loaded pages with video should auto-enter Picture in Picture.
    static var stickyPictureInPicture: Bool {
        get { d.bool(forKey: "media.pip.sticky") }
        set { d.set(newValue, forKey: "media.pip.sticky") }
    }

    /// Default on — Zero-trust-inspired isolation prefers HTTPS-only navigation.
    static var httpsOnly: Bool {
        get { d.object(forKey: "https.only") == nil ? true : d.bool(forKey: "https.only") }
        set { d.set(newValue, forKey: "https.only") }
    }

    /// Sec-GPC / navigator.globalPrivacyControl. Default on for new installs.
    static var globalPrivacyControlEnabled: Bool {
        get { d.object(forKey: "gpc.enabled") == nil ? true : d.bool(forKey: "gpc.enabled") }
        set {
            d.set(newValue, forKey: "gpc.enabled")
            NotificationCenter.default.post(name: .globalPrivacyControlChanged, object: nil)
        }
    }

    static var noImagesEnabled: Bool {
        get { d.bool(forKey: "no.images.enabled") }
        set {
            d.set(newValue, forKey: "no.images.enabled")
            if !newValue { d.set(false, forKey: "no.images.aggressive") }
            NotificationCenter.default.post(name: .noImagesChanged, object: nil)
        }
    }

    /// When true, No Images script also runs in iframes (heavier). Default off = main frame only.
    static var aggressiveNoImagesEnabled: Bool {
        get { d.bool(forKey: "no.images.aggressive") }
        set {
            d.set(newValue, forKey: "no.images.aggressive")
            NotificationCenter.default.post(name: .noImagesChanged, object: nil)
        }
    }

    /// Crashlytics + Analytics. Default on, matching the previous always-on Firebase setup.
    static var shareDiagnostics: Bool {
        get { d.object(forKey: "privacy.shareDiagnostics") == nil ? true : d.bool(forKey: "privacy.shareDiagnostics") }
        set {
            d.set(newValue, forKey: "privacy.shareDiagnostics")
            NotificationCenter.default.post(name: .shareDiagnosticsChanged, object: nil)
        }
    }

    static var didShowSearchPrivacyPrompt: Bool {
        get { d.bool(forKey: "search.privacyPrompt.done") }
        set { d.set(newValue, forKey: "search.privacyPrompt.done") }
    }

    static var didShowDefaultBrowserPrompt: Bool {
        get { d.bool(forKey: "defaultBrowser.prompt.done") }
        set { d.set(newValue, forKey: "defaultBrowser.prompt.done") }
    }

    static var searchEngineID: String {
        get { d.string(forKey: "search.engine") ?? SearchEngine.youTube.id }
        set { d.set(newValue, forKey: "search.engine") }
    }

    static var homeWallpaperIndex: Int {
        get { d.integer(forKey: "home.wallpaper") }
        set { d.set(newValue, forKey: "home.wallpaper"); NotificationCenter.default.post(name: .homeSettingsChanged, object: nil) }
    }

    static var themePackID: String {
        get { d.string(forKey: "theme.pack.id") ?? "default" }
        set { d.set(newValue, forKey: "theme.pack.id") }
    }

    static var didShowOnboarding: Bool {
        get { d.bool(forKey: "onboarding.done") }
        set { d.set(newValue, forKey: "onboarding.done") }
    }

    /// First process launch time (persisted). Used for new-user ad-free window.
    static var firstLaunchDate: Date {
        if let stored = d.object(forKey: "app.firstLaunchDate") as? Date {
            return stored
        }
        let now = Date()
        // Upgrading installs: don't grant a fresh ad-free window.
        if looksLikeExistingInstall {
            let past = now.addingTimeInterval(-4 * 24 * 60 * 60)
            d.set(past, forKey: "app.firstLaunchDate")
            return past
        }
        d.set(now, forKey: "app.firstLaunchDate")
        return now
    }

    /// Records install/first-open if missing. Safe to call every launch.
    static func recordFirstLaunchIfNeeded() {
        _ = firstLaunchDate
        migrateFeatureHighlightsForPreexistingUsersIfNeeded()
    }

    /// Upgrades that already finished first-run before Highlights shipped should never see the sheet.
    /// Fresh installs still have `onboarding.done == false` here, so they remain eligible.
    private static func migrateFeatureHighlightsForPreexistingUsersIfNeeded() {
        let key = "onboarding.featureHighlights.migratedV1"
        guard d.object(forKey: key) == nil else { return }
        d.set(true, forKey: key)
        guard d.bool(forKey: "onboarding.done") else { return }
        d.set(true, forKey: "onboarding.featureHighlights.v1")
        d.set(true, forKey: "tip.adsDiscovery.done")
        d.set(true, forKey: "tip.backgroundAudio.done")
    }

    /// NTP account hero subtitle — shown for the first 7 days after install.
    static var showsNewTabAccountHeroSubtitle: Bool {
        Date().timeIntervalSince(firstLaunchDate) < 7 * 24 * 60 * 60
    }

    private static var looksLikeExistingInstall: Bool {
        d.object(forKey: "onboarding.done") != nil
            || d.object(forKey: "tp.enabled") != nil
            || d.object(forKey: "theme.pack.id") != nil
            || d.object(forKey: "tip.addressBarSwipe.done") != nil
    }

    /// One-time coach mark: swipe address bar to switch tabs.
    static var didShowAddressBarSwipeTip: Bool {
        get { d.bool(forKey: "tip.addressBarSwipe.done") }
        set { d.set(newValue, forKey: "tip.addressBarSwipe.done") }
    }

    /// One-time Feature Highlights sheet after first-run Spaces intro (**new users only**).
    static var didShowFeatureHighlights: Bool {
        get { d.bool(forKey: "onboarding.featureHighlights.v1") }
        set { d.set(newValue, forKey: "onboarding.featureHighlights.v1") }
    }

    /// Post-highlights discovery toast: ads / pop-up blocking.
    static var didShowAdsDiscoveryTip: Bool {
        get { d.bool(forKey: "tip.adsDiscovery.done") }
        set { d.set(newValue, forKey: "tip.adsDiscovery.done") }
    }

    /// Post-highlights discovery toast: background audio / lock-screen play.
    static var didShowBackgroundAudioTip: Bool {
        get { d.bool(forKey: "tip.backgroundAudio.done") }
        set { d.set(newValue, forKey: "tip.backgroundAudio.done") }
    }

    /// Default Deny — privacy browser does not expose GPS-like location unless user opts in.
    static var locationPrivacyMode: LocationPrivacyMode {
        get {
            LocationPrivacyMode(rawValue: d.string(forKey: "location.mode") ?? "") ?? .deny
        }
        set { d.set(newValue.rawValue, forKey: "location.mode") }
    }

    static var spoofPresetID: String {
        get { d.string(forKey: "location.spoof.preset") ?? SpoofLocationPreset.all[0].id }
        set { d.set(newValue, forKey: "location.spoof.preset") }
    }

    static var spoofLatitude: Double {
        get {
            if d.object(forKey: "location.spoof.lat") == nil {
                return SpoofLocationPreset.all[0].latitude
            }
            return d.double(forKey: "location.spoof.lat")
        }
        set { d.set(newValue, forKey: "location.spoof.lat") }
    }

    static var spoofLongitude: Double {
        get {
            if d.object(forKey: "location.spoof.lon") == nil {
                return SpoofLocationPreset.all[0].longitude
            }
            return d.double(forKey: "location.spoof.lon")
        }
        set { d.set(newValue, forKey: "location.spoof.lon") }
    }

    static var spoofTimeZoneIdentifier: String {
        get { d.string(forKey: "location.spoof.tz") ?? SpoofLocationPreset.all[0].timeZoneIdentifier }
        set { d.set(newValue, forKey: "location.spoof.tz") }
    }

    static var locationSummary: String {
        switch locationPrivacyMode {
        case .deny: return "Deny"
        case .ask: return "Current Location"
        case .spoof:
            if let preset = SpoofLocationPreset.all.first(where: { $0.id == spoofPresetID }) {
                return "Spoof · \(preset.name)"
            }
            return String(format: "Spoof · %.2f, %.2f", spoofLatitude, spoofLongitude)
        }
    }

    // MARK: - Clear Option (auto-clear on exit).
    // Cache, cookies, history, local storage, and close-tabs default on. Turn a switch off to keep that data.

    private static func setClearOption(_ value: Bool, forKey key: String) {
        d.set(value, forKey: key)
        // Ensure the choice survives force-quit / crash immediately after toggling.
        d.synchronize()
        NotificationCenter.default.post(name: .clearOptionSettingsChanged, object: nil)
    }

    /// Default on — caches are wiped when leaving the app.
    static var autoClearCache: Bool {
        get { d.object(forKey: "clear.auto.cache") == nil ? true : d.bool(forKey: "clear.auto.cache") }
        set { setClearOption(newValue, forKey: "clear.auto.cache") }
    }

    /// Default on — cookies clear on every leave, so sites ask you to sign in again.
    static var autoClearCookies: Bool {
        get { d.object(forKey: "clear.auto.cookies") == nil ? true : d.bool(forKey: "clear.auto.cookies") }
        set { setClearOption(newValue, forKey: "clear.auto.cookies") }
    }

    /// When true, browsing history is cleared when leaving the app / on next launch.
    /// History is still recorded during the current session. Default on.
    static var autoClearHistory: Bool {
        get { d.object(forKey: "clear.auto.history") == nil ? true : d.bool(forKey: "clear.auto.history") }
        set { setClearOption(newValue, forKey: "clear.auto.history") }
    }

    /// Default on. WhatsApp Web and many sites keep sessions in IndexedDB / localStorage.
    static var autoClearLocalStorage: Bool {
        get { d.object(forKey: "clear.auto.localStorage") == nil ? true : d.bool(forKey: "clear.auto.localStorage") }
        set { setClearOption(newValue, forKey: "clear.auto.localStorage") }
    }

    static var clearOptionSummary: String {
        let on = [autoClearCache, autoClearCookies, autoClearHistory, autoClearLocalStorage].filter { $0 }.count
        var parts: [String] = []
        if on == 0 { parts.append("Clear off") }
        else if on == 4 { parts.append("Clear all") }
        else { parts.append("Clear \(on)/4") }
        if closeAllTabsOnExit { parts.append("Close tabs") }
        return parts.joined(separator: " · ")
    }

    /// Close every tab when leaving the app (leave one fresh New Tab). Default on.
    static var closeAllTabsOnExit: Bool {
        get { d.object(forKey: "clear.closeTabsOnExit") == nil ? true : d.bool(forKey: "clear.closeTabsOnExit") }
        set { setClearOption(newValue, forKey: "clear.closeTabsOnExit") }
    }

    /// Show tab card webpage snapshots. Default on.
    static var showTabsPreviewImages: Bool {
        get { d.object(forKey: "clear.showTabPreviews") == nil ? true : d.bool(forKey: "clear.showTabPreviews") }
        set { setClearOption(newValue, forKey: "clear.showTabPreviews") }
    }

    /// How many recently used webpage tabs keep a live `WKWebView` (LRU). Default 3.
    /// Older tabs stay in the switcher but unload until reopened. Range 1…8.
    static var activeBackgroundTabLimit: Int {
        get {
            guard d.object(forKey: "tabs.activeBackgroundLimit") != nil else { return 3 }
            return min(max(d.integer(forKey: "tabs.activeBackgroundLimit"), 1), 8)
        }
        set {
            let capped = min(max(newValue, 1), 8)
            d.set(capped, forKey: "tabs.activeBackgroundLimit")
            d.synchronize()
            NotificationCenter.default.post(name: .clearOptionSettingsChanged, object: nil)
        }
    }

    static let activeBackgroundTabLimitOptions: [Int] = Array(1...8)
}

extension Notification.Name {
    static let trackerProtectionChanged = Notification.Name("mmbrowser.tp.changed")
    static let accurateBlockCountChanged = Notification.Name("mmbrowser.tp.accurateBlockCount.changed")
    static let noImagesChanged = Notification.Name("mmbrowser.noimages.changed")
    static let homeSettingsChanged = Notification.Name("mmbrowser.home.changed")
    static let navigationDirectoryChanged = Notification.Name("mmbrowser.navigation.changed")
    static let searchEngineChanged = Notification.Name("mmbrowser.search.changed")
    static let shortsFocusChanged = Notification.Name("mmbrowser.shorts.changed")
    static let youtubeAdShieldChanged = Notification.Name("mmbrowser.yt.adshield.changed")
    static let mediaPlaybackSettingsChanged = Notification.Name("mmbrowser.media.changed")
    static let locationPrivacyChanged = Notification.Name("mmbrowser.location.changed")
    static let globalPrivacyControlChanged = Notification.Name("mmbrowser.gpc.changed")
    static let shareDiagnosticsChanged = Notification.Name("mmbrowser.diagnostics.changed")
    static let clearOptionSettingsChanged = Notification.Name("mmbrowser.clearOption.changed")
    /// Posted after scheduled clear so the browser can close tabs if configured.
    static let clearOptionSessionCleanup = Notification.Name("mmbrowser.clearOption.sessionCleanup")
    /// Media / PiP session started — used for one-time Background Audio discovery tip.
    static let featureDiscoveryMediaStarted = Notification.Name("mmbrowser.featureDiscovery.mediaStarted")
}
