import UIKit
import SnapKit

/// One-time coach mark pointing at the address bar: swipe to switch tabs.
final class AddressBarSwipeTipView: UIView {
    var onDismiss: (() -> Void)?

    private let dimView = UIView()
    private let highlight = UIView()
    private let card = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let gotItButton = UIButton(type: .system)
    private let arrow = UIView()
    private weak var anchorView: UIView?
    private weak var hostView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        addSubview(dimView)

        highlight.backgroundColor = .clear
        highlight.layer.cornerRadius = 22
        highlight.layer.borderWidth = 2
        highlight.layer.borderColor = BrowserTheme.chromeBlue.cgColor
        highlight.isUserInteractionEnabled = false
        addSubview(highlight)

        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        addSubview(card)

        arrow.backgroundColor = BrowserTheme.card
        addSubview(arrow)

        titleLabel.text = "Switch tabs faster"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 0

        bodyLabel.text = "Swipe left or right on the address bar to jump between open tabs."
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        gotItButton.setTitle("Got it", for: .normal)
        gotItButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        gotItButton.setTitleColor(.white, for: .normal)
        gotItButton.backgroundColor = BrowserTheme.chromeBlue
        gotItButton.layer.cornerRadius = 12
        gotItButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, gotItButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        card.addSubview(stack)

        dimView.snp.makeConstraints { $0.edges.equalToSuperview() }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }
        gotItButton.snp.makeConstraints { $0.height.equalTo(44) }

        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Present above `host`, highlighting `anchor` (typically the address bar).
    static func present(in host: UIView, anchoring anchor: UIView, onDismiss: (() -> Void)? = nil) -> AddressBarSwipeTipView {
        let tip = AddressBarSwipeTipView(frame: host.bounds)
        tip.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tip.hostView = host
        tip.anchorView = anchor
        tip.onDismiss = onDismiss
        host.addSubview(tip)
        tip.layoutTip()
        UIView.animate(withDuration: 0.28) { tip.alpha = 1 }
        return tip
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTip()
    }

    private func layoutTip() {
        guard let host = hostView, let anchor = anchorView else { return }
        let rect = anchor.convert(anchor.bounds, to: host).insetBy(dx: -4, dy: -4)
        highlight.frame = rect

        let cardWidth = min(host.bounds.width - 32, 340)
        // Size height from content so the body copy is never clipped.
        bodyLabel.preferredMaxLayoutWidth = cardWidth - 32
        let fitting = card.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let cardHeight = ceil(fitting.height)

        let arrowSize: CGFloat = 14
        var cardY = rect.minY - 12 - cardHeight - arrowSize / 2
        if cardY < host.safeAreaInsets.top + 12 {
            cardY = rect.maxY + 12 + arrowSize / 2
        }
        let cardX = max(16, min(rect.midX - cardWidth / 2, host.bounds.width - 16 - cardWidth))
        card.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)

        let arrowAbove = card.frame.maxY <= rect.minY
        arrow.transform = CGAffineTransform(rotationAngle: .pi / 4)
        arrow.bounds = CGRect(x: 0, y: 0, width: arrowSize, height: arrowSize)
        let arrowX = min(max(rect.midX, card.frame.minX + 28), card.frame.maxX - 28)
        if arrowAbove {
            arrow.center = CGPoint(x: arrowX, y: card.frame.maxY - 1)
        } else {
            arrow.center = CGPoint(x: arrowX, y: card.frame.minY + 1)
        }
        bringSubviewToFront(card)
        bringSubviewToFront(arrow)
        bringSubviewToFront(highlight)
    }

    @objc private func dismissTapped() {
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in
            self.removeFromSuperview()
            self.onDismiss?()
        }
    }
}
