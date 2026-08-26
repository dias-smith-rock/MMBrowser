import Foundation
import UIKit

enum GestureShape: String, CaseIterable {
    /// Short reverse hook, then long stroke right → Back.
    case hookRight
    /// Short reverse hook, then long stroke left → Forward.
    case hookLeft
    /// Closed circle → Add Bookmark.
    case circle

    var displayName: String {
        switch self {
        case .hookRight: return "Hook →"
        case .hookLeft: return "Hook ←"
        case .circle: return "Hook ○"
        }
    }

    var symbolName: String {
        switch self {
        case .hookRight: return "arrow.right"
        case .hookLeft: return "arrow.left"
        case .circle: return "circle"
        }
    }

    var defaultAction: GestureBrowserAction {
        switch self {
        case .hookRight: return .goBack
        case .hookLeft: return .goForward
        case .circle: return .addBookmark
        }
    }

    var isNavigationHook: Bool {
        switch self {
        case .hookRight, .hookLeft: return true
        case .circle: return false
        }
    }
}

enum GestureBrowserAction: String, CaseIterable {
    case none
    case reload
    case addBookmark
    case addReadingList
    case share
    case findInPage
    case readerMode
    case desktopSite
    case newIncognitoTab
    case screenshot
    case goBack
    case goForward
    case pageUp
    case pageDown

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .reload: return "Reload"
        case .addBookmark: return "Add Bookmark"
        case .addReadingList: return "Add to Reading List"
        case .share: return "Share"
        case .findInPage: return "Find in Page"
        case .readerMode: return "Reader"
        case .desktopSite: return "How this tab looks"
        case .newIncognitoTab: return "New Incognito Tab"
        case .screenshot: return "Screenshot"
        case .goBack: return "Back"
        case .goForward: return "Forward"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        }
    }

    var menuAction: MenuAction? {
        switch self {
        case .none, .goBack, .goForward, .pageUp, .pageDown: return nil
        case .reload: return .reload
        case .addBookmark: return .addBookmark
        case .addReadingList: return .addReadingList
        case .share: return .share
        case .findInPage: return .findInPage
        case .readerMode: return .readerMode
        case .desktopSite: return .userAgent
        case .newIncognitoTab: return .newIncognitoTab
        case .screenshot: return .screenshot
        }
    }
}

enum GestureActionMap {
    private static func bindingKey(for shape: GestureShape) -> String {
        "gesture.binding.\(shape.rawValue)"
    }

    static func action(for shape: GestureShape, respectingToggles: Bool = true) -> GestureBrowserAction {
        if respectingToggles {
            if shape.isNavigationHook {
                guard AppSettings.navigationSwipeEnabled else { return .none }
            } else {
                guard AppSettings.drawingGesturesEnabled else { return .none }
            }
        }
        let key = bindingKey(for: shape)
        guard let raw = UserDefaults.standard.string(forKey: key),
              let action = GestureBrowserAction(rawValue: raw) else {
            return shape.defaultAction
        }
        return action
    }

    static func setAction(_ action: GestureBrowserAction, for shape: GestureShape) {
        UserDefaults.standard.set(action.rawValue, forKey: bindingKey(for: shape))
        NotificationCenter.default.post(name: .gestureSettingsChanged, object: nil)
    }

    static var summary: String {
        let enabled = AppSettings.drawingGesturesEnabled
        let swipe = AppSettings.navigationSwipeEnabled
        switch (enabled, swipe) {
        case (true, true): return "Hooks & Circle"
        case (true, false): return "Circle"
        case (false, true): return "Hooks"
        case (false, false): return "Off"
        }
    }
}
