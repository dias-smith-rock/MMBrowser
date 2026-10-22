import UIKit
import AVFoundation
import MediaPlayer
import SnapKit

/// Glassmorphism floating mini-player matching the product mock.
final class CustomPipFloatingView: UIView {
    var onClose: (() -> Void)?
    var onReturnToPage: (() -> Void)?
    var onTogglePlay: (() -> Void)?
    var onSeekBy: ((TimeInterval) -> Void)?
    var onSeekToFraction: ((Double) -> Void)?
    var onFullscreen: (() -> Void)?
    var onDockChanged: ((Bool) -> Void)?

    private let playerContainer = PlayerContainerView()
    var playerLayer: AVPlayerLayer { playerContainer.playerLayer }
    /// Frosted rim behind the video — separates the float from the page underneath.
    private let edgeFrost = EdgeFrostView()
    private let dimView = UIView()
    private let overlay = UIView()

    private let closeButton = GlassCircleButton(symbol: "xmark", pointSize: 12)
    private let returnButton = GlassCircleButton(symbol: "rectangle.on.rectangle", pointSize: 12)
    private let volumeTrack = GlassPillView()
    private let volumeFill = UIView()
    private let volumeIcon = UIImageView()
    private let hiddenVolumeView = MPVolumeView(frame: .zero)

    private let rewindButton = GlassCircleButton(symbol: "gobackward.10", pointSize: 16)
    private let playButton = GlassCircleButton(symbol: "pause.fill", pointSize: 20, diameter: 56)
    private let forwardButton = GlassCircleButton(symbol: "goforward.10", pointSize: 16)

    private let progressPill = GlassPillView()
    private let progressFill = UIView()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let fullscreenButton = GlassCircleButton(symbol: "arrow.up.left.and.arrow.down.right", pointSize: 12)

    private let edgeTab = UIButton(type: .system)

    private var panStart = CGPoint.zero
    private var dockPanStart = CGPoint.zero
    private var isScrubbing = false
    private var controlsVisible = true
    private var hideWorkItem: DispatchWorkItem?
    private lazy var dockTabPan = UIPanGestureRecognizer(target: self, action: #selector(dockTabPanned(_:)))
    private var volumeObservation: NSKeyValueObservation?
    private var isUpdatingVolumeUI = false
    private(set) var isDocked = false
    private var dockSide: DockSide = .trailing
    private var restoredFrame: CGRect = .zero
    /// width / height from the current video (updated by controller).
    var videoAspect: CGFloat = 16.0 / 9.0

    private enum DockSide { case leading, trailing }

    private let mediaClip = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Must stay unclipped so `edgeFrost` (UIVisualEffectView) can sample the page.
        backgroundColor = .clear
        isOpaque = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)

        mediaClip.backgroundColor = .black
        mediaClip.clipsToBounds = true
        mediaClip.layer.cornerRadius = 16
        mediaClip.isUserInteractionEnabled = false

        playerContainer.backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        dimView.isUserInteractionEnabled = false

        overlay.backgroundColor = .clear
        overlay.isOpaque = false

