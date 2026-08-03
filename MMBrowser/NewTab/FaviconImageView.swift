import UIKit

/// Displays a bundled navigation logo from the asset catalog.
final class FaviconImageView: UIImageView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        clipsToBounds = true
        backgroundColor = .clear
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setLogo(assetName: String?, fallbackTitle: String) {
        if let assetName, let image = UIImage(named: assetName) {
            self.image = image
            return
        }
        self.image = Self.letterImage(for: fallbackTitle)
    }

    private static func letterImage(for title: String) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let letter = String(title.prefix(1)).uppercased()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: 0, y: 14, width: size.width, height: 36)
            letter.draw(in: rect, withAttributes: attrs)
        }
    }
}
