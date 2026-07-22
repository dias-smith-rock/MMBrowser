import UIKit

final class LetterAvatarView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        label.frame = bounds
    }

    func configure(title: String, colorSeed: String) {
        let letter = title.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "#"
        label.text = letter.uppercased()
        backgroundColor = Self.color(for: colorSeed)
    }

    private static func color(for seed: String) -> UIColor {
        var hash: UInt64 = 5381
        for unit in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(unit)
        }
        let hue = CGFloat(hash % 360) / 360.0
        return UIColor(hue: hue, saturation: 0.55, brightness: 0.72, alpha: 1)
    }
}
