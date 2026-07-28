import UIKit

enum ScreenshotCropShape: CaseIterable {
    case rectangle, circle, triangle, heart, diamond, star

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .heart: return "Heart"
        case .diamond: return "Diamond"
        case .star: return "Star"
        }
    }

    func path(in rect: CGRect) -> UIBezierPath {
        switch self {
        case .rectangle:
            return UIBezierPath(rect: rect)
        case .circle:
            return UIBezierPath(ovalIn: rect)
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            return path
        case .heart:
            return ScreenshotShapePaths.heart(in: rect)
        case .diamond:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.close()
            return path
        case .star:
            return ScreenshotShapePaths.star(in: rect)
        }
    }
}

private enum ScreenshotShapePaths {
    static func heart(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let w = rect.width
        let h = rect.height
        let x = rect.minX
        let y = rect.minY
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.28))
        path.addCurve(
            to: CGPoint(x: x + w * 0.05, y: y + h * 0.28),
            controlPoint1: CGPoint(x: x + w * 0.5, y: y + h * 0.05),
            controlPoint2: CGPoint(x: x + w * 0.05, y: y + h * 0.05)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.95),
            controlPoint1: CGPoint(x: x + w * 0.05, y: y + h * 0.55),
            controlPoint2: CGPoint(x: x + w * 0.5, y: y + h * 0.75)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.95, y: y + h * 0.28),
            controlPoint1: CGPoint(x: x + w * 0.5, y: y + h * 0.75),
            controlPoint2: CGPoint(x: x + w * 0.95, y: y + h * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.28),
            controlPoint1: CGPoint(x: x + w * 0.95, y: y + h * 0.05),
            controlPoint2: CGPoint(x: x + w * 0.5, y: y + h * 0.05)
        )
        path.close()
        return path
    }

    static func star(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.5
        let inner = outer * 0.4
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let radius = i % 2 == 0 ? outer : inner
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }
}

private enum ScreenshotArrowStyle: CaseIterable {
    case standard, doubleHead, openHead, dashed

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .doubleHead: return "Double"
        case .openHead: return "Open"
        case .dashed: return "Dashed"
        }
    }
}

private enum ScreenshotTextFont: CaseIterable {
    case systemBold, systemRegular, rounded, monospaced, serif

    var title: String {
        switch self {
        case .systemBold: return "Bold"
        case .systemRegular: return "Regular"
        case .rounded: return "Rounded"
        case .monospaced: return "Mono"
        case .serif: return "Serif"
        }
    }

    func font(size: CGFloat) -> UIFont {
        switch self {
        case .systemBold:
            return .boldSystemFont(ofSize: size)
        case .systemRegular:
            return .systemFont(ofSize: size)
        case .rounded:
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            if let d = base.fontDescriptor.withDesign(.rounded) {
                return UIFont(descriptor: d, size: size)
            }
            return base
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: .semibold)
        case .serif:
            let base = UIFont.systemFont(ofSize: size, weight: .regular)
            if let d = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: d, size: size)
            }
            return base
        }
    }
}

private struct TextAnnotation {
    var origin: CGPoint // normalized 0...1 in selection local space
    var value: String
    var fontSize: CGFloat = 18
    var color: UIColor = .systemRed
    var font: ScreenshotTextFont = .systemBold
    var rotation: CGFloat = 0 // radians
}

private struct ArrowAnnotation {
    var start: CGPoint
    var end: CGPoint
    var style: ScreenshotArrowStyle = .standard
    var color: UIColor = .systemRed
    var lineWidth: CGFloat = 3
}

private enum ScreenshotAnnotation {
    case text(TextAnnotation)
    case arrow(ArrowAnnotation)
}

final class ScreenshotEditorViewController: UIViewController {
    private let sourceImage: UIImage
    private let imageView = UIImageView()
    private let canvas = UIView()
    private let dimView = UIView()
    private let borderLayer = CAShapeLayer()
    private let selectionOutlineLayer = CAShapeLayer()
    private let annotationsHost = UIView()
    private let menuBar = UIScrollView()
    private let menuStack = UIStackView()
    private var cornerHandles: [UIView] = []
    private let rotateHandle = UIView()
    private let rotateStem = CAShapeLayer()

    private var selectionCenter = CGPoint.zero
    private var selectionSize = CGSize.zero
    private var selectionRotation: CGFloat = 0
    private var shape: ScreenshotCropShape = .rectangle
    private var annotations: [ScreenshotAnnotation] = []
    private var selectedAnnotationIndex: Int?
    private var imageFrameInCanvas: CGRect = .zero
    private var didPlaceInitialSelection = false

    private enum Interaction {
        case none
        case moveFrame(startTouch: CGPoint, startCenter: CGPoint)
        case resize(corner: Int, startTouch: CGPoint, startSize: CGSize, startCenter: CGPoint)
        case rotateFrame(startAngle: CGFloat, startRotation: CGFloat)
        case drawArrow(start: CGPoint)
        case moveAnnotation(index: Int, startTouch: CGPoint, startItem: ScreenshotAnnotation)
        case moveArrowEndpoint(index: Int, isStart: Bool)
        case rotateText(index: Int, startAngle: CGFloat, startRotation: CGFloat)
        case rotateArrow(index: Int, startAngle: CGFloat, startStart: CGPoint, startEnd: CGPoint)
    }

    private var interaction: Interaction = .none
    private var arrowMode = false
    private var textMode = false
    private var annotationRotateMode = false
    private var draftArrowEnd: CGPoint?

    private let minSelection: CGFloat = 72
    private let handleSize: CGFloat = 16
    private let frameColor = UIColor.systemRed
    private let floatingMenuHeight: CGFloat = 44
    private let annotationColors: [UIColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .white, .black
    ]

