import UIKit
import SnapKit

/// Full-bleed home wallpaper with fit/tile/stretch modes and a readability overlay.
final class HomeWallpaperBackdropView: UIView {
    private let imageView = UIImageView()
    private let tileView = UIView()
    private let overlayView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true

        imageView.clipsToBounds = true
        tileView.clipsToBounds = true
        overlayView.isUserInteractionEnabled = false

        addSubview(tileView)
        addSubview(imageView)
        addSubview(overlayView)
        tileView.snp.makeConstraints { $0.edges.equalToSuperview() }
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        overlayView.snp.makeConstraints { $0.edges.equalToSuperview() }
        applyCurrent()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyCurrent() {
        let option = HomeWallpaper.selected
        backgroundColor = HomeWallpaper.fallbackColor(at: option)

        guard let image = HomeWallpaper.image(at: option) else {
            imageView.isHidden = true
            tileView.isHidden = true
            overlayView.isHidden = true
            imageView.image = nil
            tileView.backgroundColor = .clear
            return
        }

        let mode = HomeWallpaper.fitMode
        let imageAlpha = HomeWallpaper.imageOpacity
        let overlayAlpha = HomeWallpaper.overlayOpacity

        overlayView.isHidden = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(overlayAlpha)

        switch mode {
        case .tile:
            imageView.isHidden = true
            imageView.image = nil
            tileView.isHidden = false
            tileView.alpha = imageAlpha
            tileView.backgroundColor = UIColor(patternImage: HomeWallpaper.tilePattern(from: image))
        case .fit:
            imageView.isHidden = false
            tileView.isHidden = true
            tileView.backgroundColor = .clear
            imageView.image = image
            imageView.contentMode = .scaleAspectFit
            imageView.alpha = imageAlpha
        case .stretch:
            imageView.isHidden = false
            tileView.isHidden = true
            tileView.backgroundColor = .clear
            imageView.image = image
            imageView.contentMode = .scaleToFill
            imageView.alpha = imageAlpha
        case .fill:
            imageView.isHidden = false
            tileView.isHidden = true
            tileView.backgroundColor = .clear
            imageView.image = image
            imageView.contentMode = .scaleAspectFill
            imageView.alpha = imageAlpha
        }
    }
}
