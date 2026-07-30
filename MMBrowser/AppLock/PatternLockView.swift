import UIKit

protocol PatternLockViewDelegate: AnyObject {
    func patternLockView(_ view: PatternLockView, didFinishPattern indices: [Int])
}

/// Polished 3×3 pattern grid with outer ring + inner dot, similar to modern lock UIs.
final class PatternLockView: UIView {
    weak var delegate: PatternLockViewDelegate?

    private var nodes: [UIView] = []
    private var innerDots: [UIView] = []
    private var selected: [Int] = []
    private let pathLayer = CAShapeLayer()
    private var currentTouch: CGPoint?
    private let nodeSize: CGFloat = 64
    private let innerSize: CGFloat = 18
    private let accent = UIColor.white

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear

        pathLayer.strokeColor = accent.withAlphaComponent(0.85).cgColor
        pathLayer.fillColor = UIColor.clear.cgColor
        pathLayer.lineWidth = 2.5
        pathLayer.lineCap = .round
        pathLayer.lineJoin = .round
        layer.addSublayer(pathLayer)

        for _ in 0..<9 {
            let ring = UIView()
            ring.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            ring.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
            ring.layer.borderWidth = 1.5
            ring.layer.cornerRadius = nodeSize / 2

            let inner = UIView()
            inner.backgroundColor = UIColor.white.withAlphaComponent(0.55)
            inner.layer.cornerRadius = innerSize / 2
            ring.addSubview(inner)
            inner.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                inner.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
                inner.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
                inner.widthAnchor.constraint(equalToConstant: innerSize),
                inner.heightAnchor.constraint(equalToConstant: innerSize)
            ])

            addSubview(ring)
            nodes.append(ring)
            innerDots.append(inner)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 12
        let usable = bounds.insetBy(dx: inset, dy: inset)
        let stepX = usable.width / 2
        let stepY = usable.height / 2
        for (i, node) in nodes.enumerated() {
            let col = i % 3
            let row = i / 3
            node.bounds = CGRect(x: 0, y: 0, width: nodeSize, height: nodeSize)
            node.center = CGPoint(
                x: usable.minX + CGFloat(col) * stepX,
                y: usable.minY + CGFloat(row) * stepY
            )
        }
        redrawPath()
    }

    func reset(animated: Bool = true) {
        selected.removeAll()
        currentTouch = nil
        for (i, node) in nodes.enumerated() {
            node.backgroundColor = UIColor.white.withAlphaComponent(0.06)
            node.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
            node.transform = .identity
            innerDots[i].backgroundColor = UIColor.white.withAlphaComponent(0.55)
            innerDots[i].transform = .identity
        }
        pathLayer.strokeColor = accent.withAlphaComponent(0.85).cgColor
        redrawPath()
    }

    func flashError() {
        pathLayer.strokeColor = UIColor.systemRed.cgColor
        selected.forEach { idx in
            nodes[idx].layer.borderColor = UIColor.systemRed.cgColor
            innerDots[idx].backgroundColor = UIColor.systemRed
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reset()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset(animated: false)
        guard let point = touches.first?.location(in: self) else { return }
        currentTouch = point
        selectNode(at: point)
        redrawPath()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        currentTouch = point
        selectNode(at: point)
        redrawPath()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentTouch = nil
        redrawPath()
        if selected.count >= 4 {
            delegate?.patternLockView(self, didFinishPattern: selected)
        } else {
            flashError()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }

    private func selectNode(at point: CGPoint) {
        for (index, node) in nodes.enumerated() {
            let hit = node.frame.insetBy(dx: -10, dy: -10)
            if hit.contains(point), !selected.contains(index) {
                selected.append(index)
                node.backgroundColor = UIColor.white.withAlphaComponent(0.14)
                node.layer.borderColor = UIColor.white.cgColor
                innerDots[index].backgroundColor = .white
                UIView.animate(withDuration: 0.12) {
                    self.innerDots[index].transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func redrawPath() {
        let path = UIBezierPath()
        for (i, index) in selected.enumerated() {
            let p = nodes[index].center
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        if let touch = currentTouch, !selected.isEmpty {
            path.addLine(to: touch)
        }
        pathLayer.path = path.cgPath
    }
}