    init(image: UIImage) {
        self.sourceImage = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let start = ScreenshotPerf.now()
        view.backgroundColor = .black

        canvas.clipsToBounds = true
        view.addSubview(canvas)
        canvas.addSubview(imageView)
        imageView.image = sourceImage
        imageView.contentMode = .scaleAspectFit

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        canvas.addSubview(dimView)

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = frameColor.cgColor
        borderLayer.lineWidth = 2.5
        canvas.layer.addSublayer(borderLayer)

        rotateStem.strokeColor = frameColor.cgColor
        rotateStem.lineWidth = 2
        rotateStem.fillColor = UIColor.clear.cgColor
        canvas.layer.addSublayer(rotateStem)

        annotationsHost.isUserInteractionEnabled = false
        canvas.addSubview(annotationsHost)

        selectionOutlineLayer.fillColor = UIColor.clear.cgColor
        selectionOutlineLayer.strokeColor = UIColor.white.cgColor
        selectionOutlineLayer.lineWidth = 1.5
        selectionOutlineLayer.lineDashPattern = [4, 3]
        canvas.layer.addSublayer(selectionOutlineLayer)

        for _ in 0..<4 {
            let handle = makeHandleView()
            canvas.addSubview(handle)
            cornerHandles.append(handle)
        }

        rotateHandle.backgroundColor = .white
        rotateHandle.layer.borderColor = frameColor.cgColor
        rotateHandle.layer.borderWidth = 2
        rotateHandle.layer.cornerRadius = 10
        canvas.addSubview(rotateHandle)
        let rotateIcon = UIImageView(image: UIImage(systemName: "arrow.triangle.2.circlepath"))
        rotateIcon.tintColor = frameColor
        rotateIcon.contentMode = .scaleAspectFit
        rotateHandle.addSubview(rotateIcon)
        rotateIcon.frame = CGRect(x: 4, y: 4, width: 12, height: 12)

        setupMenuBar()
        rebuildMenu()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        canvas.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        canvas.addGestureRecognizer(tap)
        ScreenshotPerf.mark(
            "editor.viewDidLoad",
            since: start,
            extra: "image=\(Int(sourceImage.size.width))x\(Int(sourceImage.size.height))@\(sourceImage.scale)"
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let start = ScreenshotPerf.now()
        ScreenshotPerf.noteLayout()
        let safe = view.safeAreaInsets
        canvas.frame = CGRect(
            x: 0,
            y: safe.top,
            width: view.bounds.width,
            height: max(0, view.bounds.height - safe.top - safe.bottom)
        )
        imageView.frame = canvas.bounds
        annotationsHost.frame = canvas.bounds
        imageFrameInCanvas = aspectFitFrame(imageSize: sourceImage.size, in: canvas.bounds)

        placeInitialSelectionIfNeeded()
        refreshOverlay(source: "layout")
        ScreenshotPerf.mark("editor.viewDidLayoutSubviews", since: start)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let start = ScreenshotPerf.now()
        // First layout can run with empty bounds during presentation; place again when visible.
        placeInitialSelectionIfNeeded()
        refreshOverlay(source: "appear")
        ScreenshotPerf.mark("editor.viewDidAppear", since: start)
        ScreenshotPerf.endSessionSummary()
    }

    private func placeInitialSelectionIfNeeded() {
        guard imageFrameInCanvas.width > 1, imageFrameInCanvas.height > 1 else { return }
        let centerInside = imageFrameInCanvas.insetBy(dx: 20, dy: 20).contains(selectionCenter)
        let needsPlacement = !didPlaceInitialSelection
            || selectionSize.width < 1
            || selectionSize.height < 1
            || !centerInside
        guard needsPlacement else { return }

        let side = min(imageFrameInCanvas.width, imageFrameInCanvas.height) * 0.55
        selectionSize = CGSize(width: max(minSelection, side), height: max(minSelection, side))
        selectionCenter = CGPoint(x: imageFrameInCanvas.midX, y: imageFrameInCanvas.midY)
        selectionRotation = 0
        didPlaceInitialSelection = true
    }

    private func makeHandleView() -> UIView {
        let handle = UIView()
        handle.backgroundColor = .white
        handle.layer.borderColor = frameColor.cgColor
        handle.layer.borderWidth = 2
        handle.layer.cornerRadius = 3
        return handle
    }

    private func setupMenuBar() {
        view.addSubview(menuBar)
        menuBar.showsHorizontalScrollIndicator = false
        menuBar.backgroundColor = UIColor(white: 0.12, alpha: 0.92)
        menuBar.layer.cornerRadius = 14
        menuBar.layer.borderWidth = 1
        menuBar.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        menuBar.clipsToBounds = true
        menuBar.addSubview(menuStack)
        menuStack.axis = .horizontal
        menuStack.spacing = 6
        menuStack.alignment = .center
    }

    private func makeMenuButton(symbol: String, title: String, action: Selector, selected: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        let side: CGFloat = 36
        button.backgroundColor = selected ? frameColor : UIColor(white: 0.22, alpha: 1)
        button.layer.cornerRadius = 8
        button.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.accessibilityLabel = title
        button.accessibilityTraits = selected ? [.button, .selected] : .button
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: side),
            button.heightAnchor.constraint(equalToConstant: side)
        ])
        return button
    }

    private func rebuildMenu() {
        menuStack.arrangedSubviews.forEach {
            menuStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let items: [(String, String, Selector, Bool)]
        if let index = selectedAnnotationIndex, annotations.indices.contains(index) {
            switch annotations[index] {
            case .text:
                items = [
                    ("textformat.size", "Size", #selector(textSizeTapped), false),
                    ("paintpalette", "Color", #selector(textColorTapped), false),
                    ("textformat", "Font", #selector(textFontTapped), false),
                    ("rotate.right", "Rotate", #selector(textRotateTapped), annotationRotateMode),
                    ("checkmark", "Done", #selector(deselectTapped), false)
                ]
            case .arrow:
                items = [
                    ("arrow.triangle.branch", "Style", #selector(arrowStyleTapped), false),
                    ("paintpalette", "Color", #selector(arrowColorTapped), false),
                    ("pencil.tip", "Width", #selector(arrowWidthTapped), false),
                    ("arrow.clockwise", "Angle", #selector(arrowAngleTapped), annotationRotateMode),
                    ("checkmark", "Done", #selector(deselectTapped), false)
                ]
            }
        } else {
            items = [
                ("arrow.up.right", "Arrow", #selector(addArrowTapped), arrowMode),
                ("textformat", "Text", #selector(addTextTapped), textMode),
                ("square.on.circle", "Shape", #selector(changeShapeTapped), false),
                ("rotate.right", "Rotate", #selector(frameRotateTapped), false),
                ("square.and.arrow.down", "Album", #selector(saveAlbumTapped), false),
                ("doc.on.clipboard", "Copy", #selector(saveClipboardTapped), false),
                ("xmark", "Cancel", #selector(cancelTapped), false)
            ]
        }

        for (symbol, title, sel, selected) in items {
            menuStack.addArrangedSubview(makeMenuButton(symbol: symbol, title: title, action: sel, selected: selected))
        }
        layoutMenuNearFrame()
    }

    private func layoutMenuNearFrame() {
        menuStack.layoutIfNeeded()
        let contentWidth = menuStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width + 16
        let menuWidth = min(view.bounds.width - 24, max(contentWidth, 44))
        let menuHeight = floatingMenuHeight
        let aabb = selectionAABB()
        let gap: CGFloat = 14
        let preferBelow = aabb.maxY + gap + menuHeight + 8 < canvas.bounds.height
        var menuY = preferBelow
            ? canvas.frame.minY + aabb.maxY + gap
            : canvas.frame.minY + aabb.minY - gap - menuHeight
        menuY = min(
            max(menuY, view.safeAreaInsets.top + 4),
            view.bounds.height - view.safeAreaInsets.bottom - menuHeight - 4
        )
        var menuX = canvas.frame.minX + aabb.midX - menuWidth / 2
        menuX = min(max(12, menuX), view.bounds.width - menuWidth - 12)
        menuBar.frame = CGRect(x: menuX, y: menuY, width: menuWidth, height: menuHeight)
        menuStack.frame = CGRect(x: 8, y: 4, width: contentWidth - 16, height: menuHeight - 8)
        menuBar.contentSize = CGSize(width: max(menuWidth, contentWidth), height: menuHeight)
    }

    // MARK: - Geometry

    private func selectionTransform() -> CGAffineTransform {
        CGAffineTransform(translationX: selectionCenter.x, y: selectionCenter.y)
            .rotated(by: selectionRotation)
    }

    private func localRect() -> CGRect {
        CGRect(
            x: -selectionSize.width / 2,
            y: -selectionSize.height / 2,
            width: selectionSize.width,
            height: selectionSize.height
        )
    }

    private func selectionPathInCanvas() -> UIBezierPath {
        let path = shape.path(in: localRect())
        path.apply(selectionTransform())
        return path
    }

    private func selectionAABB() -> CGRect {
        selectionPathInCanvas().bounds.insetBy(dx: -2, dy: -2)
    }

    private func toLocal(_ point: CGPoint) -> CGPoint {
        point.applying(selectionTransform().inverted())
    }

    private func toCanvas(_ local: CGPoint) -> CGPoint {
        local.applying(selectionTransform())
    }

    private func absolutePoint(_ normalized: CGPoint) -> CGPoint {
        let local = CGPoint(
            x: (normalized.x - 0.5) * selectionSize.width,
            y: (normalized.y - 0.5) * selectionSize.height
        )
        return toCanvas(local)
    }

    private func normalizedPoint(fromCanvas point: CGPoint) -> CGPoint {
        let local = toLocal(point)
        guard selectionSize.width > 0, selectionSize.height > 0 else { return .zero }
        return CGPoint(
            x: local.x / selectionSize.width + 0.5,
            y: local.y / selectionSize.height + 0.5
        )
    }

    private func clampNormalized(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0.02), 0.98), y: min(max(point.y, 0.02), 0.98))
    }

    private func aspectFitFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clampSelectionCenterAndSize() {
        guard imageFrameInCanvas.width > 1, imageFrameInCanvas.height > 1 else { return }

        selectionSize.width = max(minSelection, selectionSize.width)
        selectionSize.height = max(minSelection, selectionSize.height)
        let maxW = imageFrameInCanvas.width
        let maxH = imageFrameInCanvas.height
        if selectionSize.width > maxW { selectionSize.width = maxW }
        if selectionSize.height > maxH { selectionSize.height = maxH }

        // Keep center roughly inside image frame.
        let inset: CGFloat = 8
        selectionCenter.x = min(max(selectionCenter.x, imageFrameInCanvas.minX + inset), imageFrameInCanvas.maxX - inset)
        selectionCenter.y = min(max(selectionCenter.y, imageFrameInCanvas.minY + inset), imageFrameInCanvas.maxY - inset)
    }

    // MARK: - Overlay

    private func refreshOverlay(source: String = "unknown") {
        guard canvas.bounds.width > 1, canvas.bounds.height > 1 else { return }
        clampSelectionCenterAndSize()
        guard selectionSize.width > 1, selectionSize.height > 1 else { return }

        let totalStart = ScreenshotPerf.now()
        var t0 = totalStart

        let cutout = selectionPathInCanvas()
        let pathMs = (ScreenshotPerf.now() - t0) * 1000
        t0 = ScreenshotPerf.now()

        let maskPath = UIBezierPath(rect: canvas.bounds)
        maskPath.append(cutout)
        maskPath.usesEvenOddFillRule = true
        let maskLayer = CAShapeLayer()
        maskLayer.path = maskPath.cgPath
        maskLayer.fillRule = .evenOdd
        dimView.frame = canvas.bounds
        dimView.layer.mask = maskLayer
        let maskMs = (ScreenshotPerf.now() - t0) * 1000
        t0 = ScreenshotPerf.now()

        borderLayer.path = cutout.cgPath
        // Keep stroke above the dim mask hole.
        canvas.layer.insertSublayer(borderLayer, above: dimView.layer)
        canvas.layer.insertSublayer(rotateStem, above: borderLayer)
        let borderMs = (ScreenshotPerf.now() - t0) * 1000
        t0 = ScreenshotPerf.now()

        updateHandles()
        let handlesMs = (ScreenshotPerf.now() - t0) * 1000
        t0 = ScreenshotPerf.now()

        redrawAnnotations()
        let annMs = (ScreenshotPerf.now() - t0) * 1000
        t0 = ScreenshotPerf.now()

        updateSelectionOutline()
        layoutMenuNearFrame()
        bringChromeToFront()
        let chromeMs = (ScreenshotPerf.now() - t0) * 1000

        let totalMs = (ScreenshotPerf.now() - totalStart) * 1000
        let breakdown = String(
            format: "path=%.1f mask=%.1f border=%.1f handles=%.1f ann=%.1f chrome=%.1f",
            pathMs, maskMs, borderMs, handlesMs, annMs, chromeMs
        )
        ScreenshotPerf.noteRefresh(source: source, durationMs: totalMs, breakdown: breakdown)
        if source.hasPrefix("pan") {
            ScreenshotPerf.notePanRefresh(durationMs: totalMs)
        }
    }

    private func bringChromeToFront() {
        canvas.bringSubviewToFront(annotationsHost)
        for handle in cornerHandles {
            canvas.bringSubviewToFront(handle)
        }
        canvas.bringSubviewToFront(rotateHandle)
        if let outline = selectionOutlineLayer.superlayer {
            outline.insertSublayer(selectionOutlineLayer, at: UInt32(outline.sublayers?.count ?? 0))
        }
    }

    private func updateHandles() {
        // Arrow selection: only start / end / mid (3 nodes). Hide crop frame chrome.
        if let index = selectedAnnotationIndex,
           case .arrow(let arrow) = annotations[index] {
            let start = absolutePoint(arrow.start)
            let end = absolutePoint(arrow.end)
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let points = [start, end, mid]
            for (i, handle) in cornerHandles.enumerated() {
                if i < 3 {
                    handle.isHidden = false
                    handle.bounds = CGRect(x: 0, y: 0, width: handleSize, height: handleSize)
                    handle.center = points[i]
                    handle.transform = .identity
                } else {
                    handle.isHidden = true
                }
            }
            rotateHandle.isHidden = true
            rotateStem.path = nil
            return
        }

        // Text selection: corners on the text box + rotate handle. Hide crop-frame chrome.
        if let index = selectedAnnotationIndex,
           case .text(let text) = annotations[index] {
            let geometry = textSelectionGeometry(text)
            for (i, handle) in cornerHandles.enumerated() {
                handle.isHidden = false
                handle.bounds = CGRect(x: 0, y: 0, width: handleSize, height: handleSize)
                handle.center = geometry.corners[i]
                handle.transform = CGAffineTransform(rotationAngle: geometry.rotation)
            }
            let stem = UIBezierPath()
            stem.move(to: geometry.topMid)
            stem.addLine(to: geometry.rotate)
            rotateStem.path = stem.cgPath
            rotateHandle.isHidden = false
            rotateHandle.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
            rotateHandle.center = geometry.rotate
            return
        }

        for handle in cornerHandles { handle.isHidden = false }
        rotateHandle.isHidden = false

        let localCorners = [
            CGPoint(x: -selectionSize.width / 2, y: -selectionSize.height / 2),
            CGPoint(x: selectionSize.width / 2, y: -selectionSize.height / 2),
            CGPoint(x: -selectionSize.width / 2, y: selectionSize.height / 2),
            CGPoint(x: selectionSize.width / 2, y: selectionSize.height / 2)
        ]
        for (index, handle) in cornerHandles.enumerated() {
            handle.bounds = CGRect(x: 0, y: 0, width: handleSize, height: handleSize)
            handle.center = toCanvas(localCorners[index])
            handle.transform = CGAffineTransform(rotationAngle: selectionRotation)
        }

        let rotateLocal = CGPoint(x: 0, y: -selectionSize.height / 2 - 28)
        let rotateCanvas = toCanvas(rotateLocal)
        let topMid = toCanvas(CGPoint(x: 0, y: -selectionSize.height / 2))
        let stem = UIBezierPath()
        stem.move(to: topMid)
        stem.addLine(to: rotateCanvas)
        rotateStem.path = stem.cgPath

        rotateHandle.bounds = CGRect(x: 0, y: 0, width: 20, height: 20)
        rotateHandle.center = rotateCanvas
    }

    private struct TextSelectionGeometry {
        var corners: [CGPoint]
        var topMid: CGPoint
        var rotate: CGPoint
        var rotation: CGFloat
        var center: CGPoint
    }

    private func textSelectionGeometry(_ text: TextAnnotation) -> TextSelectionGeometry {
        let font = text.font.font(size: text.fontSize)
        let size = (text.value as NSString).size(withAttributes: [.font: font])
        let pad: CGFloat = 10
        let halfW = size.width / 2 + pad
        let halfH = size.height / 2 + pad
        let rotation = selectionRotation + text.rotation
        let center = absolutePoint(text.origin)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
        let locals = [
            CGPoint(x: -halfW, y: -halfH),
            CGPoint(x: halfW, y: -halfH),
            CGPoint(x: -halfW, y: halfH),
            CGPoint(x: halfW, y: halfH)
        ]
        let corners = locals.map { $0.applying(transform) }
        let topMid = CGPoint(x: 0, y: -halfH).applying(transform)
        let rotate = CGPoint(x: 0, y: -halfH - 28).applying(transform)
        return TextSelectionGeometry(
            corners: corners,
            topMid: topMid,
            rotate: rotate,
            rotation: rotation,
            center: center
        )
    }

    private func updateSelectionOutline() {
        guard let index = selectedAnnotationIndex, annotations.indices.contains(index) else {
            selectionOutlineLayer.path = nil
            return
        }
        switch annotations[index] {
        case .text(let text):
            // Solid high-contrast box so selection stays visible on busy pages / red text.
            selectionOutlineLayer.lineDashPattern = nil
            selectionOutlineLayer.lineWidth = 2.5
            selectionOutlineLayer.strokeColor = frameColor.cgColor
            selectionOutlineLayer.fillColor = UIColor.clear.cgColor
            let font = text.font.font(size: text.fontSize)
            let size = (text.value as NSString).size(withAttributes: [.font: font])
            let pad: CGFloat = 10
            let rect = CGRect(
                x: -size.width / 2 - pad,
                y: -size.height / 2 - pad,
                width: size.width + pad * 2,
                height: size.height + pad * 2
            )
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            var t = CGAffineTransform(translationX: absolutePoint(text.origin).x, y: absolutePoint(text.origin).y)
            t = t.rotated(by: selectionRotation + text.rotation)
            path.apply(t)
            selectionOutlineLayer.path = path.cgPath
        case .arrow:
            // Don't overlay a dashed stroke on the arrow — it makes solid arrows look dashed.
            // The three endpoint handles already indicate selection.
            selectionOutlineLayer.path = nil
        }
    }

    // MARK: - Hit testing

    private func handleIndex(at point: CGPoint) -> Int? {
        for (index, handle) in cornerHandles.enumerated() {
            if handle.isHidden { continue }
            if handle.frame.insetBy(dx: -12, dy: -12).contains(point) { return index }
        }
        return nil
    }

    /// 0 = start, 1 = end, 2 = mid (move). Only valid while an arrow is selected.
    private func arrowHandleIndex(at point: CGPoint) -> Int? {
        guard let index = selectedAnnotationIndex,
              case .arrow = annotations[index] else { return nil }
        for i in 0..<min(3, cornerHandles.count) {
            let handle = cornerHandles[i]
            if handle.isHidden { continue }
            if handle.frame.insetBy(dx: -12, dy: -12).contains(point) { return i }
        }
        return nil
    }

    private func isRotateHandle(at point: CGPoint) -> Bool {
        guard !rotateHandle.isHidden else { return false }
        return rotateHandle.frame.insetBy(dx: -14, dy: -14).contains(point)
    }

    private func isInsideSelection(at point: CGPoint) -> Bool {
        let local = toLocal(point)
        return localRect().insetBy(dx: -8, dy: -8).contains(local)
    }

    private func annotationIndex(at point: CGPoint) -> Int? {
        for index in annotations.indices.reversed() {
            switch annotations[index] {
            case .text(let text):
                let center = absolutePoint(text.origin)
                let font = text.font.font(size: text.fontSize)
                let size = (text.value as NSString).size(withAttributes: [.font: font])
                var local = point
                local.x -= center.x
                local.y -= center.y
                local = local.applying(CGAffineTransform(rotationAngle: -(selectionRotation + text.rotation)))
                let hit = CGRect(
                    x: -size.width / 2 - 14,
                    y: -size.height / 2 - 14,
                    width: size.width + 28,
                    height: size.height + 28
                )
                if hit.contains(local) { return index }
            case .arrow(let arrow):
                let s = absolutePoint(arrow.start)
                let e = absolutePoint(arrow.end)
                if distanceToSegment(point, s, e) < max(18, arrow.lineWidth + 12) { return index }
            }
        }
        return nil
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0.5 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2
        t = min(max(t, 0), 1)
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    // MARK: - Gestures

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: canvas)

        switch gesture.state {
        case .began:
            if arrowMode {
                selectedAnnotationIndex = nil
                rebuildMenu()
                interaction = .drawArrow(start: point)
                draftArrowEnd = point
                return
            }
            // Arrow endpoint / mid nodes take priority over crop-frame chrome.
            if let arrowIndex = selectedAnnotationIndex,
               case .arrow(let arrow) = annotations[arrowIndex],
               let handle = arrowHandleIndex(at: point) {
                if handle == 2 {
                    interaction = .moveAnnotation(
                        index: arrowIndex,
                        startTouch: point,
                        startItem: .arrow(arrow)
                    )
                } else {
                    interaction = .moveArrowEndpoint(index: arrowIndex, isStart: handle == 0)
                }
                return
            }
            // Text selection chrome: rotate handle / corners act on the text, not the crop frame.
            if let textIndex = selectedAnnotationIndex,
               case .text(let text) = annotations[textIndex] {
                if isRotateHandle(at: point) {
                    let center = absolutePoint(text.origin)
                    let angle = atan2(point.y - center.y, point.x - center.x)
                    interaction = .rotateText(index: textIndex, startAngle: angle, startRotation: text.rotation)
                    return
                }
                if handleIndex(at: point) != nil {
                    interaction = .moveAnnotation(
                        index: textIndex,
                        startTouch: point,
                        startItem: .text(text)
                    )
                    return
                }
            }
            if selectedAnnotationIndex == nil, isRotateHandle(at: point) {
                let angle = atan2(point.y - selectionCenter.y, point.x - selectionCenter.x)
                interaction = .rotateFrame(startAngle: angle, startRotation: selectionRotation)
            } else if selectedAnnotationIndex == nil, let corner = handleIndex(at: point) {
                interaction = .resize(
                    corner: corner,
                    startTouch: point,
                    startSize: selectionSize,
                    startCenter: selectionCenter
                )
            } else if let index = annotationIndex(at: point) {
                if selectedAnnotationIndex != index {
                    selectedAnnotationIndex = index
                    annotationRotateMode = false
                    arrowMode = false
                    textMode = false
                    rebuildMenu()
                    refreshOverlay(source: "select")
                }
                if annotationRotateMode, case .text(let text) = annotations[index] {
                    let center = absolutePoint(text.origin)
                    let angle = atan2(point.y - center.y, point.x - center.x)
                    interaction = .rotateText(index: index, startAngle: angle, startRotation: text.rotation)
                } else if annotationRotateMode, case .arrow(let arrow) = annotations[index] {
                    let mid = CGPoint(x: (arrow.start.x + arrow.end.x) / 2, y: (arrow.start.y + arrow.end.y) / 2)
                    let midCanvas = absolutePoint(mid)
                    let angle = atan2(point.y - midCanvas.y, point.x - midCanvas.x)
                    interaction = .rotateArrow(
                        index: index,
                        startAngle: angle,
                        startStart: arrow.start,
                        startEnd: arrow.end
                    )
                } else {
                    interaction = .moveAnnotation(index: index, startTouch: point, startItem: annotations[index])
                }
            } else if isInsideSelection(at: point) {
                if selectedAnnotationIndex != nil {
                    selectedAnnotationIndex = nil
                    annotationRotateMode = false
                    rebuildMenu()
                    updateHandles()
                    updateSelectionOutline()
                }
                interaction = .moveFrame(startTouch: point, startCenter: selectionCenter)
            } else {
                interaction = .none
            }
        case .changed:
            switch interaction {
            case .moveFrame(let startTouch, let startCenter):
                selectionCenter = CGPoint(
                    x: startCenter.x + point.x - startTouch.x,
                    y: startCenter.y + point.y - startTouch.y
                )
                refreshOverlay(source: "pan.move")
            case .resize(let corner, let startTouch, let startSize, let startCenter):
                applyResize(corner: corner, startTouch: startTouch, startSize: startSize, startCenter: startCenter, current: point)
                refreshOverlay(source: "pan.resize")
            case .rotateFrame(let startAngle, let startRotation):
                let angle = atan2(point.y - selectionCenter.y, point.x - selectionCenter.x)
                selectionRotation = startRotation + (angle - startAngle)
                refreshOverlay(source: "pan.rotate")
            case .moveAnnotation(let index, let startTouch, let startItem):
                let startLocal = toLocal(startTouch)
                let curLocal = toLocal(point)
                let dxNorm = (curLocal.x - startLocal.x) / selectionSize.width
                let dyNorm = (curLocal.y - startLocal.y) / selectionSize.height
                annotations[index] = translatedAnnotation(startItem, dxNorm: dxNorm, dyNorm: dyNorm)
                redrawAnnotations()
                updateSelectionOutline()
                updateHandles()
                layoutMenuNearFrame()
            case .moveArrowEndpoint(let index, let isStart):
                guard case .arrow(var arrow) = annotations[index] else { break }
                let p = clampNormalized(normalizedPoint(fromCanvas: point))
                if isStart {
                    arrow.start = p
                } else {
                    arrow.end = p
                }
                annotations[index] = .arrow(arrow)
                redrawAnnotations()
                updateSelectionOutline()
                updateHandles()
                layoutMenuNearFrame()
            case .rotateText(let index, let startAngle, let startRotation):
                guard case .text(var text) = annotations[index] else { break }
                let center = absolutePoint(text.origin)
                let angle = atan2(point.y - center.y, point.x - center.x)
                text.rotation = startRotation + (angle - startAngle)
                annotations[index] = .text(text)
                redrawAnnotations()
                updateSelectionOutline()
                updateHandles()
                layoutMenuNearFrame()
            case .rotateArrow(let index, let startAngle, let startStart, let startEnd):
                guard case .arrow(var arrow) = annotations[index] else { break }
                let mid = CGPoint(x: (startStart.x + startEnd.x) / 2, y: (startStart.y + startEnd.y) / 2)
                let midCanvas = absolutePoint(mid)
                let angle = atan2(point.y - midCanvas.y, point.x - midCanvas.x)
                let delta = angle - startAngle
                arrow.start = rotateNormalized(startStart, around: mid, by: delta)
                arrow.end = rotateNormalized(startEnd, around: mid, by: delta)
                annotations[index] = .arrow(arrow)
                redrawAnnotations()
                updateSelectionOutline()
                updateHandles()
                layoutMenuNearFrame()
            case .drawArrow(let start):
                draftArrowEnd = point
                redrawAnnotations(draftArrow: (start, point))
            case .none:
                break
            }
        case .ended, .cancelled:
            if case .drawArrow(let start) = interaction, let end = draftArrowEnd {
                arrowMode = false
                if hypot(end.x - start.x, end.y - start.y) > 16 {
                    let arrow = ArrowAnnotation(
                        start: clampNormalized(normalizedPoint(fromCanvas: start)),
                        end: clampNormalized(normalizedPoint(fromCanvas: end))
                    )
                    annotations.append(.arrow(arrow))
                    selectedAnnotationIndex = annotations.count - 1
                    annotationRotateMode = false
                }
                draftArrowEnd = nil
                rebuildMenu()
                redrawAnnotations()
                updateHandles()
                updateSelectionOutline()
                layoutMenuNearFrame()
            }
            if case .rotateText = interaction {
                annotationRotateMode = false
                rebuildMenu()
            }
            if case .rotateArrow = interaction {
                annotationRotateMode = false
                rebuildMenu()
            }
            interaction = .none
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: canvas)

        if textMode {
            textMode = false
            rebuildMenu()
            let alert = UIAlertController(title: "Add Text", message: nil, preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "Enter text" }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
                guard let self = self else { return }
                guard let value = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else { return }
                let text = TextAnnotation(origin: self.clampNormalized(self.normalizedPoint(fromCanvas: point)), value: value)
                self.annotations.append(.text(text))
                self.selectedAnnotationIndex = self.annotations.count - 1
                self.rebuildMenu()
                self.redrawAnnotations()
                self.updateSelectionOutline()
            })
            present(alert, animated: true)
            return
        }

        if let index = annotationIndex(at: point) {
            selectedAnnotationIndex = index
            annotationRotateMode = false
            rebuildMenu()
            updateHandles()
            updateSelectionOutline()
            layoutMenuNearFrame()
            return
        }

        if selectedAnnotationIndex != nil {
            selectedAnnotationIndex = nil
            annotationRotateMode = false
            rebuildMenu()
            updateHandles()
            updateSelectionOutline()
            layoutMenuNearFrame()
        }
    }

    private func textValue(at index: Int) -> TextAnnotation? {
        if case .text(let t) = annotations[index] { return t }
        return nil
    }

    private func applyResize(
        corner: Int,
        startTouch: CGPoint,
        startSize: CGSize,
        startCenter: CGPoint,
        current: CGPoint
    ) {
        let startLocal = startTouch.applying(
            CGAffineTransform(translationX: startCenter.x, y: startCenter.y)
                .rotated(by: selectionRotation)
                .inverted()
        )
        let curLocal = current.applying(
            CGAffineTransform(translationX: startCenter.x, y: startCenter.y)
                .rotated(by: selectionRotation)
                .inverted()
        )
        let dx = curLocal.x - startLocal.x
        let dy = curLocal.y - startLocal.y

        var size = startSize
        var centerLocal = CGPoint.zero
        switch corner {
        case 0: // top-left
            size.width = max(minSelection, startSize.width - dx)
            size.height = max(minSelection, startSize.height - dy)
            centerLocal = CGPoint(x: (startSize.width - size.width) / 2, y: (startSize.height - size.height) / 2)
        case 1: // top-right
            size.width = max(minSelection, startSize.width + dx)
            size.height = max(minSelection, startSize.height - dy)
            centerLocal = CGPoint(x: (size.width - startSize.width) / 2, y: (startSize.height - size.height) / 2)
        case 2: // bottom-left
            size.width = max(minSelection, startSize.width - dx)
            size.height = max(minSelection, startSize.height + dy)
            centerLocal = CGPoint(x: (startSize.width - size.width) / 2, y: (size.height - startSize.height) / 2)
        default: // bottom-right
            size.width = max(minSelection, startSize.width + dx)
            size.height = max(minSelection, startSize.height + dy)
            centerLocal = CGPoint(x: (size.width - startSize.width) / 2, y: (size.height - startSize.height) / 2)
        }
        selectionSize = size
        selectionCenter = centerLocal.applying(
            CGAffineTransform(translationX: startCenter.x, y: startCenter.y).rotated(by: selectionRotation)
        )
    }

    private func translatedAnnotation(_ item: ScreenshotAnnotation, dxNorm: CGFloat, dyNorm: CGFloat) -> ScreenshotAnnotation {
        switch item {
        case .arrow(var arrow):
            let (dx, dy) = clampedDelta(dxNorm, dyNorm, for: [arrow.start, arrow.end])
            arrow.start = CGPoint(x: arrow.start.x + dx, y: arrow.start.y + dy)
            arrow.end = CGPoint(x: arrow.end.x + dx, y: arrow.end.y + dy)
            return .arrow(arrow)
        case .text(var text):
            let (dx, dy) = clampedDelta(dxNorm, dyNorm, for: [text.origin])
            text.origin = CGPoint(x: text.origin.x + dx, y: text.origin.y + dy)
            return .text(text)
        }
    }

    private func clampedDelta(_ dx: CGFloat, _ dy: CGFloat, for points: [CGPoint]) -> (CGFloat, CGFloat) {
        var dx = dx
        var dy = dy
        let lo: CGFloat = 0.02
        let hi: CGFloat = 0.98
        for _ in 0..<2 {
            for p in points {
                if p.x + dx < lo { dx = lo - p.x }
                if p.x + dx > hi { dx = hi - p.x }
                if p.y + dy < lo { dy = lo - p.y }
                if p.y + dy > hi { dy = hi - p.y }
            }
        }
        return (dx, dy)
    }

    private func rotateNormalized(_ point: CGPoint, around mid: CGPoint, by delta: CGFloat) -> CGPoint {
        let dx = point.x - mid.x
        let dy = point.y - mid.y
        let c = cos(delta)
        let s = sin(delta)
        return clampNormalized(CGPoint(
            x: mid.x + dx * c - dy * s,
            y: mid.y + dx * s + dy * c
        ))
    }

    // MARK: - Drawing annotations

    private func redrawAnnotations(draftArrow: (CGPoint, CGPoint)? = nil) {
        let start = ScreenshotPerf.now()
        annotationsHost.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        annotationsHost.subviews.forEach { $0.removeFromSuperview() }

        for (index, item) in annotations.enumerated() {
            switch item {
            case .arrow(let arrow):
                let layer = CAShapeLayer()
                let path = arrowPath(
                    from: absolutePoint(arrow.start),
                    to: absolutePoint(arrow.end),
                    style: arrow.style,
                    lineWidth: arrow.lineWidth
                )
                layer.path = path.cgPath
                layer.fillColor = UIColor.clear.cgColor
                layer.strokeColor = arrow.color.cgColor
                layer.lineWidth = arrow.lineWidth
                layer.lineCap = .round
                layer.lineJoin = .round
                if arrow.style == .dashed {
                    layer.lineDashPattern = [6, 4]
                }
                if selectedAnnotationIndex == index {
                    layer.shadowColor = UIColor.white.cgColor
                    layer.shadowOpacity = 0.9
                    layer.shadowRadius = 3
                    layer.shadowOffset = .zero
                }
                annotationsHost.layer.addSublayer(layer)
            case .text(let text):
                let label = UILabel()
                label.text = text.value
                label.textColor = text.color
                label.font = text.font.font(size: text.fontSize)
                label.sizeToFit()
                label.center = absolutePoint(text.origin)
                label.transform = CGAffineTransform(rotationAngle: selectionRotation + text.rotation)
                if selectedAnnotationIndex == index {
                    label.layer.shadowColor = UIColor.white.cgColor
                    label.layer.shadowOpacity = 0.9
                    label.layer.shadowRadius = 3
                    label.layer.shadowOffset = .zero
                }
                annotationsHost.addSubview(label)
            }
        }

        if let draft = draftArrow {
            let layer = CAShapeLayer()
            layer.path = arrowPath(from: draft.0, to: draft.1, style: .standard, lineWidth: 3).cgPath
            layer.fillColor = UIColor.clear.cgColor
            layer.strokeColor = frameColor.cgColor
            layer.lineWidth = 3
            layer.lineCap = .round
            annotationsHost.layer.addSublayer(layer)
        }
        let ms = (ScreenshotPerf.now() - start) * 1000
        if ms >= 4 {
            ScreenshotPerf.mark("editor.redrawAnnotations", since: start, extra: "count=\(annotations.count)")
        }
    }

    private func arrowPath(from start: CGPoint, to end: CGPoint, style: ScreenshotArrowStyle, lineWidth: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = max(12, lineWidth * 4)

        func addHead(at tip: CGPoint, direction: CGFloat, open: Bool) {
            let left = CGPoint(
                x: tip.x - head * cos(direction - .pi / 6),
                y: tip.y - head * sin(direction - .pi / 6)
            )
            let right = CGPoint(
                x: tip.x - head * cos(direction + .pi / 6),
                y: tip.y - head * sin(direction + .pi / 6)
            )
            if open {
                path.move(to: left)
                path.addLine(to: tip)
                path.addLine(to: right)
            } else {
                path.move(to: left)
                path.addLine(to: tip)
                path.addLine(to: right)
            }
        }

        path.move(to: start)
        path.addLine(to: end)
        switch style {
        case .standard, .dashed:
            addHead(at: end, direction: angle, open: false)
        case .openHead:
            addHead(at: end, direction: angle, open: true)
        case .doubleHead:
            addHead(at: end, direction: angle, open: false)
            addHead(at: start, direction: angle + .pi, open: false)
        }
        return path
    }

    // MARK: - Default menu

    @objc private func addArrowTapped() {
        selectedAnnotationIndex = nil
        annotationRotateMode = false
        if arrowMode {
            arrowMode = false
        } else {
            arrowMode = true
            textMode = false
        }
        rebuildMenu()
        updateSelectionOutline()
    }

    @objc private func addTextTapped() {
        selectedAnnotationIndex = nil
        annotationRotateMode = false
        if textMode {
            textMode = false
        } else {
            textMode = true
            arrowMode = false
        }
        rebuildMenu()
        updateSelectionOutline()
    }

    @objc private func changeShapeTapped() {
        arrowMode = false
        textMode = false
        rebuildMenu()
        let sheet = UIAlertController(title: "Crop Shape", message: nil, preferredStyle: .actionSheet)
        for item in ScreenshotCropShape.allCases {
            sheet.addAction(UIAlertAction(title: item.title, style: .default) { [weak self] _ in
                self?.shape = item
                self?.refreshOverlay(source: "shape")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func frameRotateTapped() {
        arrowMode = false
        textMode = false
        rebuildMenu()
        selectionRotation += .pi / 12
        refreshOverlay(source: "menu.rotate")
    }

    @objc private func deselectTapped() {
        selectedAnnotationIndex = nil
        annotationRotateMode = false
        arrowMode = false
        textMode = false
        rebuildMenu()
        updateHandles()
        updateSelectionOutline()
        layoutMenuNearFrame()
    }

    // MARK: - Text menu

    @objc private func textSizeTapped() {
        guard let index = selectedAnnotationIndex, case .text(var text) = annotations[index] else { return }
        let sheet = UIAlertController(title: "Text Size", message: nil, preferredStyle: .actionSheet)
        for size in [14, 18, 24, 32, 42] as [CGFloat] {
            sheet.addAction(UIAlertAction(title: "\(Int(size)) pt", style: .default) { [weak self] _ in
                text.fontSize = size
                self?.annotations[index] = .text(text)
                self?.redrawAnnotations()
                self?.updateSelectionOutline()
                self?.updateHandles()
                self?.layoutMenuNearFrame()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func textColorTapped() {
        guard let index = selectedAnnotationIndex, case .text(var text) = annotations[index] else { return }
        let sheet = UIAlertController(title: "Text Color", message: nil, preferredStyle: .actionSheet)
        let names = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "White", "Black"]
        for (i, name) in names.enumerated() {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                text.color = self?.annotationColors[i] ?? .systemRed
                self?.annotations[index] = .text(text)
                self?.redrawAnnotations()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func textFontTapped() {
        guard let index = selectedAnnotationIndex, case .text(var text) = annotations[index] else { return }
        let sheet = UIAlertController(title: "Font", message: nil, preferredStyle: .actionSheet)
        for font in ScreenshotTextFont.allCases {
            sheet.addAction(UIAlertAction(title: font.title, style: .default) { [weak self] _ in
                text.font = font
                self?.annotations[index] = .text(text)
                self?.redrawAnnotations()
                self?.updateSelectionOutline()
                self?.updateHandles()
                self?.layoutMenuNearFrame()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func textRotateTapped() {
        annotationRotateMode.toggle()
        rebuildMenu()
    }

    // MARK: - Arrow menu

    @objc private func arrowStyleTapped() {
        guard let index = selectedAnnotationIndex, case .arrow(var arrow) = annotations[index] else { return }
        let sheet = UIAlertController(title: "Arrow Style", message: nil, preferredStyle: .actionSheet)
        for style in ScreenshotArrowStyle.allCases {
            sheet.addAction(UIAlertAction(title: style.title, style: .default) { [weak self] _ in
                arrow.style = style
                self?.annotations[index] = .arrow(arrow)
                self?.redrawAnnotations()
                self?.updateSelectionOutline()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func arrowColorTapped() {
        guard let index = selectedAnnotationIndex, case .arrow(var arrow) = annotations[index] else { return }
        let sheet = UIAlertController(title: "Arrow Color", message: nil, preferredStyle: .actionSheet)
        let names = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "White", "Black"]
        for (i, name) in names.enumerated() {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                arrow.color = self?.annotationColors[i] ?? .systemRed
                self?.annotations[index] = .arrow(arrow)
                self?.redrawAnnotations()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func arrowWidthTapped() {
        guard let index = selectedAnnotationIndex, case .arrow(var arrow) = annotations[index] else { return }
        let sheet = UIAlertController(title: "Line Width", message: nil, preferredStyle: .actionSheet)
        for width in [2, 3, 5, 8, 12] as [CGFloat] {
            sheet.addAction(UIAlertAction(title: "\(Int(width)) pt", style: .default) { [weak self] _ in
                arrow.lineWidth = width
                self?.annotations[index] = .arrow(arrow)
                self?.redrawAnnotations()
                self?.updateSelectionOutline()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentSheet(sheet)
    }

    @objc private func arrowAngleTapped() {
        annotationRotateMode.toggle()
        rebuildMenu()
    }

    private func presentSheet(_ sheet: UIAlertController) {
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = menuBar
            pop.sourceRect = menuBar.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func saveAlbumTapped() {
        guard let image = exportImage() else {
            Toast.show("Export failed", from: self)
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(saveFinished(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func saveFinished(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if error != nil {
            Toast.show("Could not save to album", from: self)
        } else {
            Toast.show("Saved to album", from: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.dismiss(animated: true)
            }
        }
    }

    @objc private func saveClipboardTapped() {
        guard let image = exportImage() else {
            Toast.show("Export failed", from: self)
            return
        }
        UIPasteboard.general.image = image
        Toast.show("Copied to clipboard", from: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    // MARK: - Export

    private func exportImage() -> UIImage? {
        guard imageFrameInCanvas.width > 1, selectionSize.width > 1 else { return nil }

        let exportSize = selectionSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = sourceImage.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: exportSize, format: format)

        let scaleX = sourceImage.size.width / imageFrameInCanvas.width
        let scaleY = sourceImage.size.height / imageFrameInCanvas.height

        return renderer.image { ctx in
            let bounds = CGRect(origin: .zero, size: exportSize)
            shape.path(in: bounds).addClip()

            let c = ctx.cgContext
            c.translateBy(x: exportSize.width / 2, y: exportSize.height / 2)
            c.concatenate(CGAffineTransform(rotationAngle: -selectionRotation))
            c.translateBy(x: -selectionCenter.x, y: -selectionCenter.y)

            // Draw source image in canvas coordinates.
            if let cg = sourceImage.cgImage {
                let drawRect = imageFrameInCanvas
                c.saveGState()
                c.translateBy(x: drawRect.minX, y: drawRect.maxY)
                c.scaleBy(x: 1, y: -1)
                c.draw(cg, in: CGRect(x: 0, y: 0, width: drawRect.width, height: drawRect.height))
                c.restoreGState()
            }

            // Annotations in canvas space (same CTM).
            for item in annotations {
                switch item {
                case .arrow(let arrow):
                    let s = absolutePoint(arrow.start)
                    let e = absolutePoint(arrow.end)
                    let path = arrowPath(from: s, to: e, style: arrow.style, lineWidth: arrow.lineWidth)
                    c.setStrokeColor(arrow.color.cgColor)
                    c.setLineWidth(arrow.lineWidth)
                    c.setLineCap(.round)
                    c.setLineJoin(.round)
                    if arrow.style == .dashed {
                        c.setLineDash(phase: 0, lengths: [6, 4])
                    } else {
                        c.setLineDash(phase: 0, lengths: [])
                    }
                    c.addPath(path.cgPath)
                    c.strokePath()
                case .text(let text):
                    let p = absolutePoint(text.origin)
                    let font = text.font.font(size: text.fontSize)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: text.color
                    ]
                    let size = (text.value as NSString).size(withAttributes: attrs)
                    c.saveGState()
                    c.translateBy(x: p.x, y: p.y)
                    c.concatenate(CGAffineTransform(rotationAngle: selectionRotation + text.rotation))
                    // Flip for UIKit text drawing in CGContext that may be flipped — use UIKit draw in image renderer which is UIKit-flipped.
                    c.restoreGState()

                    // Use UIKit string drawing in current UIGraphics context:
                    let uiP = p
                    c.saveGState()
                    // UIGraphicsImageRenderer is UIKit-oriented (y down). Our CTM already maps canvas->export.
                    let drawPoint = CGPoint(x: uiP.x - size.width / 2, y: uiP.y - size.height / 2)
                    // For rotated text, translate to center then rotate.
                    c.translateBy(x: uiP.x, y: uiP.y)
                    c.concatenate(CGAffineTransform(rotationAngle: selectionRotation + text.rotation))
                    (text.value as NSString).draw(
                        at: CGPoint(x: -size.width / 2, y: -size.height / 2),
                        withAttributes: attrs
                    )
                    c.restoreGState()
                    _ = drawPoint
                    _ = scaleX
                    _ = scaleY
                }
            }
        }
    }
}
