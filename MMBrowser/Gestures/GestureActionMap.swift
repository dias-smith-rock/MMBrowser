import Foundation
import UIKit

enum GestureShape: String, CaseIterable {
    case checkmark
    case circle
    case zigzag
    case triangle
    case vUp
    case vDown

    var displayName: String {
        switch self {
        case .checkmark: return "Checkmark ✓"
        case .circle: return "Circle O"
        case .zigzag: return "Zigzag Z"
        case .triangle: return "Triangle △"
        case .vUp: return "V Up ∧"
        case .vDown: return "V Down ∨"
        }
    }

    var symbolName: String {
        switch self {
        case .checkmark: return "checkmark"
        case .circle: return "circle"
        case .zigzag: return "waveform.path"
        case .triangle: return "triangle"
        case .vUp: return "chevron.up"
        case .vDown: return "chevron.down"
        }
    }

    var defaultAction: GestureBrowserAction {
        switch self {
        case .checkmark: return .addBookmark
        case .circle: return .reload
        case .zigzag: return .share
        case .triangle: return .addReadingList
        case .vUp, .vDown: return .none
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

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .reload: return "Reload"
        case .addBookmark: return "Add Bookmark"
        case .addReadingList: return "Add to Reading List"
        case .share: return "Share"
        case .findInPage: return "Find in Page"
        case .readerMode: return "Reader"
        case .desktopSite: return "Request Desktop Site"
        case .newIncognitoTab: return "New Incognito Tab"
        case .screenshot: return "Screenshot"
        }
    }

    var menuAction: MenuAction? {
        switch self {
        case .none: return nil
        case .reload: return .reload
        case .addBookmark: return .addBookmark
        case .addReadingList: return .addReadingList
        case .share: return .share
        case .findInPage: return .findInPage
        case .readerMode: return .readerMode
        case .desktopSite: return .desktopSite
        case .newIncognitoTab: return .newIncognitoTab
        case .screenshot: return .screenshot
        }
    }
}

enum GestureActionMap {
    private static func bindingKey(for shape: GestureShape) -> String {
        "gesture.binding.\(shape.rawValue)"
    }

    static func action(for shape: GestureShape) -> GestureBrowserAction {
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
        case (true, true): return "Drawing & Swipes"
        case (true, false): return "Drawing"
        case (false, true): return "Swipes"
        case (false, false): return "Off"
        }
    }
}
