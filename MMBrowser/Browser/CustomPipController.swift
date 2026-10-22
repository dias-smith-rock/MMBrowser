import UIKit
import AVFoundation
import AVKit
import MediaPlayer
import WebKit

/// Custom floating player → system PiP + Now Playing on background → custom again on foreground.
@MainActor
final class CustomPipController: NSObject {
    static let shared = CustomPipController()

    enum Mode {
        case idle
        case custom
        case system
    }

    private(set) var mode: Mode = .idle

    private var player: AVPlayer?
    private var pipController: AVPictureInPictureController?
    private var floatingView: CustomPipFloatingView?
    private weak var hostView: UIView?
    private weak var webController: WebViewController?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var presentationSizeObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    /// width / height; default landscape 16:9 until the item reports a real size.
    private var videoAspect: CGFloat = 16.0 / 9.0
    private var timeObserver: Any?
    private var isHandoffInProgress = false
    private var suppressForegroundRestore = false
    private var nowPlayingTitle = "Video"
    private var streamURL: URL?
    private var didUserCloseSystemPip = false
    private weak var fullscreenController: CustomPipFullscreenViewController?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Returns `true` when custom player started; `false` means caller should use legacy WK PiP.
    @discardableResult
    func startFromUserAction(
        web: WebViewController,
        hostView: UIView,
        completion: ((Bool) -> Void)? = nil
    ) -> Bool {
        guard AppSettings.pictureInPictureEnabled else {
            completion?(false)
            return false
        }
        guard let candidate = web.pipStreamCandidate else {
            completion?(false)
            return false
        }

        stop(reason: "restart")
        hostView.window?.endEditing(true)
        self.hostView = hostView
        self.webController = web
        self.nowPlayingTitle = web.webView?.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? candidate.url.host
            ?? "Video"
        self.streamURL = candidate.url
        self.didUserCloseSystemPip = false

        MediaPlaybackSupport.configureAudioSessionIfNeeded(forceReactivate: true)
        MediaPlaybackSupport.pauseMediaIfNeeded(in: web.webView, owner: web)

        let pageURL = web.webView?.url?.absoluteString
        let headers = DownloadManager.defaultExtraHeaders(for: candidate.url, pageURL: pageURL)
        let store = web.webView?.configuration.websiteDataStore.httpCookieStore

        let begin: ([HTTPCookie]) -> Void = { [weak self] cookies in
            guard let self else {
                completion?(false)
                return
            }
            var allHeaders = headers
            if !cookies.isEmpty {
                for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
                    allHeaders[k] = v
                }
            }
            self.startPlayer(url: candidate.url, headers: allHeaders, hostView: hostView)
            PipSession.claim(web)
            AppAnalytics.logPipEnter(source: "custom", host: AppAnalytics.privacyHost(candidate.url))
            completion?(true)
        }

