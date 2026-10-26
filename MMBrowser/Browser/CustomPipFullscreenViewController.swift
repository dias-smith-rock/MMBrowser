import UIKit
import AVFoundation
import MediaPlayer
import SnapKit

/// In-app fullscreen player sharing the same `AVPlayer` as the floating window.
final class CustomPipFullscreenViewController: UIViewController {
    var onDismiss: (() -> Void)?
    var onTogglePlay: (() -> Void)?
    var onSeekBy: ((TimeInterval) -> Void)?
    var onSeekToFraction: ((Double) -> Void)?
    var onPlaybackRate: ((Float) -> Void)?
    /// `nil` turns the sleep timer off; otherwise duration in seconds.
    var onSleepTimer: ((TimeInterval?) -> Void)?
    var onCloseSession: (() -> Void)?

    private let player: AVPlayer
    /// Landscape source video → lock UI to landscape while fullscreen.
    private let prefersLandscape: Bool
    private var playbackRate: Float
    private var isExiting = false
    private let playerLayer = AVPlayerLayer()
    private let overlay = UIView()
    private let closeButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let lockButton = UIButton(type: .system)
    private let sleepButton = UIButton(type: .system)
    private var sleepTimerEndsAt: Date?
    private let progress = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let gestureHint = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let gestureIcon = UIImageView()
    private let gestureLabel = UILabel()
    private let hiddenVolumeView = MPVolumeView(frame: .zero)
    private var hideWorkItem: DispatchWorkItem?
    private var hintWorkItem: DispatchWorkItem?
    private var timeObserver: Any?
    private var isScrubbing = false
    private var isControlsLocked = false
    private var verticalGestureMode: VerticalGestureMode?
    private var gestureStartValue: CGFloat = 0

    private enum VerticalGestureMode { case brightness, volume }

    private static let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    init(player: AVPlayer, prefersLandscape: Bool, playbackRate: Float = 1.0) {
        self.player = player
        self.prefersLandscape = prefersLandscape
        self.playbackRate = playbackRate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var shouldAutorotate: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Mac windows are freely resized — do not force a phone-style lock.
        if PlatformSupport.isMacInterface { return .all }
        if isExiting { return .portrait }
        return prefersLandscape ? .landscape : .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if PlatformSupport.isMacInterface { return .portrait }
        return prefersLandscape ? .landscapeRight : .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerLayer.player = player
        // Fill the screen — crop edges instead of letterboxing.
        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)

        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        view.addSubview(overlay)

        configureChrome()
        layoutChrome()
        setupGestures()
        scheduleHide()
        addTimeObserver()
        refreshPlayIcon()
        applySpeedTitle()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if prefersLandscape {
            requestOrientation(.landscape)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        playerLayer.player = nil
        onDismiss?()
    }

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        guard !PlatformSupport.isMacInterface else { return }
        guard let scene = view.window?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    private func exitFullscreen() {
        isExiting = true
        if prefersLandscape, !PlatformSupport.isMacInterface {
            requestOrientation(.portrait)
        } else {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        dismiss(animated: true)
    }

    // MARK: - Chrome

    private func configureChrome() {
        func style(_ button: UIButton, symbol: String?, size: CGFloat, diameter: CGFloat) {
            button.tintColor = .white
            if let symbol {
                button.setImage(
                    UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .bold)),
                    for: .normal
                )
            }
            button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            button.layer.cornerRadius = diameter / 2
        }
        style(closeButton, symbol: "xmark", size: 14, diameter: 36)
        style(rewindButton, symbol: "gobackward.10", size: 18, diameter: 44)
        style(playButton, symbol: "pause.fill", size: 22, diameter: 64)
        style(forwardButton, symbol: "goforward.10", size: 18, diameter: 44)
        style(speedButton, symbol: nil, size: 12, diameter: 36)
        style(lockButton, symbol: "lock.open.fill", size: 16, diameter: 40)
        lockButton.accessibilityLabel = "Lock controls"
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        style(sleepButton, symbol: "moon.zzz", size: 16, diameter: 40)
        sleepButton.accessibilityLabel = "Sleep timer"
        sleepButton.showsMenuAsPrimaryAction = true
        sleepButton.menu = makeSleepTimerMenu()
        speedButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        speedButton.setTitleColor(.white, for: .normal)
        speedButton.showsMenuAsPrimaryAction = true
        speedButton.menu = makeSpeedMenu()
        speedButton.accessibilityLabel = "Playback speed"

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(rewindTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)

