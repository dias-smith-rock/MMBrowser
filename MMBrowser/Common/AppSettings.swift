import Foundation
import UIKit

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

    static var httpsOnly: Bool {
        get { d.bool(forKey: "https.only") }
        set { d.set(newValue, forKey: "https.only") }
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

    static var searchEngineID: String {
        get { d.string(forKey: "search.engine") ?? SearchEngine.duckDuckGo.id }
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

    /// One-time coach mark: swipe address bar to switch tabs.
    static var didShowAddressBarSwipeTip: Bool {
        get { d.bool(forKey: "tip.addressBarSwipe.done") }
        set { d.set(newValue, forKey: "tip.addressBarSwipe.done") }
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
        case .ask: return "Ask"
        case .spoof:
            if let preset = SpoofLocationPreset.all.first(where: { $0.id == spoofPresetID }) {
                return "Spoof · \(preset.name)"
            }
            return String(format: "Spoof · %.2f, %.2f", spoofLatitude, spoofLongitude)
        }
    }

    /// One-finger Hook → / ← navigation. Default on.
    static var navigationSwipeEnabled: Bool {
        get { d.object(forKey: "gesture.navSwipe.enabled") == nil ? true : d.bool(forKey: "gesture.navSwipe.enabled") }
        set {
            d.set(newValue, forKey: "gesture.navSwipe.enabled")
            NotificationCenter.default.post(name: .gestureSettingsChanged, object: nil)
        }
    }

    /// One-finger Hook ○ (circle) gesture. Default on.
    static var drawingGesturesEnabled: Bool {
        get { d.object(forKey: "gesture.drawing.enabled") == nil ? true : d.bool(forKey: "gesture.drawing.enabled") }
        set {
            d.set(newValue, forKey: "gesture.drawing.enabled")
            NotificationCenter.default.post(name: .gestureSettingsChanged, object: nil)
        }
    }

    // MARK: - Clear Option (auto-clear on exit). Defaults on for privacy.

    private static func setClearOption(_ value: Bool, forKey key: String) {
        d.set(value, forKey: key)
        // Ensure the choice survives force-quit / crash immediately after toggling.
        d.synchronize()
        NotificationCenter.default.post(name: .clearOptionSettingsChanged, object: nil)
    }

    static var autoClearCache: Bool {
        get { d.object(forKey: "clear.auto.cache") == nil ? true : d.bool(forKey: "clear.auto.cache") }
        set { setClearOption(newValue, forKey: "clear.auto.cache") }
    }

    static var autoClearCookies: Bool {
        get { d.object(forKey: "clear.auto.cookies") == nil ? true : d.bool(forKey: "clear.auto.cookies") }
        set { setClearOption(newValue, forKey: "clear.auto.cookies") }
    }

    /// When true, browsing history is cleared when leaving the app / on next launch.
    /// History is still recorded during the current session. Default off so History works out of the box.
    static var autoClearHistory: Bool {
        get { d.object(forKey: "clear.auto.history") == nil ? false : d.bool(forKey: "clear.auto.history") }
        set { setClearOption(newValue, forKey: "clear.auto.history") }
    }

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

    /// Close every tab when leaving the app (leave one fresh New Tab). Default off so
    /// container tabs survive relaunch / force-quit; enable for stronger session privacy.
    static var closeAllTabsOnExit: Bool {
        get { d.object(forKey: "clear.closeTabsOnExit") == nil ? false : d.bool(forKey: "clear.closeTabsOnExit") }
        set { setClearOption(newValue, forKey: "clear.closeTabsOnExit") }
    }

    /// Show tab card webpage snapshots. Default on.
    static var showTabsPreviewImages: Bool {
        get { d.object(forKey: "clear.showTabPreviews") == nil ? true : d.bool(forKey: "clear.showTabPreviews") }
        set { setClearOption(newValue, forKey: "clear.showTabPreviews") }
    }

    /// Local notification when a download finishes (or fails) in the background. Default on.
    static var downloadCompletionNotificationsEnabled: Bool {
        get { d.object(forKey: "downloads.notify") == nil ? true : d.bool(forKey: "downloads.notify") }
        set { d.set(newValue, forKey: "downloads.notify") }
    }
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
    static let gestureSettingsChanged = Notification.Name("mmbrowser.gesture.changed")
    static let clearOptionSettingsChanged = Notification.Name("mmbrowser.clearOption.changed")
    /// Posted after scheduled clear so the browser can close tabs if configured.
    static let clearOptionSessionCleanup = Notification.Name("mmbrowser.clearOption.sessionCleanup")
}
