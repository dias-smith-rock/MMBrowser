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
    /// Asset bitmaps are scaled to `pointSize` so they match SF Symbol toolbar weight.
    func image(
        for key: ThemeIconKey,
        configuration: UIImage.SymbolConfiguration? = nil,
        pointSize: CGFloat = 22
    ) -> UIImage? {
        let config = configuration ?? UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let ref = current.icons[key] ?? BuiltinThemePacks.defaultPack.icons[key]
        guard let ref = ref else { return nil }
        switch ref {
        case .symbol(let name):
            return UIImage(systemName: name, withConfiguration: config)
        case .asset(let name):
            if let asset = UIImage(named: name) {
                return scaledTemplate(asset, pointSize: pointSize)
            }
            // Asset missing → try same key from default pack as symbol fallback.
            if let fallback = BuiltinThemePacks.defaultPack.icons[key],
               case .symbol(let symbol) = fallback {
                return UIImage(systemName: symbol, withConfiguration: config)
            }
            return nil
        }
    }

    private func scaledTemplate(_ image: UIImage, pointSize: CGFloat) -> UIImage {
        let src = image.withRenderingMode(.alwaysOriginal)
        let maxSide = max(src.size.width, src.size.height)
        guard maxSide > 0 else { return image.withRenderingMode(.alwaysTemplate) }
        let ratio = pointSize / maxSide
        let size = CGSize(width: max(1, src.size.width * ratio), height: max(1, src.size.height * ratio))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            src.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }

    /// Convenience for menu rows that still pass legacy SF Symbol strings.
    func menuSymbolFallback(_ symbol: String, key: ThemeIconKey) -> UIImage? {
        image(for: key) ?? UIImage(systemName: symbol)
    }
}

extension Notification.Name {
    static let themeDidChange = Notification.Name("mmbrowser.theme.changed")
}