        progress.minimumTrackTintColor = .white
        progress.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        progress.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        progress.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        progress.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)

        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        remainingLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        elapsedLabel.textColor = .white
        remainingLabel.textColor = .white

        gestureHint.layer.cornerRadius = 14
        gestureHint.clipsToBounds = true
        gestureHint.alpha = 0
        gestureHint.isUserInteractionEnabled = false
        gestureIcon.tintColor = .white
        gestureIcon.contentMode = .scaleAspectFit
        gestureLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        gestureLabel.textColor = .white
        gestureLabel.textAlignment = .center

        hiddenVolumeView.isHidden = true
        hiddenVolumeView.alpha = 0.01
        hiddenVolumeView.showsRouteButton = false
    }

    private func layoutChrome() {
        overlay.addSubview(closeButton)
        overlay.addSubview(speedButton)
        overlay.addSubview(rewindButton)
        overlay.addSubview(playButton)
        overlay.addSubview(forwardButton)
        view.addSubview(lockButton)
        overlay.addSubview(sleepButton)
        overlay.addSubview(progress)
        overlay.addSubview(elapsedLabel)
        overlay.addSubview(remainingLabel)
        view.addSubview(gestureHint)
        gestureHint.contentView.addSubview(gestureIcon)
        gestureHint.contentView.addSubview(gestureLabel)
        view.addSubview(hiddenVolumeView)

        overlay.snp.makeConstraints { $0.edges.equalToSuperview() }
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.size.equalTo(36)
        }
        speedButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.size.equalTo(36)
        }
        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(64)
        }
        rewindButton.snp.makeConstraints { make in
            make.centerY.equalTo(playButton)
            make.trailing.equalTo(playButton.snp.leading).offset(-28)
            make.size.equalTo(44)
        }
        forwardButton.snp.makeConstraints { make in
            make.centerY.equalTo(playButton)
            make.leading.equalTo(playButton.snp.trailing).offset(28)
            make.size.equalTo(44)
        }
        lockButton.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }
        sleepButton.snp.makeConstraints { make in
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }
        progress.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(56)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(56)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(28)
        }
        elapsedLabel.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.centerY.equalTo(progress)
        }
        remainingLabel.snp.makeConstraints { make in
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.centerY.equalTo(progress)
        }
        gestureHint.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.greaterThanOrEqualTo(120)
            make.height.equalTo(56)
        }
        gestureIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        gestureLabel.snp.makeConstraints { make in
            make.leading.equalTo(gestureIcon.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
        hiddenVolumeView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(-1000)
            make.size.equalTo(CGSize(width: 1, height: 1))
        }
    }

    private func setupGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleOverlay))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(verticalPanned(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    // MARK: - Sleep Timer

    private func makeSleepTimerMenu() -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.makeSleepTimerActions() ?? [])
            }
        ])
    }

    private func makeSleepTimerActions() -> [UIMenuElement] {
        var items: [UIMenuElement] = []
        if let remaining = PipSleepTimer.remaining(until: sleepTimerEndsAt) {
            items.append(UIAction(
                title: "Turn Off · \(PipSleepTimer.remainingLabel(for: remaining))",
                attributes: .destructive
            ) { [weak self] _ in
                self?.onSleepTimer?(nil)
                self?.scheduleHide()
            })
        }
        for preset in PipSleepTimer.presets {
            items.append(UIAction(title: preset.title) { [weak self] _ in
                self?.onSleepTimer?(TimeInterval(preset.minutes * 60))
                self?.scheduleHide()
            })
        }
        items.append(UIAction(title: "Custom…") { [weak self] _ in
            DispatchQueue.main.async { self?.presentCustomSleepTimer() }
        })
        return items
    }

    private func presentCustomSleepTimer() {
        let alert = UIAlertController(
            title: "Custom Sleep Timer",
            message: "Enter minutes until playback pauses.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.placeholder = "Minutes"
            field.textAlignment = .center
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.scheduleHide()
        })
        alert.addAction(UIAlertAction(title: "Start", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let minutes = Int(raw), minutes > 0 {
                let clamped = min(minutes, PipSleepTimer.maxCustomMinutes)
                self.onSleepTimer?(TimeInterval(clamped * 60))
            }
            self.scheduleHide()
        })
        present(alert, animated: true)
    }

    // MARK: - Speed

    private func makeSpeedMenu() -> UIMenu {
        let actions = Self.rates.map { rate -> UIAction in
            UIAction(
                title: Self.speedLabel(for: rate),
                state: abs(rate - playbackRate) < 0.01 ? .on : .off
            ) { [weak self] _ in
                self?.selectRate(rate)
            }
        }
        return UIMenu(title: "Playback Speed", options: .singleSelection, children: actions)
    }

    private func selectRate(_ rate: Float) {
        playbackRate = rate
        applySpeedTitle()
        speedButton.menu = makeSpeedMenu()
        onPlaybackRate?(rate)
        scheduleHide()
    }

    private func applySpeedTitle() {
        speedButton.setTitle(Self.speedLabel(for: playbackRate), for: .normal)
    }

    private static func speedLabel(for rate: Float) -> String {
        let tenths = Double(rate) * 10
        if abs(tenths - tenths.rounded()) < 0.01 {
            return String(format: "%.1fx", rate)
        }
        return String(format: "%.2fx", rate)
    }

    // MARK: - Playback UI

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let current = time.seconds
            let duration = self.player.currentItem?.duration.seconds ?? 0
            guard duration.isFinite, duration > 0 else { return }
            self.progress.value = Float(current / duration)
            self.elapsedLabel.text = Self.format(current)
            self.remainingLabel.text = "-\(Self.format(max(duration - current, 0)))"
            self.refreshPlayIcon()
        }
    }

    private func refreshPlayIcon() {
        let playing = player.rate > 0.01
        playButton.setImage(
            UIImage(
                systemName: playing ? "pause.fill" : "play.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
            ),
            for: .normal
        )
    }

    private func scheduleHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.2) {
                if self.isControlsLocked {
                    self.lockButton.alpha = 0
                } else {
                    self.overlay.alpha = 0
                    self.lockButton.alpha = 0
                }
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private var chromeControls: [UIView] {
        [closeButton, speedButton, sleepButton, rewindButton, playButton, forwardButton, progress, elapsedLabel, remainingLabel]
    }

    func setSleepTimerEndDate(_ endsAt: Date?) {
        sleepTimerEndsAt = endsAt
        let remaining = PipSleepTimer.remaining(until: endsAt)
        let symbol = remaining == nil ? "moon.zzz" : "moon.zzz.fill"
        sleepButton.setImage(
            UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            ),
            for: .normal
        )
        sleepButton.accessibilityLabel = remaining.map {
            "Sleep timer, \(PipSleepTimer.remainingLabel(for: $0))"
        } ?? "Sleep timer"
    }

    private func applyLockChrome(animated: Bool) {
        let symbol = isControlsLocked ? "lock.fill" : "lock.open.fill"
        lockButton.setImage(
            UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            ),
            for: .normal
        )
        lockButton.accessibilityLabel = isControlsLocked ? "Unlock controls" : "Lock controls"
        let updates = {
            self.overlay.alpha = self.isControlsLocked ? 0 : 1
            self.overlay.isUserInteractionEnabled = !self.isControlsLocked
            self.lockButton.alpha = 1
            for control in self.chromeControls {
                control.alpha = self.isControlsLocked ? 0 : 1
                control.isUserInteractionEnabled = !self.isControlsLocked
            }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: updates)
        } else {
            updates()
        }
    }

    // MARK: - Brightness / volume

    @objc private func verticalPanned(_ gesture: UIPanGestureRecognizer) {
        guard !isControlsLocked else { return }
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            let third = view.bounds.width / 3
            if location.x < third, PlatformSupport.supportsScreenBrightnessGestures {
                verticalGestureMode = .brightness
                gestureStartValue = UIScreen.main.brightness
            } else if location.x > view.bounds.width - third {
                verticalGestureMode = .volume
                gestureStartValue = CGFloat(currentSystemVolume())
            } else {
                verticalGestureMode = nil
            }
        case .changed:
            guard let mode = verticalGestureMode else { return }
            // Up = increase. ~full height drag ≈ full range.
            let delta = -translation.y / max(view.bounds.height * 0.55, 1)
            let next = min(max(gestureStartValue + delta, 0), 1)
            switch mode {
            case .brightness:
                guard PlatformSupport.supportsScreenBrightnessGestures else { return }
                UIScreen.main.brightness = next
                showGestureHint(symbol: brightnessSymbol(for: next), text: "\(Int((next * 100).rounded()))%")
            case .volume:
                setSystemVolume(Float(next))
                showGestureHint(symbol: volumeSymbol(for: next), text: "\(Int((next * 100).rounded()))%")
            }
        case .ended, .cancelled:
            verticalGestureMode = nil
            hideGestureHintSoon()
        default:
            break
        }
    }

    private func currentSystemVolume() -> Float {
        for view in hiddenVolumeView.subviews {
            if let slider = view as? UISlider { return slider.value }
        }
        return AVAudioSession.sharedInstance().outputVolume
    }

    private func setSystemVolume(_ value: Float) {
        for view in hiddenVolumeView.subviews {
            if let slider = view as? UISlider {
                slider.value = value
                return
            }
        }
    }

    private func brightnessSymbol(for value: CGFloat) -> String {
        value < 0.15 ? "sun.min.fill" : "sun.max.fill"
    }

    private func volumeSymbol(for value: CGFloat) -> String {
        if value < 0.01 { return "speaker.slash.fill" }
        if value < 0.4 { return "speaker.wave.1.fill" }
        if value < 0.7 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func showGestureHint(symbol: String, text: String) {
        gestureIcon.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        gestureLabel.text = text
        hintWorkItem?.cancel()
        UIView.animate(withDuration: 0.12) { self.gestureHint.alpha = 1 }
    }

    private func hideGestureHintSoon() {
        hintWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.2) { self?.gestureHint.alpha = 0 }
        }
        hintWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Actions

    @objc private func toggleOverlay() {
        if isControlsLocked {
            if lockButton.alpha < 0.5 {
                UIView.animate(withDuration: 0.2) { self.lockButton.alpha = 1 }
                scheduleHide()
            } else {
                UIView.animate(withDuration: 0.2) { self.lockButton.alpha = 0 }
            }
            return
        }
        if overlay.alpha < 0.5 {
            UIView.animate(withDuration: 0.2) {
                self.overlay.alpha = 1
                self.lockButton.alpha = 1
            }
            scheduleHide()
        } else {
            UIView.animate(withDuration: 0.2) {
                self.overlay.alpha = 0
                self.lockButton.alpha = 0
            }
        }
    }

    @objc private func lockTapped() {
        isControlsLocked.toggle()
        applyLockChrome(animated: true)
        let host: String? = {
            if let asset = player.currentItem?.asset as? AVURLAsset {
                return AppAnalytics.privacyHost(asset.url)
            }
            return nil
        }()
        AppAnalytics.logFullscreenLock(locked: isControlsLocked, host: host)
        scheduleHide()
    }

    @objc private func closeTapped() {
        exitFullscreen()
    }

    @objc private func playTapped() {
        onTogglePlay?()
        refreshPlayIcon()
        scheduleHide()
    }

    @objc private func rewindTapped() {
        onSeekBy?(-10)
        scheduleHide()
    }

    @objc private func forwardTapped() {
        onSeekBy?(10)
        scheduleHide()
    }

    @objc private func scrubBegan() { isScrubbing = true }
    @objc private func scrubChanged() {}
    @objc private func scrubEnded() {
        isScrubbing = false
        onSeekToFraction?(Double(progress.value))
        scheduleHide()
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension CustomPipFullscreenViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if isControlsLocked { return false }
        if touch.view is UIControl { return false }
        let point = touch.location(in: view)
        // Progress scrubber owns horizontal interaction.
        if progress.frame.insetBy(dx: -8, dy: -16).contains(point) { return false }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