        configureChrome()
        layoutChrome()
        setupGestures()
        setupVolume()
        scheduleHideControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        volumeObservation?.invalidate()
        hideWorkItem?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isDocked {
            restoredFrame = frame
            layer.shadowPath = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: EdgeFrostView.outerRadius
            ).cgPath
        } else {
            layer.shadowPath = nil
            layer.shadowOpacity = 0
        }
        if !isDocked, layer.shadowOpacity < 0.01 {
            layer.shadowOpacity = 0.18
        }
    }

    func attach(player: AVPlayer) {
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
    }

    func setPlaying(_ playing: Bool) {
        playButton.setSymbol(playing ? "pause.fill" : "play.fill", pointSize: 20)
    }

    func updateProgress(current: Double, duration: Double) {
        guard !isScrubbing, duration > 0.5, duration.isFinite else { return }
        let fraction = min(max(current / duration, 0), 1)
        let trackWidth = max(progressPill.bounds.width - 88, 1)
        progressFill.snp.updateConstraints { make in
            make.width.equalTo(trackWidth * fraction)
        }
        elapsedLabel.text = Self.formatTime(current)
        remainingLabel.text = "-\(Self.formatTime(max(duration - current, 0)))"
    }

    func undockIfNeeded() {
        guard isDocked else { return }
        expandFromDock(animated: true)
    }

    // MARK: - Setup

    private func configureChrome() {
        closeButton.accessibilityLabel = "Close"
        returnButton.accessibilityLabel = "Return to page"
        rewindButton.accessibilityLabel = "Back 10 seconds"
        forwardButton.accessibilityLabel = "Forward 10 seconds"
        playButton.accessibilityLabel = "Play or pause"
        fullscreenButton.accessibilityLabel = "Full screen"

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(rewindTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)

        volumeFill.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        volumeFill.layer.cornerRadius = 3
        volumeIcon.image = UIImage(
            systemName: "speaker.wave.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        volumeIcon.tintColor = .white
        volumeIcon.contentMode = .scaleAspectFit

        progressFill.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        progressFill.layer.cornerRadius = 2

        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        elapsedLabel.textColor = .white
        remainingLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        remainingLabel.textColor = .white
        elapsedLabel.text = "0:00"
        remainingLabel.text = "-0:00"

        hiddenVolumeView.isHidden = true
        hiddenVolumeView.alpha = 0.01
        hiddenVolumeView.showsRouteButton = false

        edgeTab.isHidden = true
        edgeTab.backgroundColor = DockTabStyle.fill
        edgeTab.layer.cornerRadius = DockTabStyle.cornerRadius
        edgeTab.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        edgeTab.tintColor = UIColor(white: 0.78, alpha: 1)
        edgeTab.accessibilityLabel = "Restore player"
        edgeTab.addTarget(self, action: #selector(edgeTabTapped), for: .touchUpInside)
        // Pan lives on the tab itself — the button otherwise eats touches and blocks drag.
        dockTabPan.cancelsTouchesInView = true
        edgeTab.addGestureRecognizer(dockTabPan)
        applyDockTabIcon(side: .trailing)
    }

    private func layoutChrome() {
        // Frost sits behind the video; a small inset lets the blurred rim show.
        addSubview(edgeFrost)
        addSubview(mediaClip)
        mediaClip.addSubview(playerContainer)
        mediaClip.addSubview(dimView)
        addSubview(overlay)
        addSubview(hiddenVolumeView)
        addSubview(edgeTab)

        overlay.addSubview(closeButton)
        overlay.addSubview(volumeTrack)
        volumeTrack.addSubview(volumeFill)
        volumeTrack.addSubview(volumeIcon)
        overlay.addSubview(returnButton)

        overlay.addSubview(rewindButton)
        overlay.addSubview(playButton)
        overlay.addSubview(forwardButton)

        overlay.addSubview(progressPill)
        progressPill.addSubview(elapsedLabel)
        progressPill.addSubview(progressFill)
        progressPill.addSubview(remainingLabel)
        overlay.addSubview(fullscreenButton)

        edgeFrost.snp.makeConstraints { $0.edges.equalToSuperview() }
        mediaClip.snp.makeConstraints { $0.edges.equalToSuperview().inset(EdgeFrostView.rimWidth) }
        playerContainer.snp.makeConstraints { $0.edges.equalToSuperview() }
        dimView.snp.makeConstraints { $0.edges.equalToSuperview() }
        overlay.snp.makeConstraints { $0.edges.equalTo(mediaClip) }
        hiddenVolumeView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(-1000)
            make.size.equalTo(CGSize(width: 1, height: 1))
        }

        closeButton.snp.makeConstraints { make in
            make.leading.top.equalToSuperview().inset(10)
        }
        returnButton.snp.makeConstraints { make in
            make.trailing.top.equalToSuperview().inset(10)
        }
        volumeTrack.snp.makeConstraints { make in
            make.centerY.equalTo(closeButton)
            make.centerX.equalToSuperview()
            make.height.equalTo(22)
            make.width.equalTo(72)
        }
        volumeIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(12)
        }
        volumeFill.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.height.equalTo(4)
            make.width.equalTo(40)
        }

        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        rewindButton.snp.makeConstraints { make in
            make.centerY.equalTo(playButton)
            make.trailing.equalTo(playButton.snp.leading).offset(-18)
        }
        forwardButton.snp.makeConstraints { make in
            make.centerY.equalTo(playButton)
            make.leading.equalTo(playButton.snp.trailing).offset(18)
        }

        fullscreenButton.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview().inset(10)
        }
        progressPill.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(10)
            make.trailing.equalTo(fullscreenButton.snp.leading).offset(-8)
            make.centerY.equalTo(fullscreenButton)
            make.height.equalTo(22)
        }
        elapsedLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }
        remainingLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(10)
            make.centerY.equalToSuperview()
        }
        progressFill.snp.makeConstraints { make in
            make.leading.equalTo(elapsedLabel.snp.trailing).offset(8)
            make.centerY.equalToSuperview()
            make.height.equalTo(3)
            make.width.equalTo(20)
        }

        edgeTab.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func applyDockTabIcon(side: DockSide) {
        let name = side == .leading ? "chevron.right" : "chevron.left"
        edgeTab.setImage(
            UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)),
            for: .normal
        )
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(contentTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        let volumePan = UIPanGestureRecognizer(target: self, action: #selector(volumePanned(_:)))
        volumeTrack.addGestureRecognizer(volumePan)
        volumeTrack.isUserInteractionEnabled = true

        let progressPan = UIPanGestureRecognizer(target: self, action: #selector(progressPanned(_:)))
        progressPill.addGestureRecognizer(progressPan)
        let progressTap = UITapGestureRecognizer(target: self, action: #selector(progressTapped(_:)))
        progressPill.addGestureRecognizer(progressTap)
        progressPill.isUserInteractionEnabled = true
    }

    private func setupVolume() {
        let session = AVAudioSession.sharedInstance()
        applyVolumeUI(session.outputVolume)
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            DispatchQueue.main.async {
                self?.applyVolumeUI(value)
            }
        }
    }

    // MARK: - Controls visibility

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        controlsVisible = visible
        let apply = {
            self.overlay.isHidden = !visible
            self.dimView.isHidden = !visible
            self.overlay.alpha = visible ? 1 : 0
            self.dimView.alpha = visible ? 1 : 0
        }
        if animated {
            if visible {
                overlay.isHidden = false
                dimView.isHidden = false
                overlay.alpha = 0
                dimView.alpha = 0
            }
            UIView.animate(withDuration: 0.2, animations: {
                self.overlay.alpha = visible ? 1 : 0
                self.dimView.alpha = visible ? 1 : 0
            }, completion: { _ in
                if !visible {
                    self.overlay.isHidden = true
                    self.dimView.isHidden = true
                }
            })
        } else {
            apply()
        }
        if visible { scheduleHideControls() }
    }

    private func scheduleHideControls() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.setControlsVisible(false, animated: true)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func bumpControls() {
        // Keep overlay up while interacting — never toggle off mid-tap.
        hideWorkItem?.cancel()
        if controlsVisible {
            overlay.isHidden = false
            overlay.alpha = 1
            dimView.isHidden = false
            dimView.alpha = 1
            scheduleHideControls()
        } else {
            setControlsVisible(true, animated: true)
        }
    }

    // MARK: - Actions

    @objc private func contentTapped() {
        guard !isDocked else {
            expandFromDock(animated: true)
            return
        }
        setControlsVisible(!controlsVisible, animated: true)
    }

    @objc private func closeTapped() {
        bumpControls()
        onClose?()
    }

    @objc private func returnTapped() {
        bumpControls()
        onReturnToPage?()
    }

    @objc private func playTapped() {
        bumpControls()
        onTogglePlay?()
    }

    @objc private func rewindTapped() {
        bumpControls()
        onSeekBy?(-10)
    }

    @objc private func forwardTapped() {
        bumpControls()
        onSeekBy?(10)
    }

    @objc private func fullscreenTapped() {
        bumpControls()
        onFullscreen?()
    }

    @objc private func edgeTabTapped() {
        expandFromDock(animated: true)
    }

    // MARK: - Drag / dock

    @objc private func dockTabPanned(_ gesture: UIPanGestureRecognizer) {
        guard isDocked, let superview else { return }
        let translation = gesture.translation(in: superview)
        let velocity = gesture.velocity(in: superview)
        let halfH = DockTabStyle.height / 2
        let top = halfH + superview.safeAreaInsets.top + 4
        let bottom = superview.bounds.height - halfH - superview.safeAreaInsets.bottom - 4

        switch gesture.state {
        case .began:
            dockPanStart = center
        case .changed:
            let y = min(max(dockPanStart.y + translation.y, top), bottom)
            // Follow finger horizontally while dragging so user can pull inward or cross sides.
            var x = dockPanStart.x + translation.x
            x = min(max(x, DockTabStyle.width / 2), superview.bounds.width - DockTabStyle.width / 2)
            center = CGPoint(x: x, y: y)
        case .ended, .cancelled:
            let y = min(max(center.y, top), bottom)

            // Strong inward fling restores the player.
            let inward = (dockSide == .leading && (velocity.x > 650 || translation.x > 56))
                || (dockSide == .trailing && (velocity.x < -650 || translation.x < -56))
            if inward {
                expandFromDock(animated: true)
                return
            }

            // Snap to nearer screen edge (allows dragging to the opposite side).
            let preferLeading = center.x < superview.bounds.midX
            let newSide: DockSide = preferLeading ? .leading : .trailing
            if newSide != dockSide {
                dockSide = newSide
                applyDockTabIcon(side: newSide)
                switch newSide {
                case .leading:
                    edgeTab.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
                case .trailing:
                    edgeTab.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
                }
            }
            let snapX = newSide == .leading
                ? DockTabStyle.width / 2
                : superview.bounds.width - DockTabStyle.width / 2
            UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
                self.center = CGPoint(x: snapX, y: y)
            }
        default:
            break
        }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let superview, !isDocked else { return }
        let translation = gesture.translation(in: superview)
        let velocity = gesture.velocity(in: superview)

        // Don't drag when interacting with progress.
        let loc = gesture.location(in: self)
        if progressPill.frame.insetBy(dx: -4, dy: -6).contains(loc), gesture.state == .began {
            return
        }

        switch gesture.state {
        case .began:
            panStart = center
            bumpControls()
        case .changed:
            var next = CGPoint(x: panStart.x + translation.x, y: panStart.y + translation.y)
            let halfH = bounds.height / 2
            let top = halfH + superview.safeAreaInsets.top + 4
            let bottom = superview.bounds.height - halfH - superview.safeAreaInsets.bottom - 4
            next.y = min(max(next.y, top), bottom)
            // Allow X past edges so user can fling to dock.
            center = next
        case .ended, .cancelled:
            maybeDock(velocityX: velocity.x, in: superview)
        default:
            break
        }
    }

    private func maybeDock(velocityX: CGFloat, in superview: UIView) {
        let midX = superview.bounds.midX
        let leadingThreshold = bounds.width * 0.35
        let trailingThreshold = superview.bounds.width - bounds.width * 0.35
        let flingLeading = velocityX < -800
        let flingTrailing = velocityX > 800
        let nearLeading = frame.maxX < leadingThreshold || center.x < midX * 0.45
        let nearTrailing = frame.minX > trailingThreshold || center.x > superview.bounds.width * 0.78

        if flingLeading || (nearLeading && velocityX <= 0) {
            collapseToDock(side: .leading, in: superview)
            return
        }
        if flingTrailing || (nearTrailing && velocityX >= 0) {
            collapseToDock(side: .trailing, in: superview)
            return
        }

        // Snap inside safe bounds.
        var frame = self.frame
        let inset: CGFloat = 8
        frame.origin.x = min(max(frame.origin.x, inset), superview.bounds.width - frame.width - inset)
        frame.origin.y = min(
            max(frame.origin.y, superview.safeAreaInsets.top + inset),
            superview.bounds.height - frame.height - superview.safeAreaInsets.bottom - inset
        )
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            self.frame = frame
        }
        restoredFrame = frame
    }

    private func collapseToDock(side: DockSide, in superview: UIView) {
        restoredFrame = frame
        dockSide = side
        isDocked = true
        setControlsVisible(false, animated: false)

        // Fixed dock handle — never inherits player width/height.
        let tab = CGSize(width: DockTabStyle.width, height: DockTabStyle.height)
        var docked = CGRect(origin: .zero, size: tab)
        let midY = frame.midY
        docked.origin.y = min(
            max(midY - tab.height / 2, superview.safeAreaInsets.top + 8),
            superview.bounds.height - tab.height - superview.safeAreaInsets.bottom - 8
        )
        switch side {
        case .leading:
            docked.origin.x = 0
            edgeTab.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        case .trailing:
            docked.origin.x = superview.bounds.width - tab.width
            edgeTab.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
        applyDockTabIcon(side: side)
        edgeTab.backgroundColor = DockTabStyle.fill
        edgeTab.layer.cornerRadius = DockTabStyle.cornerRadius
        edgeTab.snp.remakeConstraints { $0.edges.equalToSuperview() }
        edgeTab.isHidden = false
        mediaClip.isHidden = true
        edgeFrost.isHidden = true
        overlay.isHidden = true
        dimView.isHidden = true
        dimView.alpha = 0
        layer.shadowOpacity = 0

        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseInOut) {
            self.frame = docked
        } completion: { _ in
            self.onDockChanged?(true)
        }
    }

    private func expandFromDock(animated: Bool) {
        guard isDocked, let superview else { return }
        isDocked = false
        edgeTab.isHidden = true
        mediaClip.isHidden = false
        edgeFrost.isHidden = false
        layer.shadowOpacity = 0.18
        var target = restoredFrame
        if target.width < 10 || target.height < 10 {
            target = CustomPipController.preferredFloatingFrame(aspect: videoAspect, in: superview)
        }
        // Keep vertical position near the dock tab when restoring.
        let preferY = frame.midY - target.height / 2
        let inset: CGFloat = 8
        target.origin.x = min(max(target.origin.x, inset), superview.bounds.width - target.width - inset)
        target.origin.y = min(
            max(preferY, superview.safeAreaInsets.top + inset),
            superview.bounds.height - target.height - superview.safeAreaInsets.bottom - inset
        )
        dimView.isHidden = false
        overlay.isHidden = false
        overlay.alpha = 1
        let apply = {
            self.frame = target
            self.dimView.alpha = 1
        }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseInOut, animations: apply) { _ in
                self.controlsVisible = true
                self.scheduleHideControls()
                self.onDockChanged?(false)
            }
        } else {
            apply()
            controlsVisible = true
            scheduleHideControls()
            onDockChanged?(false)
        }
    }

    // MARK: - Volume / progress gestures

    @objc private func volumePanned(_ gesture: UIPanGestureRecognizer) {
        bumpControls()
        let x = gesture.location(in: volumeTrack).x
        let usable = max(volumeTrack.bounds.width - 36, 1)
        let fraction = min(max((x - 8) / usable, 0), 1)
        setSystemVolume(Float(fraction))
        applyVolumeUI(Float(fraction))
    }

    @objc private func progressPanned(_ gesture: UIPanGestureRecognizer) {
        bumpControls()
        let fraction = progressFraction(at: gesture.location(in: progressPill))
        switch gesture.state {
        case .began:
            isScrubbing = true
        case .changed:
            applyProgressFill(fraction)
        case .ended, .cancelled:
            isScrubbing = false
            onSeekToFraction?(fraction)
        default:
            break
        }
    }

    @objc private func progressTapped(_ gesture: UITapGestureRecognizer) {
        bumpControls()
        let fraction = progressFraction(at: gesture.location(in: progressPill))
        applyProgressFill(fraction)
        onSeekToFraction?(fraction)
    }

    private func progressFraction(at point: CGPoint) -> Double {
        let leading = elapsedLabel.frame.maxX + 8
        let trailing = remainingLabel.frame.minX - 8
        let width = max(trailing - leading, 1)
        return min(max(Double((point.x - leading) / width), 0), 1)
    }

    private func applyProgressFill(_ fraction: Double) {
        let trackWidth = max(progressPill.bounds.width - 88, 1)
        progressFill.snp.updateConstraints { make in
            make.width.equalTo(trackWidth * fraction)
        }
        layoutIfNeeded()
    }

    private func applyVolumeUI(_ value: Float) {
        guard !isUpdatingVolumeUI else { return }
        let usable = max(volumeTrack.bounds.width - 36, 1)
        let width = max(CGFloat(value) * usable, 4)
        volumeFill.snp.updateConstraints { make in
            make.width.equalTo(width)
        }
        let symbol: String
        if value < 0.01 { symbol = "speaker.slash.fill" }
        else if value < 0.4 { symbol = "speaker.wave.1.fill" }
        else { symbol = "speaker.wave.2.fill" }
        volumeIcon.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        volumeIcon.tintColor = .white
    }

    private func setSystemVolume(_ value: Float) {
        isUpdatingVolumeUI = true
        defer { isUpdatingVolumeUI = false }
        // Drive the private slider inside MPVolumeView.
        for view in hiddenVolumeView.subviews {
            if let slider = view as? UISlider {
                slider.value = value
                return
            }
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds.rounded(.down)), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

extension CustomPipFloatingView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Don't toggle chrome when tapping buttons / sliders.
        if gestureRecognizer is UITapGestureRecognizer {
            var view: UIView? = touch.view
            while let current = view {
                if current is UIControl { return false }
                if current === volumeTrack || current === progressPill { return false }
                if current === overlay && touch.view !== overlay && touch.view !== dimView {
                    // Touches on chrome subviews of overlay are handled above.
                }
                view = current.superview
                if current === self { break }
            }
        }

        guard gestureRecognizer is UIPanGestureRecognizer else { return true }
        let point = touch.location(in: self)
        // Progress scrubber owns its own pan — exclude from window drag.
        if progressPill.frame.insetBy(dx: -6, dy: -8).contains(point) { return false }
        if volumeTrack.frame.insetBy(dx: -4, dy: -4).contains(point) { return false }
        if touch.view is UIControl { return false }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

// MARK: - Dock tab (fixed size)

private enum DockTabStyle {
    static let width: CGFloat = 22
    static let height: CGFloat = 56
    static let cornerRadius: CGFloat = 11
    static let fill = UIColor(white: 0.22, alpha: 1)
}

// MARK: - Edge frost rim

/// Rounded frosted plate behind the video. Video is inset so a thin blurred rim
/// samples the webpage and separates the float from page content.
private final class EdgeFrostView: UIView {
    static let rimWidth: CGFloat = 1.5
    static let outerRadius: CGFloat = 18

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        // Round only the effect view — never mask this wrapper (breaks blur).
        blurView.layer.cornerRadius = Self.outerRadius
        blurView.clipsToBounds = true
        blurView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        addSubview(blurView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Player layer host

/// Backing layer is `AVPlayerLayer` so video always matches view bounds
/// (manual `frame = bounds` breaks after `AVPictureInPictureController` attaches).
private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Chrome helpers

private enum PipChromeStyle {
    static let fill = UIColor.white.withAlphaComponent(0.35)
}

/// Translucent pill track (no blur).
private final class GlassPillView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = PipChromeStyle.fill
        clipsToBounds = true
        layer.cornerRadius = 11
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Circular translucent control (no blur).
private final class GlassCircleButton: UIControl {
    private let iconView = UIImageView()
    private var pointSize: CGFloat

    init(symbol: String, pointSize: CGFloat, diameter: CGFloat = 32) {
        self.pointSize = pointSize
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = PipChromeStyle.fill
        clipsToBounds = true
        layer.cornerRadius = diameter / 2

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        iconView.isUserInteractionEnabled = false

        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(diameter * 0.46)
        }
        snp.makeConstraints { $0.size.equalTo(diameter) }
        setSymbol(symbol, pointSize: pointSize)

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String, pointSize: CGFloat = 16) {
        self.pointSize = pointSize
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        iconView.image = UIImage(systemName: name, withConfiguration: config)?
            .withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .white
    }

    @objc private func touchDown() {
        iconView.alpha = 0.65
    }

    @objc private func touchUp() {
        iconView.alpha = 1
    }
}
