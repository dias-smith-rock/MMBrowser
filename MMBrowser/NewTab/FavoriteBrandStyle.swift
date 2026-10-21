import UIKit

/// Facebook-style circular brand badges for Favorites tiles.
enum FavoriteBrandStyle {
    /// Returns a complete circular badge (edge-to-edge), matching `nav_facebook`.
    static func badgeImage(
        urlString: String?,
        assetName: String?,
        fallbackTitle: String,
        size: CGFloat = 128
    ) -> UIImage {
        let host = normalizedHost(from: urlString)
        let asset = assetName ?? ""

        // Bundled marks that are already full circular badges.
        if logoFillsCircle(host: host, asset: asset),
           let named = assetName.flatMap({ UIImage(named: $0) })
            ?? bundledAssetName(forHost: host).flatMap({ UIImage(named: $0) }) {
            return named
        }

        if let drawn = drawKnownBrand(host: host, asset: asset, size: size) {
            return drawn
        }

        // Fallback: soft circle + letter (same silhouette as Facebook).
        return letterBadge(title: fallbackTitle, size: size)
    }

    // MARK: - Known brands

    private static func drawKnownBrand(host: String, asset: String, size: CGFloat) -> UIImage? {
        if matches(host, "instagram.com") || asset == "nav_instagram" {
            return gradientBadge(
                colors: [
                    UIColor(red: 131 / 255, green: 58 / 255, blue: 180 / 255, alpha: 1),
                    UIColor(red: 253 / 255, green: 29 / 255, blue: 29 / 255, alpha: 1),
                    UIColor(red: 252 / 255, green: 176 / 255, blue: 69 / 255, alpha: 1)
                ],
                size: size
            ) { ctx, bounds in
                drawInstagramGlyph(in: bounds, context: ctx)
            }
        }
        if matches(host, "telegram.org") || matches(host, "t.me") {
            return solidBadge(color: UIColor(red: 42 / 255, green: 171 / 255, blue: 238 / 255, alpha: 1), size: size) { ctx, bounds in
                drawTelegramGlyph(in: bounds, context: ctx)
            }
        }
        if matches(host, "linkedin.com") || asset == "nav_linkedin" {
            return nil // use bundled circular asset via logoFillsCircle
        }
        if matches(host, "spotify.com") || asset == "nav_spotify" {
            return solidBadge(color: UIColor(red: 30 / 255, green: 215 / 255, blue: 96 / 255, alpha: 1), size: size) { _, bounds in
                drawSymbol("waveform", in: bounds)
            }
        }
        if matches(host, "reddit.com") || asset == "nav_reddit" {
            return solidBadge(color: UIColor(red: 255 / 255, green: 69 / 255, blue: 0, alpha: 1), size: size) { _, bounds in
                drawSymbol("bubble.left.fill", in: bounds)
            }
        }
        if matches(host, "github.com") || asset == "nav_github" {
            return solidBadge(color: UIColor(white: 0.12, alpha: 1), size: size) { _, bounds in
                drawSymbol("chevron.left.forwardslash.chevron.right", in: bounds)
            }
        }
        if matches(host, "google.") {
            return solidBadge(color: UIColor(white: 0.92, alpha: 1), size: size) { _, bounds in
                drawGoogleG(in: bounds)
            }
        }
        return nil
    }

    // MARK: - Badge canvas

