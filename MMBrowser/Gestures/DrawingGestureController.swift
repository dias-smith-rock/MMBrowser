import UIKit

protocol DrawingGestureControllerDelegate: AnyObject {
    func drawingGestureController(_ controller: DrawingGestureController, didRecognize shape: GestureShape, action: GestureBrowserAction)
}

/// Two-finger stroke overlay + shape recognition for browser shortcuts.
final class DrawingGestureController: NSObject, UIGestureRecognizerDelegate {
    weak var delegate: DrawingGestureControllerDelegate?

    private weak var hostView: UIView?
    private let overlay = StrokeOverlayView()
    private var pan: UIPanGestureRecognizer?
    private var points: [CGPoint] = []
    private var isEnabled = true
    /// When true, ignores AppSettings.drawingGesturesEnabled (practice pad).
    var ignoresGlobalToggle = false

    func attach(to view: UIView) {
        detach()
        hostView = view
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
        gesture.minimumNumberOfTouches = 2
        gesture.maximumNumberOfTouches = 2
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        pan = gesture
        refreshEnabled()
    }

    func detach() {
        if let pan, let hostView {
            hostView.removeGestureRecognizer(pan)
        }
        pan = nil
        overlay.removeFromSuperview()
        hostView = nil
        points.removeAll()
    }

    func refreshEnabled() {
        isEnabled = ignoresGlobalToggle || AppSettings.drawingGesturesEnabled
        pan?.isEnabled = isEnabled
        if !isEnabled {
            clearStroke(animated: false)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEnabled, let hostView else { return }
        switch gesture.state {
        case .began:
            points.removeAll()
            overlay.alpha = 1
            overlay.clear()
            appendMidpoint(from: gesture, in: hostView)
        case .changed:
            appendMidpoint(from: gesture, in: hostView)
            overlay.update(points: points)
        case .ended, .cancelled, .failed:
            appendMidpoint(from: gesture, in: hostView)
            overlay.update(points: points)
            finishStroke()
        default:
            break
        }
    }

    private func appendMidpoint(from gesture: UIPanGestureRecognizer, in view: UIView) {
        guard gesture.numberOfTouches >= 2 else {
            let p = gesture.location(in: view)
            if points.last.map({ hypot($0.x - p.x, $0.y - p.y) > 2 }) ?? true {
                points.append(p)
            }
            return
        }
        let a = gesture.location(ofTouch: 0, in: view)
        let b = gesture.location(ofTouch: 1, in: view)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        if let last = points.last, hypot(last.x - mid.x, last.y - mid.y) < 2 { return }
        points.append(mid)
    }

    private func finishStroke() {
        let recognized = ShapeRecognizer.recognize(points)
        clearStroke(animated: true)
        guard let shape = recognized else { return }
        let action = GestureActionMap.action(for: shape)
        guard action != .none else { return }
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

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl { return false }
        return isEnabled
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
