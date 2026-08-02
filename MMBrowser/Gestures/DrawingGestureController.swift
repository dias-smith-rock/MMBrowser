import UIKit

protocol DrawingGestureControllerDelegate: AnyObject {
    func drawingGestureController(_ controller: DrawingGestureController, didRecognize shape: GestureShape, action: GestureBrowserAction)
}

/// One-finger stroke overlay + shape recognition for Hook → / ← / ○.
///
/// Never disables `UIScrollView.isScrollEnabled` — toggling that mid-gesture
/// frequently leaves WKWebView unable to scroll until the page is reloaded.
final class DrawingGestureController: NSObject, UIGestureRecognizerDelegate {
    weak var delegate: DrawingGestureControllerDelegate?

    private weak var hostView: UIView?
    private weak var webScrollView: UIScrollView?
    private let overlay = StrokeOverlayView()
    private var pan: UIPanGestureRecognizer?
    private var points: [CGPoint] = []
    /// When true, ignores AppSettings toggles (practice pad).
    var ignoresGlobalToggle = false

    func attach(to view: UIView, lockScrollView: UIScrollView? = nil) {
        detach()
        hostView = view
        webScrollView = lockScrollView
        overlay.isUserInteractionEnabled = false
        overlay.alpha = 0
        view.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.delegate = self
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        // Keep touches flowing to WKWebView so vertical scrolling / pull-to-refresh work.
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        view.addGestureRecognizer(gesture)
        pan = gesture
        refreshEnabled()
    }

    func detach() {
        cancelActiveStroke()
        if let pan, let hostView {
            hostView.removeGestureRecognizer(pan)
        }
        pan = nil
        overlay.removeFromSuperview()
        hostView = nil
        webScrollView = nil
        points.removeAll()
    }

    func refreshEnabled() {
        let on = ignoresGlobalToggle
            || AppSettings.drawingGesturesEnabled
            || AppSettings.navigationSwipeEnabled
        pan?.isEnabled = on
        if !on {
            cancelActiveStroke()
            clearStroke(animated: false)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let hostView else { return }
        switch gesture.state {
        case .began:
            points.removeAll()
            overlay.alpha = 1
            overlay.clear()
            appendPoint(from: gesture, in: hostView)
        case .changed:
            // If the stroke turns into a vertical scroll, yield immediately.
            if isPrimarilyVertical(gesture, in: hostView) {
                cancelActiveStroke()
                return
            }
            appendPoint(from: gesture, in: hostView)
            overlay.update(points: points)
        case .ended, .cancelled, .failed:
            if gesture.state == .ended, !isPrimarilyVertical(gesture, in: hostView) {
                appendPoint(from: gesture, in: hostView)
                overlay.update(points: points)
                finishStroke()
            } else {
                clearStroke(animated: false)
                points.removeAll()
            }
        default:
            break
        }
    }

    private func isPrimarilyVertical(_ gesture: UIPanGestureRecognizer, in view: UIView) -> Bool {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let dx: CGFloat
        let dy: CGFloat
        if abs(velocity.x) + abs(velocity.y) > 40 {
            dx = velocity.x
            dy = velocity.y
        } else {
            dx = translation.x
            dy = translation.y
        }
        // Vertical page scroll / pull-to-refresh — do not treat as a drawing stroke.
        return abs(dy) >= abs(dx) * 1.05
    }

    /// Force-cancel the recognizer so WKWebView keeps the pan for scrolling.
    private func cancelActiveStroke() {
        clearStroke(animated: false)
        points.removeAll()
        guard let pan, pan.isEnabled, pan.state == .began || pan.state == .changed else { return }
        pan.isEnabled = false
        pan.isEnabled = true
    }

    private func appendPoint(from gesture: UIPanGestureRecognizer, in view: UIView) {
        let point = gesture.location(in: view)
        if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 2 { return }
        points.append(point)
    }

    private func finishStroke() {
        let recognized = ShapeRecognizer.recognize(points)
        clearStroke(animated: true)
        guard let shape = recognized else { return }
        let action = GestureActionMap.action(for: shape, respectingToggles: !ignoresGlobalToggle)
        guard action != .none else {
            if ignoresGlobalToggle {
                delegate?.drawingGestureController(self, didRecognize: shape, action: .none)
            }
            return
        }
        delegate?.drawingGestureController(self, didRecognize: shape, action: action)
    }

    private func clearStroke(animated: Bool) {
        points.removeAll()
        let clear = { [weak self] in
            self?.overlay.clear()
            self?.overlay.alpha = 0
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: { self.overlay.alpha = 0 }, completion: { _ in clear() })
        } else {
            clear()
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let hostView else { return true }
        // Practice pad: accept any direction.
        if ignoresGlobalToggle { return true }
        // Only start for clearly non-vertical pans so page scrolling always wins.
        return !isPrimarilyVertical(pan, in: hostView)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if otherGestureRecognizer == webScrollView?.panGestureRecognizer {
            return true
        }
        if otherGestureRecognizer is UIRefreshControl { return true }
        if let otherView = otherGestureRecognizer.view, otherView is UIScrollView {
            return true
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl { return false }
        return ignoresGlobalToggle
            || AppSettings.drawingGesturesEnabled
            || AppSettings.navigationSwipeEnabled
    }
}

private final class StrokeOverlayView: UIView {
    private let strokeLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        strokeLayer.strokeColor = BrowserTheme.chromeBlue.withAlphaComponent(0.85).cgColor
        strokeLayer.fillColor = UIColor.clear.cgColor
        strokeLayer.lineWidth = 3.5
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        layer.addSublayer(strokeLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        strokeLayer.frame = bounds
    }

    func update(points: [CGPoint]) {
        let path = UIBezierPath()
        guard let first = points.first else {
            strokeLayer.path = nil
            return
        }
        path.move(to: first)
        for p in points.dropFirst() {
            path.addLine(to: p)
        }
        strokeLayer.path = path.cgPath
    }

    func clear() {
        strokeLayer.path = nil
    }
}