        if let store {
            store.getAllCookies { all in
                let matched = DownloadManager.cookies(
                    for: candidate.url,
                    from: all,
                    pageURL: pageURL
                )
                DispatchQueue.main.async { begin(matched) }
            }
        } else {
            begin([])
        }
        return true
    }

    var isActive: Bool { mode != .idle }

    /// User tapped play on a webpage — leave custom float so inline media can take over.
    func dismissForPageUserPlay(from web: WebViewController) {
        guard mode != .idle else { return }
        let samePage = webController === web
        PipProbe.log("customPip.pageUserPlay", [
            "samePage": samePage,
            "host": web.webView?.url?.host ?? "?"
        ])
        suppressForegroundRestore = true
        stop(reason: samePage ? "pageUserPlay" : "otherTabUserPlay")
    }

    func stop(reason: String) {
        PipProbe.log("customPip.stop", ["reason": reason, "mode": "\(mode)"])
        clearNowPlaying()
        removeTimeObserver()
        endObserver.map { NotificationCenter.default.removeObserver($0) }
        endObserver = nil
        statusObservation = nil
        rateObservation = nil
        presentationSizeObservation = nil
        videoAspect = 16.0 / 9.0
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        pipController = nil
        if fullscreenController != nil {
            fullscreenController?.dismiss(animated: false)
            fullscreenController = nil
        }
        player?.pause()
        player = nil
        floatingView?.removeFromSuperview()
        floatingView = nil
        mode = .idle
        isHandoffInProgress = false
        streamURL = nil
        if let web = webController {
            PipSession.releaseIfOwner(web)
        }
        webController = nil
        hostView = nil
    }

    // MARK: - Player

    private func startPlayer(url: URL, headers: [String: String], hostView: UIView) {
        let options: [String: Any] = headers.isEmpty
            ? [:]
            : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.player = player

        let floating = CustomPipFloatingView()
        floating.attach(player: player)
        floating.onClose = { [weak self] in
            self?.suppressForegroundRestore = true
            self?.stop(reason: "userClose")
        }
        floating.onReturnToPage = { [weak self] in
            self?.returnToPage()
        }
        floating.onTogglePlay = { [weak self] in
            self?.togglePlay()
        }
        floating.onSeekBy = { [weak self] delta in
            self?.seekBy(delta)
        }
        floating.onSeekToFraction = { [weak self] fraction in
            self?.seekToFraction(fraction)
        }
        floating.onFullscreen = { [weak self] in
            self?.presentFullscreen()
        }
        hostView.addSubview(floating)
        floating.frame = Self.preferredFloatingFrame(aspect: videoAspect, in: hostView)
        floating.videoAspect = videoAspect
        floatingView = floating
        hostView.bringSubviewToFront(floating)

        configureSystemPip(playerLayer: floating.playerLayer)
        observePlayer(player)
        observePresentationSize(item)
        addTimeObserver()
        player.play()
        mode = .custom
        updateNowPlaying(isPlaying: true)
        remoteCommandsEnabled(true)
        PipProbe.log("customPip.start", [
            "host": url.host ?? "?",
            "hls": url.pathExtension.lowercased() == "m3u8"
        ])
    }

    private func observePresentationSize(_ item: AVPlayerItem) {
        presentationSizeObservation = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            let size = item.presentationSize
            guard size.width > 1, size.height > 1 else { return }
            Task { @MainActor in
                self?.applyVideoSize(size)
            }
        }
    }

    private func applyVideoSize(_ size: CGSize) {
        let aspect = size.width / size.height
        guard aspect.isFinite, aspect > 0.05, aspect < 20 else { return }
        let changed = abs(aspect - videoAspect) > 0.02
        videoAspect = aspect
        floatingView?.videoAspect = aspect
        // Portrait has no large window — drop back to small if needed.
        if aspect < 1 {
            floatingView?.setWindowSize(.small, animated: changed)
        } else if changed, let floatingView, !floatingView.isDocked {
            floatingView.applyWindowSize(animated: true)
        }
        PipProbe.log("customPip.aspect", [
            "w": Int(size.width),
            "h": Int(size.height),
            "portrait": aspect < 1
        ])
    }

    enum FloatingWindowSize {
        case small
        case large
    }

    /// Small: compact PiP. Large (landscape only): width = screen − side margins.
    static func preferredFloatingFrame(
        aspect: CGFloat,
        in hostView: UIView,
        size windowSize: FloatingWindowSize = .small,
        preservingCenter: CGPoint? = nil
    ) -> CGRect {
        let safe = hostView.safeAreaInsets
        let inset: CGFloat = 12
        let maxH = hostView.bounds.height - safe.top - safe.bottom - 96
        let resolvedSize: FloatingWindowSize = (aspect < 1) ? .small : windowSize

        let size: CGSize
        switch resolvedSize {
        case .large:
            // Full width minus margins; height follows aspect, capped to safe area.
            var w = hostView.bounds.width - inset * 2
            var h = w / max(aspect, 0.05)
            if h > maxH {
                h = maxH
                w = h * aspect
            }
            size = CGSize(width: w, height: h)
        case .small:
            let maxW = min(hostView.bounds.width - inset * 2, 300)
            let smallMaxH = min(maxH, aspect < 1 ? 420 : 220)
            if aspect >= 1 {
                var w = maxW
                var h = w / aspect
                if h > smallMaxH {
                    h = smallMaxH
                    w = h * aspect
                }
                size = CGSize(width: w, height: h)
            } else {
                let portraitMaxW = min(hostView.bounds.width - inset * 2, 200)
                var w = portraitMaxW
                var h = w / aspect
                if h > smallMaxH {
                    h = smallMaxH
                    w = h * aspect
                }
                size = CGSize(width: w, height: h)
            }
        }

        let minX = inset
        let maxX = hostView.bounds.width - size.width - inset
        let minY = safe.top + inset
        let maxY = hostView.bounds.height - size.height - safe.bottom - 88

        let origin: CGPoint
        if let center = preservingCenter {
            var x = center.x - size.width / 2
            var y = center.y - size.height / 2
            x = min(max(x, minX), max(maxX, minX))
            y = min(max(y, minY), max(maxY, minY))
            origin = CGPoint(x: x, y: y)
        } else if resolvedSize == .large {
            // Center large window horizontally; keep near bottom like small default.
            origin = CGPoint(
                x: (hostView.bounds.width - size.width) / 2,
                y: max(maxY, minY)
            )
        } else {
            origin = CGPoint(
                x: max(maxX, minX),
                y: max(maxY, minY)
            )
        }
        return CGRect(origin: origin, size: size)
    }

    private func configureSystemPip(playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        let controller = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller
    }

    private func observePlayer(_ player: AVPlayer) {
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.floatingView?.setPlaying(player.rate > 0.01)
                self?.updateNowPlaying(isPlaying: player.rate > 0.01)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemEnded()
            }
        }
    }

    private func togglePlay() {
        guard let player else { return }
        if player.rate > 0.01 {
            player.pause()
        } else {
            player.play()
        }
    }

    private func returnToPage() {
        // Close floating player and leave page media available again.
        suppressForegroundRestore = true
        stop(reason: "returnToPage")
    }

    private func seekBy(_ delta: TimeInterval) {
        let next = max(0, currentSeconds() + delta)
        let duration = player?.currentItem?.duration.seconds ?? .infinity
        let clamped = duration.isFinite ? min(next, max(duration - 0.05, 0)) : next
        seek(to: clamped) { [weak self] in
            self?.player?.play()
        }
    }

    private func seekToFraction(_ fraction: Double) {
        let duration = player?.currentItem?.duration.seconds ?? 0
        guard duration.isFinite, duration > 0 else { return }
        seek(to: duration * min(max(fraction, 0), 1)) { [weak self] in
            self?.player?.play()
        }
    }

    private func presentFullscreen() {
        guard let player, let host = hostView?.window?.rootViewController else { return }
        floatingView?.undockIfNeeded()
        floatingView?.isHidden = true
        // Temporarily detach floating layer so fullscreen can attach.
        floatingView?.playerLayer.player = nil
        let full = CustomPipFullscreenViewController(player: player)
        full.onTogglePlay = { [weak self] in self?.togglePlay() }
        full.onSeekBy = { [weak self] d in self?.seekBy(d) }
        full.onSeekToFraction = { [weak self] f in self?.seekToFraction(f) }
        full.onDismiss = { [weak self] in
            guard let self else { return }
            self.floatingView?.playerLayer.player = self.player
            self.floatingView?.isHidden = false
            self.fullscreenController = nil
            if let hostView = self.hostView, let floating = self.floatingView {
                hostView.bringSubviewToFront(floating)
            }
            // Re-bind system PiP to the floating layer.
            if let layer = self.floatingView?.playerLayer {
                self.configureSystemPip(playerLayer: layer)
            }
        }
        fullscreenController = full
        var presenter: UIViewController = host
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(full, animated: true)
    }

    private func currentSeconds() -> Double {
        guard let t = player?.currentTime(), t.isNumeric, !t.seconds.isNaN else { return 0 }
        return max(0, t.seconds)
    }

    private func durationSeconds() -> Double {
        guard let d = player?.currentItem?.duration, d.isNumeric, !d.seconds.isNaN else { return 0 }
        return max(0, d.seconds)
    }

    private func seek(to seconds: Double, completion: (() -> Void)? = nil) {
        guard let player else {
            completion?()
            return
        }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.25, preferredTimescale: 600)) { _ in
            DispatchQueue.main.async { completion?() }
        }
    }

    private func addTimeObserver() {
        removeTimeObserver()
        guard let player else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.floatingView?.updateProgress(current: self.currentSeconds(), duration: self.durationSeconds())
            self.updateNowPlaying(isPlaying: (self.player?.rate ?? 0) > 0.01)
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    // MARK: - Lifecycle handoff

    @objc private func appDidEnterBackground() {
        guard mode == .custom, !isHandoffInProgress else { return }
        handoffToSystemPiP()
    }

    @objc private func appWillEnterForeground() {
        // Prefer become-active for restore (after animations).
    }

    @objc private func appDidBecomeActive() {
        guard mode == .system || (mode == .custom && pipController?.isPictureInPictureActive == true) else { return }
        if didUserCloseSystemPip || suppressForegroundRestore {
            suppressForegroundRestore = false
            if didUserCloseSystemPip {
                stop(reason: "systemPipClosed")
            }
            return
        }
        restoreCustomFromSystemPiP()
    }

    private func handoffToSystemPiP() {
        guard let pipController, pipController.isPictureInPicturePossible else {
            // Keep AVPlayer playing in background via audio session; no visual PiP.
            PipProbe.log("customPip.handoff.skip", ["why": "pipNotPossible"])
            updateNowPlaying(isPlaying: (player?.rate ?? 0) > 0)
            return
        }
        isHandoffInProgress = true
        let seconds = currentSeconds()
        PipProbe.log("customPip.handoff.toSystem", ["t": String(format: "%.2f", seconds)])
        floatingView?.undockIfNeeded()
        floatingView?.isHidden = true
        pipController.startPictureInPicture()
        // Ensure playback continues.
        player?.play()
        mode = .system
        updateNowPlaying(isPlaying: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isHandoffInProgress = false
        }
    }

    private func restoreCustomFromSystemPiP() {
        guard !isHandoffInProgress else { return }
        isHandoffInProgress = true
        let seconds = currentSeconds()
        PipProbe.log("customPip.handoff.toCustom", ["t": String(format: "%.2f", seconds)])
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        floatingView?.isHidden = false
        if let hostView, let floatingView {
            hostView.bringSubviewToFront(floatingView)
        }
        seek(to: seconds) { [weak self] in
            self?.player?.play()
            self?.mode = .custom
            self?.floatingView?.setPlaying(true)
            self?.updateNowPlaying(isPlaying: true)
            self?.isHandoffInProgress = false
        }
    }

    // MARK: - Sticky

    private func handleItemEnded() {
        floatingView?.setPlaying(false)
        updateNowPlaying(isPlaying: false)
        guard AppSettings.stickyPictureInPicture, let web = webController else {
            return
        }
        PipProbe.log("customPip.ended.sticky", ["host": streamURL?.host ?? "?"])
        // Ask page sticky path to advance; then try custom again, else legacy.
        MediaPlaybackSupport.applyStickyPrefer(in: web.webView, prefer: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak web] in
            guard let self, let web else { return }
            if let next = web.pipStreamCandidate, next.url != self.streamURL {
                let host = self.hostView
                self.stop(reason: "stickyNext")
                if let host {
                    _ = self.startFromUserAction(web: web, hostView: host, completion: nil)
                }
            } else {
                // Fall back to legacy sticky PiP on the page.
                let host = self.hostView
                self.stop(reason: "stickyLegacy")
                web.enterPictureInPictureFromUserAction(showFailureToast: false, completion: nil)
                _ = host
            }
        }
    }

    // MARK: - Now Playing

    private func remoteCommandsEnabled(_ on: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        guard on else { return }
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.player?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.player?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.togglePlay() }
            return .success
        }
    }

    private func updateNowPlaying(isPlaying: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let item = player?.currentItem {
            let duration = item.duration
            if duration.isNumeric, !duration.seconds.isNaN {
                info[MPMediaItemPropertyPlaybackDuration] = duration.seconds
            }
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentSeconds()
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        remoteCommandsEnabled(false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

extension CustomPipController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            self.mode = .system
            self.floatingView?.isHidden = true
            PipProbe.log("customPip.system.started", [:])
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            PipProbe.log("customPip.system.stopped", [
                "handoff": self.isHandoffInProgress,
                "appState": UIApplication.shared.applicationState.rawValue
            ])
            if UIApplication.shared.applicationState != .active, !self.isHandoffInProgress {
                // User closed system PiP while in background.
                self.didUserCloseSystemPip = true
            }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            PipProbe.log("customPip.system.fail", ["error": error.localizedDescription])
            self.floatingView?.isHidden = false
            self.mode = .custom
            self.player?.play()
            self.isHandoffInProgress = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            self.restoreCustomFromSystemPiP()
            completionHandler(true)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