    private static func solidBadge(
        color: UIColor,
        size: CGFloat,
        draw: (CGContext, CGRect) -> Void
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            color.setFill()
            UIBezierPath(ovalIn: bounds).fill()
            draw(ctx.cgContext, bounds)
        }
    }

    private static func gradientBadge(
        colors: [UIColor],
        size: CGFloat,
        draw: (CGContext, CGRect) -> Void
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let path = UIBezierPath(ovalIn: bounds)
            path.addClip()
            let cgColors = colors.map(\.cgColor) as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: [0, 0.55, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size),
                    end: CGPoint(x: size, y: 0),
                    options: []
                )
            }
            draw(ctx.cgContext, bounds)
        }
    }

    private static func letterBadge(title: String, size: CGFloat) -> UIImage {
        solidBadge(color: UIColor(white: 0.45, alpha: 1), size: size) { _, bounds in
            let letter = String(title.prefix(1)).uppercased()
            let font = UIFont.systemFont(ofSize: size * 0.42, weight: .semibold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let textSize = (letter as NSString).size(withAttributes: attrs)
            let rect = CGRect(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            (letter as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    // MARK: - Glyphs (white on brand fill)

    private static func drawSymbol(_ name: String, in bounds: CGRect) {
        let pointSize = bounds.width * 0.42
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let image = UIImage(systemName: name, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
        let side = bounds.width * 0.46
        let rect = CGRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        image.draw(in: rect)
    }

    private static func drawInstagramGlyph(in bounds: CGRect, context: CGContext) {
        let inset = bounds.width * 0.24
        let outer = bounds.insetBy(dx: inset, dy: inset)
        let radius = outer.width * 0.22
        let path = UIBezierPath(roundedRect: outer, cornerRadius: radius)
        path.lineWidth = bounds.width * 0.055
        UIColor.white.setStroke()
        path.stroke()

        let lensSide = outer.width * 0.38
        let lens = CGRect(
            x: outer.midX - lensSide / 2,
            y: outer.midY - lensSide / 2,
            width: lensSide,
            height: lensSide
        )
        let lensPath = UIBezierPath(ovalIn: lens)
        lensPath.lineWidth = bounds.width * 0.055
        lensPath.stroke()

        let dotSide = bounds.width * 0.07
        let dot = CGRect(
            x: outer.maxX - dotSide - outer.width * 0.1,
            y: outer.minY + outer.height * 0.1,
            width: dotSide,
            height: dotSide
        )
        UIColor.white.setFill()
        UIBezierPath(ovalIn: dot).fill()
    }

    private static func drawTelegramGlyph(in bounds: CGRect, context: CGContext) {
        drawSymbol("paperplane.fill", in: bounds)
    }

    private static func drawGoogleG(in bounds: CGRect) {
        let letter = "G"
        let font = UIFont.systemFont(ofSize: bounds.width * 0.48, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        // Approximate multicolor G with blue (good enough for shortcut tile).
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 66 / 255, green: 133 / 255, blue: 244 / 255, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let textSize = (letter as NSString).size(withAttributes: attrs)
        let rect = CGRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (letter as NSString).draw(in: rect, withAttributes: attrs)
    }

    // MARK: - Helpers

    private static func logoFillsCircle(host: String, asset: String) -> Bool {
        matches(host, "facebook.com") || asset == "nav_facebook"
            || matches(host, "whatsapp.com") || asset == "nav_whatsapp"
            || host == "x.com" || matches(host, "twitter.com") || asset == "nav_x"
            || isYouTubeMain(host: host, asset: asset)
            || matches(host, "linkedin.com") || asset == "nav_linkedin"
    }

    private static func bundledAssetName(forHost host: String) -> String? {
        if matches(host, "facebook.com") { return "nav_facebook" }
        if matches(host, "whatsapp.com") { return "nav_whatsapp" }
        if host == "x.com" || matches(host, "twitter.com") { return "nav_x" }
        if isYouTubeMain(host: host, asset: "") { return "nav_youtube" }
        if matches(host, "linkedin.com") { return "nav_linkedin" }
        return nil
    }

    /// youtube.com / youtu.be — not YouTube Music.
    private static func isYouTubeMain(host: String, asset: String) -> Bool {
        if asset == "nav_youtubemusic" || host.hasPrefix("music.") { return false }
        if asset == "nav_youtube" { return true }
        return host == "youtu.be" || matches(host, "youtube.com") || matches(host, "youtu.be")
    }

    private static func normalizedHost(from urlString: String?) -> String {
        guard let urlString, let url = URL(string: urlString), var host = url.host?.lowercased(), !host.isEmpty else {
            return ""
        }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        return host
    }

    private static func matches(_ host: String, _ token: String) -> Bool {
        guard !host.isEmpty else { return false }
        return host == token || host.hasSuffix("." + token) || host.contains(token)
    }
}
