import UIKit

enum BrowserTheme {
    private static var c: ThemeColors { ThemeManager.shared.colors }

    static var background: UIColor { c.background }
    static var elevated: UIColor { c.elevated }
    static var card: UIColor { c.card }
    static var secondaryCard: UIColor { c.secondaryCard }
    /// Distinct chrome for private browsing — derived from the active theme pack.
    static var privateBackground: UIColor { c.privateBackground }
    static var privateElevated: UIColor { c.privateElevated }
    static var privateAccent: UIColor { c.privateAccent }
    static var chromeBlue: UIColor { c.accent }
    static var textPrimary: UIColor { c.textPrimary }
    static var textSecondary: UIColor { c.textSecondary }
    static let toolbarHeight: CGFloat = 52
    static let addressBarHeight: CGFloat = 44

    static var preferredUserInterfaceStyle: UIUserInterfaceStyle {
        ThemeManager.shared.current.userInterfaceStyle
    }

    /// NTP wallpapers: Default = theme background; others tint that base (light/dark adaptive).
    static func homeWallpaperColor(at index: Int = AppSettings.homeWallpaperIndex) -> UIColor {
        let colors = homeWallpaperColors
        return colors[index % colors.count]
    }

    static var homeWallpaperColors: [UIColor] {
        let base = background
        let isLight = ThemeManager.shared.current.isLight
        if isLight {
            return [
                base,
                blend(base, ThemeHex.color("6B8FD4"), amount: 0.22),
                blend(base, ThemeHex.color("5FA86E"), amount: 0.18),
                blend(base, ThemeHex.color("6B5A78"), amount: 0.16)
            ]
        }
        return [
            base,
            blend(base, ThemeHex.color("1A2A4A"), amount: 0.55),
            blend(base, ThemeHex.color("152818"), amount: 0.55),
            blend(base, ThemeHex.color("0C0C14"), amount: 0.70)
        ]
    }

    private static func blend(_ a: UIColor, _ b: UIColor, amount: CGFloat) -> UIColor {
        let t = min(max(amount, 0), 1)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }

    /// Applies opaque chrome so presented sheets match the active theme.
    static func applyDarkNavigationBar(to navigationBar: UINavigationBar) {
        applyNavigationBar(to: navigationBar)
    }

    static func applyNavigationBar(to navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = background
        appearance.titleTextAttributes = [.foregroundColor: textPrimary]
        appearance.largeTitleTextAttributes = [.foregroundColor: textPrimary]

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = appearance
        }
        navigationBar.barStyle = ThemeManager.shared.current.isLight ? .default : .black
        navigationBar.isTranslucent = false
        navigationBar.tintColor = chromeBlue
        navigationBar.titleTextAttributes = [.foregroundColor: textPrimary]
    }

    /// Shared chrome for settings / library screens so light themes stay readable.
    static func applyScreenChrome(to viewController: UIViewController, tableView: UITableView? = nil) {
        viewController.view.backgroundColor = background
        viewController.overrideUserInterfaceStyle = preferredUserInterfaceStyle
        tableView?.backgroundColor = background
        tableView?.overrideUserInterfaceStyle = preferredUserInterfaceStyle
        tableView?.separatorColor = textSecondary.withAlphaComponent(0.25)
        tableView?.tintColor = chromeBlue
        if let navigationBar = viewController.navigationController?.navigationBar {
            applyNavigationBar(to: navigationBar)
        }
    }

    static func styleListCell(_ cell: UITableViewCell) {
        cell.backgroundColor = card
        cell.textLabel?.textColor = textPrimary
        cell.detailTextLabel?.textColor = textSecondary
        cell.tintColor = chromeBlue
    }

    static func styleSectionHeaderFooter(_ view: UIView) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.textColor = textSecondary
        header.detailTextLabel?.textColor = textSecondary
    }
}
