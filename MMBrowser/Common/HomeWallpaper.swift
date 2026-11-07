import UIKit

/// Home / Space wallpaper presets, custom photo, fit modes, and overlay.
enum HomeWallpaper {
    enum Option: Int, CaseIterable {
        case `default` = 0
        case deepBlue = 1
        case forest = 2
        case midnight = 3
        case custom = 4

        var title: String {
            switch self {
            case .default: return "Default"
            case .deepBlue: return "Deep Blue"
            case .forest: return "Forest"
            case .midnight: return "Midnight"
            case .custom: return "Custom"
            }
        }

        var usesPhoto: Bool {
            switch self {
            case .forest, .midnight, .custom: return true
            case .default, .deepBlue: return false
            }
        }
    }

    /// How the photo is laid out on screen.
    enum FitMode: Int, CaseIterable {
        case fit = 0
        case tile = 1
        case stretch = 2
        case fill = 3

        var title: String {
            switch self {
            case .fit: return "Fit"
            case .tile: return "Tile"
            case .stretch: return "Stretch"
            case .fill: return "Fill"
            }
        }

        var detail: String {
            switch self {
            case .fit: return "Show the full image"
            case .tile: return "Repeat the image"
            case .stretch: return "Stretch to fill (may distort)"
            case .fill: return "Crop to fill the screen"
            }
        }
    }

    static var names: [String] { Option.allCases.map(\.title) }

    static var selected: Option {
        Option(rawValue: AppSettings.homeWallpaperIndex) ?? .default
    }

    static var selectedIndex: Int { selected.rawValue }

    static var fitMode: FitMode {
        FitMode(rawValue: AppSettings.homeWallpaperFitMode) ?? .fill
    }

    /// Overlay darkness 0…1 (higher = stronger mask).
    static var overlayOpacity: CGFloat {
        CGFloat(AppSettings.homeWallpaperOverlayOpacity)
    }

    /// Image layer alpha (wallpaper stays slightly translucent under the mask).
    static var imageOpacity: CGFloat { 0.92 }

    static func fallbackColor(at option: Option = selected) -> UIColor {
        BrowserTheme.homeWallpaperColor(at: option.rawValue)
    }

    /// Resolved photo / art for the current (or given) option. `nil` for Default.
    static func image(at option: Option = selected) -> UIImage? {
        switch option {
        case .default:
            return nil
        case .deepBlue:
            return DeepBlueArt.image()
        case .forest:
            return UIImage(named: "wallpaper_forest")
                ?? bundleJPEG("wallpaper_forest")
        case .midnight:
            return UIImage(named: "wallpaper_midnight")
                ?? bundleJPEG("wallpaper_midnight")
        case .custom:
            return loadCustomImage()
        }
    }

    static func preview(at option: Option, size: CGSize = CGSize(width: 44, height: 44)) -> UIImage {
        if option == .default {
            return swatch(color: BrowserTheme.background, size: size)
        }
        if let art = image(at: option) {
            return scaledPreview(art, size: size)
        }
        return swatch(color: fallbackColor(at: option), size: size)
    }

    static func preview(at index: Int, size: CGSize = CGSize(width: 44, height: 44)) -> UIImage {
        preview(at: Option(rawValue: index) ?? .default, size: size)
    }

    // MARK: - Custom photo storage

    static var customImageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("HomeWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom.jpg")
    }

    static var hasCustomImage: Bool {
        FileManager.default.fileExists(atPath: customImageURL.path)
    }

    @discardableResult
    static func saveCustomImage(_ image: UIImage) -> Bool {
        let maxSide: CGFloat = 2048
        let scaled = downscale(image, maxSide: maxSide)
        guard let data = scaled.jpegData(compressionQuality: 0.88) else { return false }
        do {
            try data.write(to: customImageURL, options: .atomic)
            AppSettings.homeWallpaperIndex = Option.custom.rawValue
            return true
        } catch {
            return false
        }
    }

    static func removeCustomImage() {
        try? FileManager.default.removeItem(at: customImageURL)
        if selected == .custom {
            AppSettings.homeWallpaperIndex = Option.default.rawValue
        } else {
            NotificationCenter.default.post(name: .homeSettingsChanged, object: nil)
        }
    }

    static func loadCustomImage() -> UIImage? {
        guard hasCustomImage else { return nil }
        return UIImage(contentsOfFile: customImageURL.path)
    }

    /// Pattern image sized for tiling.
    static func tilePattern(from image: UIImage, tileWidth: CGFloat = 148) -> UIImage {
        let scale = tileWidth / max(image.size.width, 1)
        let size = CGSize(
            width: max(1, tileWidth.rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Helpers

    private static func bundleJPEG(_ name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Wallpapers")
                ?? Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func scaledPreview(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: 8).addClip()
            let imgAspect = image.size.width / max(image.size.height, 1)
            let viewAspect = size.width / max(size.height, 1)
            var draw = rect
            if imgAspect > viewAspect {
                let w = size.height * imgAspect
                draw = CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
            } else {
                let h = size.width / imgAspect
                draw = CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
            }
            image.draw(in: draw)
        }
    }

    private static func swatch(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8).fill()
        }
    }

    /// Procedural Deep Blue (no photo asset).
    private enum DeepBlueArt {
        private static var cached: UIImage?

        static func image() -> UIImage {
            if let cached { return cached }
            let size = CGSize(width: 600, height: 1200)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let cg = ctx.cgContext
                let rect = CGRect(origin: .zero, size: size)
                fillGradient(cg, rect: rect, colors: [
                    ThemeHex.color("0B1226"),
                    ThemeHex.color("152A55"),
                    ThemeHex.color("1E3F7A")
                ], start: CGPoint(x: rect.midX, y: 0), end: CGPoint(x: rect.midX, y: rect.maxY))
                softOrb(cg, center: CGPoint(x: rect.width * 0.22, y: rect.height * 0.18),
                        radius: rect.width * 0.55, color: ThemeHex.color("3D7EFF").withAlphaComponent(0.38))
                softOrb(cg, center: CGPoint(x: rect.width * 0.82, y: rect.height * 0.62),
                        radius: rect.width * 0.48, color: ThemeHex.color("1AC8FF").withAlphaComponent(0.22))
                softOrb(cg, center: CGPoint(x: rect.width * 0.45, y: rect.height * 0.88),
                        radius: rect.width * 0.40, color: ThemeHex.color("0A1B40").withAlphaComponent(0.55))
            }
            cached = img
            return img
        }

        private static func fillGradient(
            _ cg: CGContext,
            rect: CGRect,
            colors: [UIColor],
            start: CGPoint,
            end: CGPoint
        ) {
            let cgColors = colors.map { $0.cgColor } as CFArray
            let spaces = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: spaces, colors: cgColors, locations: nil) else {
                colors.last?.setFill()
                cg.fill(rect)
                return
            }
            cg.drawLinearGradient(
                gradient,
                start: start,
                end: end,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        private static func softOrb(_ cg: CGContext, center: CGPoint, radius: CGFloat, color: UIColor) {
            let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            let spaces = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(
                colorsSpace: spaces,
                colors: colors,
                locations: [0, 1] as [CGFloat]
            ) else { return }
            cg.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }
    }
}
