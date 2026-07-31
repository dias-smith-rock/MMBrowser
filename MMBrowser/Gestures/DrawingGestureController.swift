import UIKit

protocol DrawingGestureControllerDelegate: AnyObject {
    func drawingGestureController(_ controller: DrawingGestureController, didRecognize shape: GestureShape, action: GestureBrowserAction)
}

/// One-finger stroke overlay + shape recognition for Hook → / ← / ○.
final class DrawingGestureController: NSObject, UIGestureRecognizerDelegate {
    weak var delegate: DrawingGestureControllerDelegate?

    private weak var hostView: UIView?
    weak var scrollViewToLock: UIScrollView?
    private let overlay = StrokeOverlayView()
    private var pan: UIPanGestureRecognizer?
    private var points: [CGPoint] = []
    /// When true, ignores AppSettings toggles (practice pad).
    var ignoresGlobalToggle = false

    private var didLockScrolling = false
    private var savedScrollEnabled = true
    private var savedPinchEnabled = true
    private var savedMinZoom: CGFloat = 1
    private var savedMaxZoom: CGFloat = 1

    func attach(to view: UIView, lockScrollView: UIScrollView? = nil) {
        detach()
        hostView = view
        scrollViewToLock = lockScrollView
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
        gesture.cancelsTouchesInView = true
        view.addGestureRecognizer(gesture)
        pan = gesture
        refreshEnabled()
    }

    func detach() {
        unlockScrolling()
        if let pan, let hostView {
            hostView.removeGestureRecognizer(pan)
        }
        pan = nil
        overlay.removeFromSuperview()
        hostView = nil
        scrollViewToLock = nil
        points.removeAll()
    }

    func refreshEnabled() {
        let on = ignoresGlobalToggle
            || AppSettings.drawingGesturesEnabled
            || AppSettings.navigationSwipeEnabled
        pan?.isEnabled = on
        if !on {
            unlockScrolling()
            clearStroke(animated: false)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let hostView else { return }
        switch gesture.state {
        case .began:
            lockScrolling()
            points.removeAll()
            overlay.alpha = 1
            overlay.clear()
            appendPoint(from: gesture, in: hostView)
        case .changed:
            appendPoint(from: gesture, in: hostView)
            overlay.update(points: points)
        case .ended, .cancelled, .failed:
            appendPoint(from: gesture, in: hostView)
            overlay.update(points: points)
            finishStroke()
            unlockScrolling()
        default:
            break
        }
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

    private func lockScrolling() {
        guard !didLockScrolling, let scroll = scrollViewToLock else { return }
        didLockScrolling = true
        savedScrollEnabled = scroll.isScrollEnabled
        savedPinchEnabled = scroll.pinchGestureRecognizer?.isEnabled ?? true
        savedMinZoom = scroll.minimumZoomScale
        savedMaxZoom = scroll.maximumZoomScale
        scroll.isScrollEnabled = false
        scroll.pinchGestureRecognizer?.isEnabled = false
        let zoom = scroll.zoomScale
        scroll.minimumZoomScale = zoom
        scroll.maximumZoomScale = zoom
        scroll.setContentOffset(scroll.contentOffset, animated: false)
    }

    private func unlockScrolling() {
        guard didLockScrolling, let scroll = scrollViewToLock else {
            didLockScrolling = false
            return
        }
        didLockScrolling = false
        scroll.isScrollEnabled = savedScrollEnabled
        scroll.pinchGestureRecognizer?.isEnabled = savedPinchEnabled
        scroll.minimumZoomScale = savedMinZoom
        scroll.maximumZoomScale = savedMaxZoom
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
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
