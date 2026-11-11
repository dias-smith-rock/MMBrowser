import UIKit
import SnapKit

/// AssistiveTouch-style floating control that restores the browser chrome when tapped.
final class ChromeBubbleView: UIControl {
    var onTap: (() -> Void)?
    /// Called after a drag ends so the host can persist position.
    var onDragEnded: ((CGPoint) -> Void)?

    private let ring = UIView()
    private let dot = UIView()
    private var panStartCenter: CGPoint = .zero
    private var didDrag = false

    static let diameter: CGFloat = 56

    override init(frame: CGRect) {
        super.init(frame: frame)
        bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Show address bar and toolbar"
        isUserInteractionEnabled = true

        backgroundColor = UIColor.black.withAlphaComponent(0.28)
        layer.cornerRadius = Self.diameter / 2
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        ring.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        ring.layer.cornerRadius = 18
        ring.isUserInteractionEnabled = false
        addSubview(ring)

        dot.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        dot.layer.cornerRadius = 5
        dot.isUserInteractionEnabled = false
        addSubview(dot)

        ring.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(36)
        }
        dot.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(10)
        }

        addTarget(self, action: #selector(handleTouchUpInside), for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Slightly enlarge the hit target so the bubble is easy to tap.
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    func applyChromeTint(_ color: UIColor?) {
        let accent = color ?? BrowserTheme.chromeBlue
        backgroundColor = accent.withAlphaComponent(0.55)
        ring.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
    }

    @objc private func handleTouchUpInside() {
        guard !didDrag else { return }
        onTap?()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let superview else { return }
        switch gesture.state {
        case .began:
            panStartCenter = center
            didDrag = false
            superview.bringSubviewToFront(self)
            UIView.animate(withDuration: 0.12) {
                self.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                self.alpha = 0.92
            }
        case .changed:
            let translation = gesture.translation(in: superview)
            if hypot(translation.x, translation.y) > 4 {
                didDrag = true
                cancelTracking(with: nil)
            }
            guard didDrag else { return }
            let next = CGPoint(
                x: panStartCenter.x + translation.x,
                y: panStartCenter.y + translation.y
            )
            center = Self.clampedCenter(next, in: superview, size: bounds.size)
        case .ended, .cancelled, .failed:
            UIView.animate(withDuration: 0.18) {
                self.transform = .identity
                self.alpha = 1
            }
            if didDrag {
                onDragEnded?(center)
            }
            // Reset after the run loop so touchUpInside (if any) still sees didDrag.
            DispatchQueue.main.async { [weak self] in
                self?.didDrag = false
            }
        default:
            break
        }
    }

    static func clampedCenter(_ center: CGPoint, in host: UIView, size: CGSize) -> CGPoint {
        let safe = host.safeAreaInsets
        let inset: CGFloat = 8
        let halfW = size.width / 2
        let halfH = size.height / 2
        let minX = safe.left + inset + halfW
        let maxX = max(minX, host.bounds.width - safe.right - inset - halfW)
        let minY = safe.top + inset + halfH
        let maxY = max(minY, host.bounds.height - safe.bottom - inset - halfH)
        return CGPoint(
            x: min(max(center.x, minX), maxX),
            y: min(max(center.y, minY), maxY)
        )
    }

    /// Bottom-center of the screen, just above the home indicator.
    static func defaultCenter(in host: UIView) -> CGPoint {
        let safe = host.safeAreaInsets
        return CGPoint(
            x: host.bounds.midX,
            y: host.bounds.height - safe.bottom - 12 - diameter / 2
        )
    }
}
