import Foundation
import UIKit

enum AppSettings {
    private static let d = UserDefaults.standard

    static var trackerProtectionEnabled: Bool {
        get { d.object(forKey: "tp.enabled") == nil ? true : d.bool(forKey: "tp.enabled") }
        set { d.set(newValue, forKey: "tp.enabled"); NotificationCenter.default.post(name: .trackerProtectionChanged, object: nil) }
    }

    static var httpsOnly: Bool {
        get { d.bool(forKey: "https.only") }
        set { d.set(newValue, forKey: "https.only") }
    }

    static var noImagesEnabled: Bool {
        get { d.bool(forKey: "no.images.enabled") }
        set {
            d.set(newValue, forKey: "no.images.enabled")
            NotificationCenter.default.post(name: .noImagesChanged, object: nil)
        }
    }

    static var searchEngineID: String {
        get { d.string(forKey: "search.engine") ?? SearchEngine.duckDuckGo.id }
        set { d.set(newValue, forKey: "search.engine") }
    }

    static var showShortcuts: Bool {
        get { d.object(forKey: "home.shortcuts") == nil ? true : d.bool(forKey: "home.shortcuts") }
        set { d.set(newValue, forKey: "home.shortcuts"); NotificationCenter.default.post(name: .homeSettingsChanged, object: nil) }
    }

    static var showContinue: Bool {
        get { d.object(forKey: "home.continue") == nil ? true : d.bool(forKey: "home.continue") }
        set { d.set(newValue, forKey: "home.continue"); NotificationCenter.default.post(name: .homeSettingsChanged, object: nil) }
    }

    static var showDiscover: Bool {
        get { d.object(forKey: "home.discover") == nil ? true : d.bool(forKey: "home.discover") }
        set { d.set(newValue, forKey: "home.discover"); NotificationCenter.default.post(name: .homeSettingsChanged, object: nil) }
    }

    static var homeWallpaperIndex: Int {
        get { d.integer(forKey: "home.wallpaper") }
        set { d.set(newValue, forKey: "home.wallpaper"); NotificationCenter.default.post(name: .homeSettingsChanged, object: nil) }
    }

    static var didShowOnboarding: Bool {
        get { d.bool(forKey: "onboarding.done") }
        set { d.set(newValue, forKey: "onboarding.done") }
    }
}

extension Notification.Name {
    static let trackerProtectionChanged = Notification.Name("mmbrowser.tp.changed")
    static let noImagesChanged = Notification.Name("mmbrowser.noimages.changed")
    static let homeSettingsChanged = Notification.Name("mmbrowser.home.changed")
    static let searchEngineChanged = Notification.Name("mmbrowser.search.changed")
}
