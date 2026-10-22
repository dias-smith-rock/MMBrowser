import UIKit
import AVFoundation
import SnapKit

/// In-app fullscreen player sharing the same `AVPlayer` as the floating window.
final class CustomPipFullscreenViewController: UIViewController {
    var onDismiss: (() -> Void)?
    var onTogglePlay: (() -> Void)?
    var onSeekBy: ((TimeInterval) -> Void)?
    var onSeekToFraction: ((Double) -> Void)?
    var onCloseSession: (() -> Void)?

    private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let overlay = UIView()
    private let closeButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let progress = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private var hideWorkItem: DispatchWorkItem?
    private var timeObserver: Any?
    private var isScrubbing = false

    init(player: AVPlayer) {
        self.player = player
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)

        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        view.addSubview(overlay)

        configureButtons()
        overlay.addSubview(closeButton)
        overlay.addSubview(rewindButton)
        overlay.addSubview(playButton)
        overlay.addSubview(forwardButton)
        overlay.addSubview(progress)
        overlay.addSubview(elapsedLabel)
        overlay.addSubview(remainingLabel)

        overlay.snp.makeConstraints { $0.edges.equalToSuperview() }
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(16)
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleOverlay))
        view.addGestureRecognizer(tap)
        scheduleHide()
        addTimeObserver()
        refreshPlayIcon()
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
        // Detach layer so floating view can own the player again.
        playerLayer.player = nil
        onDismiss?()
    }

    private func configureButtons() {
        func style(_ button: UIButton, symbol: String, size: CGFloat) {
            button.tintColor = .white
            button.setImage(
                UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .bold)),
                for: .normal
            )
            button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
            button.layer.cornerRadius = button == playButton ? 32 : (button == closeButton ? 18 : 22)
        }
        style(closeButton, symbol: "xmark", size: 14)
        style(rewindButton, symbol: "gobackward.10", size: 18)
        style(playButton, symbol: "pause.fill", size: 22)
        style(forwardButton, symbol: "goforward.10", size: 18)

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
    }

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
            UIView.animate(withDuration: 0.2) { self?.overlay.alpha = 0 }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    @objc private func toggleOverlay() {
        if overlay.alpha < 0.5 {
            UIView.animate(withDuration: 0.2) { self.overlay.alpha = 1 }
            scheduleHide()
        } else {
            UIView.animate(withDuration: 0.2) { self.overlay.alpha = 0 }
        }
    }

    @objc private func closeTapped() {
        // Exit fullscreen back to floating (keep playing).
        dismiss(animated: true)
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
