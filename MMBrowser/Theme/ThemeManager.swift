import UIKit

final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var current: ThemePack

    var colors: ThemeColors { current.colors }

    private init() {
        current = BuiltinThemePacks.pack(id: AppSettings.themePackID)
    }

    func reloadFromSettings() {
        apply(packID: AppSettings.themePackID, persist: false)
    }

    func select(packID: String) {
        apply(packID: packID, persist: true)
    }

    private func apply(packID: String, persist: Bool) {
        let pack = BuiltinThemePacks.pack(id: packID)
        current = pack
        if persist {
            AppSettings.themePackID = pack.id
        }
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    /// Resolves an icon: prefers asset when configured and present; falls back to symbol / default pack.
    func image(
        for key: ThemeIconKey,
        configuration: UIImage.SymbolConfiguration? = nil
    ) -> UIImage? {
        let ref = current.icons[key] ?? BuiltinThemePacks.defaultPack.icons[key]
        guard let ref = ref else { return nil }
        switch ref {
        case .symbol(let name):
            if let configuration = configuration {
                return UIImage(systemName: name, withConfiguration: configuration)
            }
            return UIImage(systemName: name)
        case .asset(let name):
            if let asset = UIImage(named: name) {
                return asset.withRenderingMode(.alwaysTemplate)
            }
            // Asset missing → try same key from default pack as symbol fallback.
            if let fallback = BuiltinThemePacks.defaultPack.icons[key],
               case .symbol(let symbol) = fallback {
                if let configuration = configuration {
                    return UIImage(systemName: symbol, withConfiguration: configuration)
                }
                return UIImage(systemName: symbol)
            }
            return nil
        }
    }

    /// Convenience for menu rows that still pass legacy SF Symbol strings.
    func menuSymbolFallback(_ symbol: String, key: ThemeIconKey) -> UIImage? {
        image(for: key) ?? UIImage(systemName: symbol)
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("mmbrowser.theme.changed")
}
