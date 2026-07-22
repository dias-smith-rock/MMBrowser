import UIKit
import SnapKit

final class GoogleLogoView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 44, weight: .medium)
        addSubview(label)
        label.snp.makeConstraints { make in make.edges.equalToSuperview() }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyColors() {
        let text = "Google"
        let colors: [UIColor] = [
            UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1),
            UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1),
            UIColor(red: 0.98, green: 0.74, blue: 0.02, alpha: 1),
            UIColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1),
            UIColor(red: 0.20, green: 0.66, blue: 0.33, alpha: 1),
            UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1)
        ]
        let attributed = NSMutableAttributedString(string: text)
        for (index, color) in colors.enumerated() where index < text.count {
            let range = NSRange(location: index, length: 1)
            attributed.addAttribute(.foregroundColor, value: color, range: range)
        }
        label.attributedText = attributed
    }
}
