import UIKit

enum ThemeIconKey: String, CaseIterable {
    case toolbarBack = "toolbar.back"
    case toolbarForward = "toolbar.forward"
    case toolbarNewTab = "toolbar.newTab"
    case toolbarTabs = "toolbar.tabs"
    case toolbarMenu = "toolbar.menu"
    case addressScreenshot = "address.screenshot"
    case addressCleaner = "address.cleaner"
    case menuSettings = "menu.settings"
    case menuBookmarks = "menu.bookmarks"
    case menuHistory = "menu.history"
    case menuReadingList = "menu.readingList"
    case menuDownloads = "menu.downloads"
    case menuReader = "menu.reader"
    case menuReload = "menu.reload"
    case menuFind = "menu.find"
    case menuShare = "menu.share"
    case menuDesktop = "menu.desktop"
    case menuIncognito = "menu.incognito"
    case menuAddBookmark = "menu.addBookmark"
    case menuAddReadingList = "menu.addReadingList"
    case menuSharePDF = "menu.sharePDF"
    case menuScreenshot = "menu.screenshot"
    case menuLongScreenshot = "menu.longScreenshot"
}

enum ThemeIconRef {
    case symbol(String)
    case asset(String)
}

struct ThemeColors {
    let background: UIColor
    let elevated: UIColor
    let card: UIColor
    let secondaryCard: UIColor
    let accent: UIColor
    let textPrimary: UIColor
    let textSecondary: UIColor
    let privateBackground: UIColor
    let privateElevated: UIColor

    /// Private browsing accent follows the pack accent (slightly softer).
    var privateAccent: UIColor { accent }
}

struct ThemePack {
    let id: String
    let name: String
    /// When true, sheets/settings prefer light interface style.
    let isLight: Bool
    let colors: ThemeColors
    let icons: [ThemeIconKey: ThemeIconRef]

    var userInterfaceStyle: UIUserInterfaceStyle { isLight ? .light : .dark }
}

enum ThemeHex {
    static func color(_ hex: String, alpha: CGFloat = 1) -> UIColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            return UIColor.gray
        }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }
}
