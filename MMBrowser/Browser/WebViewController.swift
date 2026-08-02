import UIKit
import WebKit
import SnapKit

protocol WebViewControllerDelegate: AnyObject {
    func webViewController(_ controller: WebViewController, didUpdateTitle title: String?)
    func webViewController(_ controller: WebViewController, didUpdateURL url: URL?)
    func webViewController(_ controller: WebViewController, didUpdateProgress progress: Double, isLoading: Bool)
    func webViewController(_ controller: WebViewController, didUpdateNavigationState canGoBack: Bool, canGoForward: Bool)
    func webViewController(_ controller: WebViewController, requestNewTabFor url: URL)
    func webViewControllerDidFail(_ controller: WebViewController, error: Error)
    func webViewController(_ controller: WebViewController, present reader: UIViewController)
    func webViewController(_ controller: WebViewController, warnDangerous url: URL, proceed: @escaping () -> Void)
    func webViewController(_ controller: WebViewController, didScroll deltaY: CGFloat, offsetY: CGFloat)
    func webViewController(_ controller: WebViewController, didUpdateBlockCount count: Int)
    func webViewControllerDidReportYouTubeDegraded(_ controller: WebViewController)
    func webViewController(_ controller: WebViewController, didTriggerGestureAction action: GestureBrowserAction)
    func webViewController(_ controller: WebViewController, didDetectSessionAvatar url: URL?)
}

final class WebViewController: UIViewController {
    weak var delegate: WebViewControllerDelegate?

    /// Rewrites viewport meta so pinch-zoom works like Safari on restrictive pages.
    /// Skipped on YouTube: unlocking scale there commonly breaks mobile layout width.
    private static let viewportZoomUnlockScript = WKUserScript(
        source: """
        (function() {
          var h = (location.hostname || '').toLowerCase();
          if (h === 'youtu.be' || h.indexOf('youtube.com') !== -1 || h.indexOf('youtube-nocookie.com') !== -1) {
            return;
          }
          function unlock() {
            var metas = document.querySelectorAll('meta[name="viewport"]');
            if (!metas.length) {
              var meta = document.createElement('meta');
              meta.name = 'viewport';
              meta.content = 'width=device-width, initial-scale=1, maximum-scale=10, user-scalable=yes';
              (document.head || document.documentElement).appendChild(meta);
              return;
            }
            for (var i = 0; i < metas.length; i++) {
              var content = metas[i].getAttribute('content') || '';
              content = content.replace(/user-scalable\\s*=\\s*no/ig, 'user-scalable=yes');
              content = content.replace(/maximum-scale\\s*=\\s*[0-9.]+/ig, 'maximum-scale=10');
              if (!/user-scalable\\s*=/i.test(content)) content += ', user-scalable=yes';
              if (!/maximum-scale\\s*=/i.test(content)) content += ', maximum-scale=10';
              metas[i].setAttribute('content', content);
            }
          }
          unlock();
          document.addEventListener('DOMContentLoaded', unlock, { once: true });
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    /// Forces YouTube (and similar) back to a sane mobile viewport if something widened it.
    private static let youtubeViewportFixScript = """
    (function() {
      var h = (location.hostname || '').toLowerCase();
      if (h !== 'youtu.be' && h.indexOf('youtube.com') === -1 && h.indexOf('youtube-nocookie.com') === -1) return;
      var content = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
      var metas = document.querySelectorAll('meta[name="viewport"]');
      if (!metas.length) {
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = content;
        (document.head || document.documentElement).appendChild(meta);
      } else {
        for (var i = 0; i < metas.length; i++) {
          metas[i].setAttribute('content', content);
        }
      }
      // Remove our older overflow clamp if a previous build injected it.
      var clamp = document.getElementById('mm-overflow-clamp');
      if (clamp && clamp.parentNode) clamp.parentNode.removeChild(clamp);
    })();
    """

    private(set) var webView: WKWebView?
    private let isIncognito: Bool
    /// Persistent store for normal tabs; ignored when `isIncognito` (uses non-persistent).
    private let websiteDataStore: WKWebsiteDataStore
    /// Geolocation deny/spoof for this tab (container-specific for normal tabs).
    private let geoConfiguration: GeolocationSpoof.Configuration
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var lastFailedURL: URL?
    private var pendingURL: URL?
    private var didSetupWebView = false
    private var httpsFallbackAttempted = false
    private var preferDesktop = false
    private var findBar: FindInPageBar?
    private var lastFindQuery: String?
    private(set) var isPageCleanerActive = false
    private var cleanerURLOnly = false
    var onPageCleanerActiveChanged: ((Bool) -> Void)?
    private var scriptMessageProxy: WebViewScriptProxy?
    private var pageCleanerObserver: NSObjectProtocol?
    private var contentOffsetObservation: NSKeyValueObservation?
    private let drawingGestures = DrawingGestureController()
    private var gestureSettingsObserver: NSObjectProtocol?
    private let autofillCoordinator = BrowserAutofillCoordinator()
    /// When true, the page video is in system Picture in Picture.
    private(set) var isPictureInPictureActive = false
    /// Sticky intent: YouTube often reports a brief leave while the app becomes active.
    private var prefersPictureInPicture = false
    private var pipForegroundObserver: NSObjectProtocol?
    private var pipLeaveWorkItem: DispatchWorkItem?
    /// Native PiP entry chip — shown while a page video is playing (hidden on YouTube Music).
    private lazy var pipEntryButton: UIButton = makePipEntryButton()
    private var pipVideoPollTimer: Timer?
    /// True when the page reports an actively playing (or PiP) `<video>`.
    private var pageHasPlayingVideo = false
    /// Prevents stacked auto-enter retries while sticky PiP waits for a video element.
    private var stickyPipEnterInFlight = false
    /// After a PiP leave, suppress sticky auto-restore briefly so a manual close can clear prefer.
    private var suppressStickyPipRestoreUntil: Date?
    /// After yielding to another tab, ignore stale active:true while system PiP tears down.
    private var suppressPipClaimUntil: Date?
    /// Last free-drag origin for the PiP button (session + UserDefaults).
    private var pipEntryButtonOrigin: CGPoint?
    private static let pipEntryOriginXKey = "media.pip.button.originX"
    private static let pipEntryOriginYKey = "media.pip.button.originY"

    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init(
        isIncognito: Bool,
        websiteDataStore: WKWebsiteDataStore = .default(),
        geoConfiguration: GeolocationSpoof.Configuration = .fromAppSettings()
    ) {
        self.isIncognito = isIncognito
        self.websiteDataStore = websiteDataStore
        self.geoConfiguration = geoConfiguration
        // Do not inherit global sticky — only the PiP owner tab may prefer PiP.
        self.prefersPictureInPicture = false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        setupErrorView()
        setupWebView()
    }

    private func setupWebView() {
        guard !didSetupWebView else { return }
        didSetupWebView = true
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isIncognito ? .nonPersistent() : websiteDataStore
        MediaPlaybackSupport.configureAudioSessionIfNeeded()
        MediaPlaybackSupport.apply(to: config)
        AdBlockManager.shared.apply(to: config) { [weak self] in
            guard let self = self else { return }
            ImageBlockManager.shared.apply(to: config) {
                self.finishWebViewSetup(with: config)
            }
        }
    }

    private func finishWebViewSetup(with config: WKWebViewConfiguration) {
        config.userContentController.addUserScript(YouTubeDarkMode.userScript)
        if YouTubeShortsFocus.isEnabled {
            config.userContentController.addUserScript(YouTubeShortsFocus.userScript)
        }
        if YouTubeAdShield.isEffectivelyEnabled {
            config.userContentController.addUserScript(YouTubeAdShield.userScript)
        }
        if let geoScript = GeolocationSpoof.userScript(configuration: geoConfiguration) {
            config.userContentController.addUserScript(geoScript)
        }
        // Unlock pinch-zoom on pages that set user-scalable=no / maximum-scale=1
        // (UIScrollView.ignoresViewportScaleLimits is unavailable in this SDK).
        // YouTube is excluded inside the script — unlocking breaks its mobile width.
        config.userContentController.addUserScript(Self.viewportZoomUnlockScript)
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.youtubeViewportFixScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let proxy = WebViewScriptProxy(target: self)
        scriptMessageProxy = proxy
        config.userContentController.add(proxy, name: PageCleanerManager.handlerName)
        if AppSettings.trackerProtectionEnabled {
            config.userContentController.add(proxy, name: AdBlockManager.blockCountHandlerName)
        }
        if YouTubeAdShield.isEffectivelyEnabled {
            config.userContentController.add(proxy, name: YouTubeAdShield.handlerName)
            config.userContentController.add(proxy, name: YouTubeAdShield.degradedHandlerName)
        }
        if AppSettings.noImagesEnabled {
            config.userContentController.add(proxy, name: ImageBlockManager.disableHandlerName)
        }
        if AppSettings.pictureInPictureEnabled || AppSettings.backgroundAudioEnabled {
            config.userContentController.add(proxy, name: MediaPlaybackSupport.pipHandlerName)
        }
        if !isIncognito {
            config.userContentController.addUserScript(BrowserAutofillCoordinator.userScript)
        }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
    // Full-page navigation uses hooked drawing strokes instead of edge swipes.
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.bounces = true
        wv.scrollView.bouncesZoom = true
        wv.scrollView.alwaysBounceVertical = true
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.isDirectionalLockEnabled = true
        wv.scrollView.isScrollEnabled = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 14.0, *) {
            wv.pageZoom = 1.0
        }
        view.insertSubview(wv, at: 0)
        // Edge-to-edge inside the browser chrome container. Top safe-area / Dynamic Island
        // usage is controlled by BrowserViewController collapsing the chrome.
        wv.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        webView = wv
        if !isIncognito {
            autofillCoordinator.hostViewController = self
            autofillCoordinator.attach(to: wv, isIncognito: isIncognito, contentController: config.userContentController)
        }
        if AppSettings.pictureInPictureEnabled || AppSettings.backgroundAudioEnabled {
            pipForegroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reinforcePictureInPictureAfterForeground()
            }
        }
        if AppSettings.pictureInPictureEnabled {
            setupPipEntryButton()
        }
        setupDrawingGestures()

        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let progress = webView.estimatedProgress
            let loading = webView.isLoading && webView.estimatedProgress < 1
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateProgress: progress, isLoading: loading)
            }
        }
        loadingObservation = wv.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            let progress = webView.estimatedProgress
            let loading = webView.isLoading && webView.estimatedProgress < 1
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateProgress: progress, isLoading: loading)
            }
        }
        titleObservation = wv.observe(\.title, options: [.new]) { [weak self] webView, _ in
            let title = webView.title
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateTitle: title)
            }
        }
        // WKWebView URL KVO can fire off the main thread; hop before touching UI.
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] webView, _ in
            let url = webView.url
            self?.notifyDelegateOnMain {
                YouTubeDarkMode.applyAppearance(to: webView, url: url)
                $0.delegate?.webViewController($0, didUpdateURL: url)
                $0.refreshPipEntryPolling()
            }
        }
        canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            let back = webView.canGoBack
            let forward = webView.canGoForward
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateNavigationState: back, canGoForward: forward)
            }
        }
        canGoForwardObservation = wv.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            let back = webView.canGoBack
            let forward = webView.canGoForward
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateNavigationState: back, canGoForward: forward)
            }
        }
        contentOffsetObservation = wv.scrollView.observe(\.contentOffset, options: [.new, .old]) { [weak self] scrollView, change in
            guard let self = self else { return }
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            let newY = scrollView.contentOffset.y
            let oldY = change.oldValue?.y ?? newY
            let delta = newY - oldY
            guard abs(delta) > 0.5 else { return }
            self.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didScroll: delta, offsetY: newY)
            }
        }

        if let pendingURL = pendingURL {
            self.pendingURL = nil
            loadPrepared(url: pendingURL, in: wv)
        }

        pageCleanerObserver = NotificationCenter.default.addObserver(
            forName: .pageCleanerRulesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let webView = self.webView else { return }
            PageCleanerManager.apply(to: webView, url: webView.url)
        }
    }

    fileprivate func handleNoImageScriptMessage(_ message: WKScriptMessage) {
        guard message.name == ImageBlockManager.disableHandlerName else { return }
        AppSettings.noImagesEnabled = false
    }

    fileprivate func handleBlockCountMessage(_ message: WKScriptMessage) {
        guard message.name == AdBlockManager.blockCountHandlerName else { return }
        let count: Int
        if let body = message.body as? [String: Any], let n = body["count"] as? Int {
            count = n
        } else if let n = message.body as? Int {
            count = n
        } else {
            return
        }
        delegate?.webViewController(self, didUpdateBlockCount: count)
    }

    fileprivate func handleYouTubeAdShieldMessage(_ message: WKScriptMessage) {
        if message.name == YouTubeAdShield.degradedHandlerName {
            FilterUpdateManager.shared.markYouTubeDegraded()
            delegate?.webViewControllerDidReportYouTubeDegraded(self)
            return
        }
        guard message.name == YouTubeAdShield.handlerName else { return }
        // Skip events are informational; block-count UI is driven by cosmetic detector.
    }

    fileprivate func handlePageCleanerMessage(_ message: WKScriptMessage) {
        guard message.name == PageCleanerManager.handlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              type == "delete",
              let selector = body["selector"] as? String,
              !selector.isEmpty,
              let webView = webView else { return }

        let label = (body["label"] as? String) ?? selector
        let host = (body["host"] as? String)?.lowercased()
            ?? webView.url?.host?.lowercased()
            ?? ""
        guard !host.isEmpty else { return }

        let normalizedRect = PageCleanerPreviewBuilder.normalizedRect(from: body)

        // Snapshot while the element is still visible, then hide.
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            let finish = {
                guard let self else { return }
                PageCleanerManager.hideSelector(selector, on: webView)

                if self.isIncognito {
                    Toast.show("Hidden for this session", from: self)
                    return
                }

                let urlString: String?
                if self.cleanerURLOnly, let url = webView.url {
                    urlString = PageCleanerStore.canonicalURLString(url)
                } else {
                    urlString = nil
                }

                var preview: UIImage?
                if let image, let normalizedRect {
                    preview = PageCleanerPreviewBuilder.makePreview(
                        snapshot: image,
                        normalizedRect: normalizedRect
                    )
                }

                if PageCleanerStore.shared.add(
                    host: host,
                    urlString: urlString,
                    selector: selector,
                    label: label,
                    previewImage: preview
                ) != nil {
                    Toast.show(urlString == nil ? "Hidden on this site" : "Hidden on this page", from: self)
                } else {
                    Toast.show("Already hidden", from: self)
                }
            }
            if Thread.isMainThread {
                finish()
            } else {
                DispatchQueue.main.async(execute: finish)
            }
        }
    }

    private func setupErrorView() {
        errorContainer.isHidden = true
        errorContainer.backgroundColor = BrowserTheme.background
        view.addSubview(errorContainer)
        errorLabel.textColor = BrowserTheme.textPrimary
        errorLabel.font = .systemFont(ofSize: 16)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        retryButton.setTitle("Retry", for: .normal)
        retryButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        errorContainer.addSubview(errorLabel)
        errorContainer.addSubview(retryButton)
        errorContainer.snp.makeConstraints { make in make.edges.equalToSuperview() }
        errorLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-20)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        retryButton.snp.makeConstraints { make in
            make.top.equalTo(errorLabel.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }
    }

    func load(url: URL) {
        errorContainer.isHidden = true
        lastFailedURL = nil
        httpsFallbackAttempted = false
        guard let webView = webView else {
            pendingURL = url
            return
        }
        loadPrepared(url: url, in: webView)
    }

    private func loadPrepared(url: URL, in webView: WKWebView) {
        if DangerousSiteGuard.isDangerous(url) {
            delegate?.webViewController(self, warnDangerous: url) { [weak self] in
                self?.actuallyLoad(url, in: webView)
            }
            return
        }
        actuallyLoad(url, in: webView)
    }

    private func actuallyLoad(_ url: URL, in webView: WKWebView) {
        YouTubeDarkMode.applyAppearance(to: webView, url: url)
        applyDesktopPreference(to: webView)
        let go = {
            if YouTubeDarkMode.isYouTube(url) {
                YouTubeDarkMode.ensureDarkCookie(in: webView.configuration.websiteDataStore) {
                    webView.load(URLRequest(url: url))
                }
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        go()
    }

    func goBack() { if webView?.canGoBack == true { webView?.goBack() } }
    func goForward() { if webView?.canGoForward == true { webView?.goForward() } }
    func reload() { webView?.reload() }

    func pageUp() {
        webView?.evaluateJavaScript(
            "window.scrollBy({top: -Math.max(120, window.innerHeight * 0.85), left: 0, behavior: 'smooth'});",
            completionHandler: nil
        )
    }

    func pageDown() {
        webView?.evaluateJavaScript(
            "window.scrollBy({top: Math.max(120, window.innerHeight * 0.85), left: 0, behavior: 'smooth'});",
            completionHandler: nil
        )
    }

    private func setupDrawingGestures() {
        drawingGestures.delegate = self
        drawingGestures.attach(to: view, lockScrollView: webView?.scrollView)
        if gestureSettingsObserver == nil {
            gestureSettingsObserver = NotificationCenter.default.addObserver(
                forName: .gestureSettingsChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshGestureSettings()
            }
        }
        refreshGestureSettings()
    }

    private func refreshGestureSettings() {
        drawingGestures.refreshEnabled()
    }

    func setPreferDesktop(_ enabled: Bool) {
        preferDesktop = enabled
        guard let webView = webView else { return }
        applyDesktopPreference(to: webView)
        webView.reload()
    }

    private func applyDesktopPreference(to webView: WKWebView) {
        if preferDesktop {
            webView.customUserAgent = desktopUA
        } else {
            webView.customUserAgent = nil
        }
    }

    func captureSnapshot(completion: @escaping (UIImage?) -> Void) {
        webView?.takeSnapshot(with: nil) { image, _ in completion(image) }
    }

    func openReaderMode() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(ReaderExtractor.script) { [weak self] result, _ in
            guard let self = self else { return }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = obj["ok"] as? Bool, ok,
                  let html = obj["html"] as? String else {
                Toast.show("Couldn't extract article", from: self)
                return
            }
            let title = (obj["title"] as? String) ?? (webView.title ?? "Reader")
            let reader = ReaderViewController(title: title, bodyHTML: html)
            let nav = UINavigationController(rootViewController: reader)
            nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
            BrowserTheme.applyNavigationBar(to: nav.navigationBar)
            self.delegate?.webViewController(self, present: nav)
        }
    }

    func showFindInPage() {
        exitPageCleaner()
        guard findBar == nil else { findBar?.focus(); return }
        let bar = FindInPageBar()
        bar.delegate = self
        view.addSubview(bar)
        bar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.height.equalTo(52)
        }
        findBar = bar
        bar.focus()
    }

    func enterPageCleaner(urlOnly: Bool) {
        if let findBar = findBar {
            findBarDidDismiss(findBar)
        }
        guard webView?.url != nil else {
            Toast.show("No page to clean", from: self)
            return
        }
        cleanerURLOnly = urlOnly
        let wasActive = isPageCleanerActive
        isPageCleanerActive = true
        if let webView = webView {
            PageCleanerManager.setPickMode(enabled: true, on: webView)
        }
        if !wasActive {
            onPageCleanerActiveChanged?(true)
        }
    }

    func exitPageCleaner() {
        guard isPageCleanerActive else { return }
        if let webView = webView {
            PageCleanerManager.setPickMode(enabled: false, on: webView)
        }
        cleanerURLOnly = false
        isPageCleanerActive = false
        onPageCleanerActiveChanged?(false)
    }

    func saveReadingList() {
        guard !isIncognito else {
            Toast.show("Not available in Private Browsing", from: self)
            return
        }
        guard let webView = webView, let url = webView.url else {
            Toast.show("No page to save", from: self)
            return
        }
        let title = webView.title ?? url.host ?? "Saved"
        if #available(iOS 14.0, *) {
            let config = WKPDFConfiguration()
            webView.createPDF(configuration: config) { result in
                let data = try? result.get()
                ReadingListStore.shared.add(title: title, url: url, pdfData: data)
                Toast.show("Saved to Reading List", from: self)
            }
        } else {
            ReadingListStore.shared.add(title: title, url: url, pdfData: nil)
            Toast.show("Saved to Reading List", from: self)
        }
    }

    func sharePDF() {
        guard let webView = webView else { return }
        if #available(iOS 14.0, *) {
            webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let data):
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("page.pdf")
                    try? data.write(to: url)
                    let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    self.delegate?.webViewController(self, present: activity)
                case .failure:
                    Toast.show("PDF failed", from: self)
                }
            }
        } else {
            Toast.show("PDF requires iOS 14+", from: self)
        }
    }

    func printPage() {
        guard let webView = webView else { return }
        let info = UIPrintInfo(dictionary: nil)
        let pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        info.jobName = pageTitle.isEmpty ? (webView.url?.host ?? "Page") : pageTitle
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        controller.present(animated: true)
    }

    func setPageZoom(_ zoom: CGFloat) {
        guard let webView = webView else { return }
        if #available(iOS 14.0, *) {
            webView.pageZoom = max(0.5, min(zoom, 3.0))
        } else {
            Toast.show("Text size requires iOS 14+", from: self)
        }
    }

    func screenshot() {
        guard let webView = webView else { return }
        ScreenshotPerf.beginSession("manual_screenshot")
        ScreenshotPerf.mark(
            "ui.screenshot.tapped",
            extra: String(
                format: "loading=%@ progress=%.2f",
                webView.isLoading ? "YES" : "NO",
                webView.estimatedProgress
            )
        )
        // Avoid modal toast here: capture often finishes in ~100ms and a UIAlertController
        // would still be presented, causing the editor present to fail intermittently.
        let captureStart = ScreenshotPerf.now()
        LongScreenshotCapturer.captureViewport(from: webView) { [weak self] image in
            guard let self = self else { return }
            ScreenshotPerf.mark("ui.capture.callback", since: captureStart)
            guard let image = image else {
                ScreenshotPerf.mark("ui.screenshot.failed")
                Toast.show("Screenshot failed", from: self)
                return
            }
            let buildStart = ScreenshotPerf.now()
            let editor = ScreenshotEditorViewController(image: image)
            ScreenshotPerf.mark(
                "ui.editor.init",
                since: buildStart,
                extra: "image=\(Int(image.size.width))x\(Int(image.size.height))@\(image.scale)"
            )
            let presentStart = ScreenshotPerf.now()
            self.delegate?.webViewController(self, present: editor)
            ScreenshotPerf.mark("ui.editor.present.called", since: presentStart)
        }
    }

    func longScreenshot() {
        guard let webView = webView else { return }
        // Same present race as screenshot — skip modal progress toast.
        LongScreenshotCapturer.capture(from: webView) { [weak self] image in
            guard let self = self else { return }
            guard let image = image else {
                Toast.show("Screenshot failed", from: self)
                return
            }
            let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
            self.delegate?.webViewController(self, present: activity)
        }
    }

    func downloadCurrentIfFile() {
        guard !isIncognito else {
            Toast.show("Downloads are disabled in Private Browsing", from: self)
            return
        }
        guard let url = webView?.url else { return }
        let ext = url.pathExtension.lowercased()
        let fileLike = ["pdf", "zip", "png", "jpg", "jpeg", "gif", "mp3", "mp4", "mov", "dmg", "pkg", "csv", "txt"].contains(ext)
        guard fileLike else {
            Toast.show("Open a downloadable file URL first", from: self)
            return
        }
        DownloadManager.shared.download(from: url, suggestedName: url.lastPathComponent) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let item):
                Toast.show("Downloaded \(item.fileName)", from: self)
            case .failure(let error):
                Toast.show(error.localizedDescription, from: self)
            }
        }
    }

    func cleanup() {
        progressObservation = nil
        loadingObservation = nil
        titleObservation = nil
        urlObservation = nil
        canGoBackObservation = nil
        canGoForwardObservation = nil
        contentOffsetObservation = nil
        if let gestureSettingsObserver = gestureSettingsObserver {
            NotificationCenter.default.removeObserver(gestureSettingsObserver)
            self.gestureSettingsObserver = nil
        }
        drawingGestures.detach()
        if let pageCleanerObserver = pageCleanerObserver {
            NotificationCenter.default.removeObserver(pageCleanerObserver)
            self.pageCleanerObserver = nil
        }
        exitPageCleaner()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: ImageBlockManager.disableHandlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: PageCleanerManager.handlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: BrowserAutofillCoordinator.messageName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: MediaPlaybackSupport.pipHandlerName)
        if let pipForegroundObserver {
            NotificationCenter.default.removeObserver(pipForegroundObserver)
            self.pipForegroundObserver = nil
        }
        scriptMessageProxy = nil
        pipLeaveWorkItem?.cancel()
        pipLeaveWorkItem = nil
        pipVideoPollTimer?.invalidate()
        pipVideoPollTimer = nil
        PipSession.releaseIfOwner(self)
        prefersPictureInPicture = false
        setPictureInPictureActive(false)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    private func makePipEntryButton() -> UIButton {
        let button = UIButton(type: .system)
        button.isHidden = true
        button.accessibilityLabel = "Picture in Picture"
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseForegroundColor = .white
        config.baseBackgroundColor = BrowserTheme.chromeBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        config.image = UIImage(systemName: "pip.enter")
        config.imagePadding = 6
        config.title = "PiP"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 13, weight: .semibold)
            return outgoing
        }
        button.configuration = config
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.35
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 6
        button.addTarget(self, action: #selector(pipEntryTapped), for: .touchUpInside)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pipEntryPanned(_:)))
        pan.maximumNumberOfTouches = 1
        button.addGestureRecognizer(pan)
        return button
    }

    private func setupPipEntryButton() {
        if pipEntryButton.superview == nil {
            view.addSubview(pipEntryButton)
        }
        loadPipEntryButtonOriginIfNeeded()
        layoutPipEntryButton()
        refreshPipEntryPolling()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !pipEntryButton.isHidden else { return }
        layoutPipEntryButton()
    }

    private func loadPipEntryButtonOriginIfNeeded() {
        guard pipEntryButtonOrigin == nil else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.pipEntryOriginXKey) != nil,
           defaults.object(forKey: Self.pipEntryOriginYKey) != nil {
            pipEntryButtonOrigin = CGPoint(
                x: defaults.double(forKey: Self.pipEntryOriginXKey),
                y: defaults.double(forKey: Self.pipEntryOriginYKey)
            )
        }
    }

    private func persistPipEntryButtonOrigin() {
        guard let origin = pipEntryButtonOrigin else { return }
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: Self.pipEntryOriginXKey)
        defaults.set(origin.y, forKey: Self.pipEntryOriginYKey)
    }

    private func pipEntryButtonSize() -> CGSize {
        pipEntryButton.invalidateIntrinsicContentSize()
        var size = pipEntryButton.intrinsicContentSize
        if size.width < 1 || size.height < 1 || size.width == UIView.noIntrinsicMetric {
            pipEntryButton.sizeToFit()
            size = pipEntryButton.bounds.size
        }
        if size.width < 1 || size.height < 1 {
            size = CGSize(width: 72, height: 36)
        }
        return size
    }

    /// Default: left side, below typical YouTube top chrome.
    private func defaultPipEntryButtonOrigin() -> CGPoint {
        let safe = view.safeAreaInsets
        return CGPoint(x: safe.left + 12, y: safe.top + 52)
    }

    private func clampPipEntryOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let safe = view.safeAreaInsets
        let inset: CGFloat = 8
        let minX = safe.left + inset
        let minY = safe.top + inset
        let maxX = max(minX, view.bounds.width - safe.right - size.width - inset)
        let maxY = max(minY, view.bounds.height - safe.bottom - size.height - inset)
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func layoutPipEntryButton() {
        guard pipEntryButton.superview != nil, view.bounds.width > 1, view.bounds.height > 1 else { return }
        let size = pipEntryButtonSize()
        let raw = pipEntryButtonOrigin ?? defaultPipEntryButtonOrigin()
        let origin = clampPipEntryOrigin(raw, size: size)
        pipEntryButtonOrigin = origin
        pipEntryButton.frame = CGRect(origin: origin, size: size)
    }

    @objc private func pipEntryPanned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            view.bringSubviewToFront(pipEntryButton)
        case .changed:
            let translation = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            let size = pipEntryButton.bounds.size
            let next = CGPoint(
                x: pipEntryButton.frame.origin.x + translation.x,
                y: pipEntryButton.frame.origin.y + translation.y
            )
            let origin = clampPipEntryOrigin(next, size: size)
            pipEntryButtonOrigin = origin
            pipEntryButton.frame = CGRect(origin: origin, size: size)
        case .ended, .cancelled:
            persistPipEntryButtonOrigin()
        default:
            break
        }
    }

    private func refreshPipEntryPolling() {
        pipVideoPollTimer?.invalidate()
        pipVideoPollTimer = nil
        if YouTubeDarkMode.isYouTubeMusic(webView?.url) || !AppSettings.pictureInPictureEnabled {
            pageHasPlayingVideo = false
        }
        updatePipEntryButtonVisibility()
        guard AppSettings.pictureInPictureEnabled,
              !YouTubeDarkMode.isYouTubeMusic(webView?.url)
        else { return }
        pollPlayableVideoForPiP()
        pipVideoPollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.pollPlayableVideoForPiP()
        }
    }

    private func pollPlayableVideoForPiP() {
        guard AppSettings.pictureInPictureEnabled,
              !YouTubeDarkMode.isYouTubeMusic(webView?.url) else {
            pageHasPlayingVideo = false
            updatePipEntryButtonVisibility()
            return
        }
        let js = """
        (function(){
          try {
            function walk(root, out) {
              if (!root) return out;
              try { root.querySelectorAll('video').forEach(function(v){ out.push(v); }); } catch (e) {}
              try {
                var all = root.querySelectorAll('*');
                for (var i = 0; i < all.length; i++) {
                  if (all[i].shadowRoot) walk(all[i].shadowRoot, out);
                }
              } catch (e) {}
              return out;
            }
            var vids = walk(document, []);
            if (!vids.length) return 'none';
            for (var i = 0; i < vids.length; i++) {
              var v = vids[i];
              if (v.webkitPresentationMode === 'picture-in-picture') return 'pip';
              if (document.pictureInPictureElement === v) return 'pip';
              if (!v.paused && !v.ended) return 'playing';
            }
            return 'idle';
          } catch (e) { return 'none'; }
        })();
        """
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let state = result as? String ?? "none"
                let inPip = state == "pip"
                let playing = state == "playing" || inPip
                self.pageHasPlayingVideo = playing
                if inPip {
                    if let until = self.suppressPipClaimUntil, Date() < until {
                        MediaPlaybackSupport.releasePictureInPicture(in: self.webView)
                        self.setPictureInPictureActive(false)
                        return
                    }
                    self.stickyPipEnterInFlight = false
                    self.persistPipPrefer(true)
                    self.setPictureInPictureActive(true)
                } else if self.isPictureInPictureActive {
                    // Avoid a stuck "active" flag after a false leave.
                    // Do not auto-restore sticky here — that re-opened PiP after a manual close.
                    self.syncPictureInPictureActiveFromPage()
                } else {
                    self.updatePipEntryButtonVisibility()
                }
            }
        }
    }

    private func persistPipPrefer(_ prefer: Bool) {
        prefersPictureInPicture = prefer
        if prefer {
            PipSession.claim(self)
            AppSettings.stickyPictureInPicture = true
        } else {
            AppSettings.stickyPictureInPicture = false
            PipSession.releaseIfOwner(self)
        }
    }

    /// Another tab claimed PiP or started playback — stop fighting for the audio session.
    func yieldPipOwnership(reason: String) {
        PipProbe.log("session.yield", [
            "reason": reason,
            "host": webView?.url?.host ?? "?",
            "wasActive": isPictureInPictureActive,
            "wasPrefer": prefersPictureInPicture
        ])
        stickyPipEnterInFlight = false
        pipLeaveWorkItem?.cancel()
        pipLeaveWorkItem = nil
        prefersPictureInPicture = false
        // Stale presentation-mode / scan pulses still report inPip while teardown runs.
        suppressPipClaimUntil = Date().addingTimeInterval(2.5)
        suppressStickyPipRestoreUntil = Date().addingTimeInterval(2.5)
        if PipSession.isOwner(self) {
            AppSettings.stickyPictureInPicture = false
            PipSession.releaseIfOwner(self)
        }
        setPictureInPictureActive(false)
        MediaPlaybackSupport.releasePictureInPicture(in: webView)
        // Second pass — first exit can race WebKit's PiP session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            MediaPlaybackSupport.releasePictureInPicture(in: self.webView)
        }
    }

    /// After a new document load, re-apply saved PiP intent and enter when a video is ready.
    private func restoreStickyPipIfNeeded() {
        guard AppSettings.pictureInPictureEnabled, AppSettings.stickyPictureInPicture else { return }
        // YouTube Music has no PiP surface — never sticky-restore there.
        guard !YouTubeDarkMode.isYouTubeMusic(webView?.url) else { return }
        guard PipSession.isOwner(self) else {
            // Global sticky may still be true from another tab — do not steal it.
            PipProbe.log("sticky.restore.skip", [
                "why": "notOwner",
                "host": webView?.url?.host ?? "?"
            ])
            return
        }
        if let until = suppressStickyPipRestoreUntil, Date() < until {
            PipProbe.log("sticky.restore.skip", ["why": "suppressAfterLeave"])
            return
        }
        PipProbe.log("sticky.restore", [
            "host": webView?.url?.host ?? "?",
            "isMusic": YouTubeDarkMode.isYouTubeMusic(webView?.url),
            "inFlight": stickyPipEnterInFlight,
            "nativeActive": isPictureInPictureActive
        ])
        PipProbe.requestTabDump(reason: "sticky.restore")
        MediaPlaybackSupport.probePageState(in: webView, reason: "sticky.restore")
        prefersPictureInPicture = true
        MediaPlaybackSupport.applyStickyPrefer(in: webView, prefer: true)
        guard !stickyPipEnterInFlight else {
            PipProbe.log("sticky.restore.skip", ["why": "inFlight"])
            return
        }
        stickyPipEnterInFlight = true
        attemptStickyPipEnter(retriesLeft: 10)
    }

    private func attemptStickyPipEnter(retriesLeft: Int) {
        guard AppSettings.pictureInPictureEnabled,
              AppSettings.stickyPictureInPicture,
              !YouTubeDarkMode.isYouTubeMusic(webView?.url),
              retriesLeft > 0 else {
            PipProbe.log("sticky.attempt.stop", [
                "left": retriesLeft,
                "sticky": AppSettings.stickyPictureInPicture,
                "host": webView?.url?.host ?? "?"
            ])
            stickyPipEnterInFlight = false
            return
        }
        PipProbe.log("sticky.attempt", [
            "left": retriesLeft,
            "host": webView?.url?.host ?? "?",
            "isMusic": YouTubeDarkMode.isYouTubeMusic(webView?.url)
        ])
        MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: webView)
        MediaPlaybackSupport.enterPictureInPicture(in: webView) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                guard AppSettings.stickyPictureInPicture else {
                    self.stickyPipEnterInFlight = false
                    PipProbe.log("sticky.attempt.abort", ["why": "stickyCleared"])
                    return
                }
                if ok || self.isPictureInPictureActive {
                    PipProbe.log("sticky.attempt.ok", [
                        "jsOk": ok,
                        "nativeActive": self.isPictureInPictureActive,
                        "host": self.webView?.url?.host ?? "?"
                    ])
                    self.stickyPipEnterInFlight = false
                    self.setPictureInPictureActive(true)
                    return
                }
                PipProbe.log("sticky.attempt.retry", [
                    "left": retriesLeft - 1,
                    "host": self.webView?.url?.host ?? "?"
                ])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    self?.attemptStickyPipEnter(retriesLeft: retriesLeft - 1)
                }
            }
        }
    }

    /// Align native PiP flags with the page (actual presentation + sticky prefer).
    private func syncPictureInPictureActiveFromPage() {
        let js = """
        (function(){
          try {
            var inPip = !!(window.__mmAnyInPiP && window.__mmAnyInPiP());
            var prefer = !!window.__mmPreferPip;
            return (inPip ? 2 : 0) + (prefer ? 1 : 0);
          } catch (e) { return 0; }
        })();
        """
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let code = (result as? Int) ?? (result as? NSNumber)?.intValue ?? 0
                let inPip = (code & 2) != 0
                let prefer = (code & 1) != 0
                if inPip {
                    self.persistPipPrefer(true)
                    self.setPictureInPictureActive(true)
                } else if prefer, PipSession.isOwner(self) || PipSession.owner == nil {
                    // Page still wants PiP (next-video reenter in progress). Keep sticky
                    // but do not force enter — JS owns reenter vs user-dismiss.
                    self.persistPipPrefer(true)
                    self.setPictureInPictureActive(false)
                } else if prefer {
                    // Another tab owns PiP — drop local prefer so we do not fight for audio.
                    self.prefersPictureInPicture = false
                    self.setPictureInPictureActive(false)
                    MediaPlaybackSupport.applyStickyPrefer(in: self.webView, prefer: false)
                } else if PipSession.isOwner(self) {
                    self.stickyPipEnterInFlight = false
                    self.persistPipPrefer(false)
                    self.setPictureInPictureActive(false)
                } else {
                    self.prefersPictureInPicture = false
                    self.setPictureInPictureActive(false)
                }
            }
        }
    }

    private func updatePipEntryButtonVisibility() {
        // Show while a page video is playing (or already in system PiP).
        // YouTube Music has no usable HTML video / PiP surface.
        let show = AppSettings.pictureInPictureEnabled
            && !YouTubeDarkMode.isYouTubeMusic(webView?.url)
            && !(webView?.isHidden ?? false)
            && (pageHasPlayingVideo || isPictureInPictureActive)
        pipEntryButton.isHidden = !show
        if show {
            if pipEntryButton.superview == nil {
                view.addSubview(pipEntryButton)
                loadPipEntryButtonOriginIfNeeded()
            }
            layoutPipEntryButton()
            view.bringSubviewToFront(pipEntryButton)
        }
    }

    @objc private func pipEntryTapped() {
        // Explicit user intent — allow PiP again after a prior yield suppress window.
        suppressPipClaimUntil = nil
        guard !YouTubeDarkMode.isYouTubeMusic(webView?.url) else { return }
        // Silent no-op when PiP cannot start (no toast / alert).
        MediaPlaybackSupport.enterPictureInPicture(in: webView) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self, ok else { return }
                self.persistPipPrefer(true)
                self.setPictureInPictureActive(true)
            }
        }
    }

    private func reinforcePictureInPictureAfterForeground() {
        guard PipSession.isOwner(self),
              prefersPictureInPicture || isPictureInPictureActive || AppSettings.stickyPictureInPicture,
              let webView else { return }
        // Page script decides reenter vs user-dismiss; do not mark active here.
        MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: webView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, PipSession.isOwner(self),
                  AppSettings.stickyPictureInPicture || self.prefersPictureInPicture else { return }
            MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: self.webView)
            self.syncPictureInPictureActiveFromPage()
        }
    }

    fileprivate func handlePictureInPictureMessage(_ message: WKScriptMessage) {
        guard message.name == MediaPlaybackSupport.pipHandlerName else { return }
        if let body = message.body as? [String: Any] {
            if body["diag"] as? Bool == true {
                PipProbe.logJS(body)
                return
            }
            if body["userPlay"] as? Bool == true {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    PipSession.handleTrustedUserPlay(from: self)
                }
            }
            if let playing = body["videoPlaying"] as? Bool {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.pageHasPlayingVideo = playing
                    self.updatePipEntryButtonVisibility()
                }
            } else if body["videoReady"] as? Bool != nil {
                DispatchQueue.main.async { [weak self] in
                    // Sticky reenter after next-track / media swap is owned by page JS.
                    // Restoring from every videoReady pulse re-opened PiP after a manual close.
                    self?.updatePipEntryButtonVisibility()
                }
            }
            if let active = body["active"] as? Bool {
                let prefer = body["prefer"] as? Bool
                DispatchQueue.main.async { [weak self] in
                    self?.handlePictureInPictureActiveChange(active, prefer: prefer)
                }
            }
            return
        }
        if let flag = message.body as? Bool {
            DispatchQueue.main.async { [weak self] in
                self?.handlePictureInPictureActiveChange(flag, prefer: nil)
            }
        }
    }

    private func handlePictureInPictureActiveChange(_ active: Bool, prefer: Bool?) {
        pipLeaveWorkItem?.cancel()
        pipLeaveWorkItem = nil

        PipProbe.log("native.activeChange", [
            "active": active,
            "prefer": prefer.map { $0 ? "true" : "false" } ?? "nil",
            "host": webView?.url?.host ?? "?",
            "sticky": AppSettings.stickyPictureInPicture,
            "nativeActive": isPictureInPictureActive
        ])

        if active {
            if let until = suppressPipClaimUntil, Date() < until {
                // Yielding to another tab — do not reclaim from teardown flicker.
                PipProbe.log("native.activeChange.ignored", [
                    "why": "yielding",
                    "host": webView?.url?.host ?? "?"
                ])
                setPictureInPictureActive(false)
                MediaPlaybackSupport.releasePictureInPicture(in: webView)
                return
            }
            // Only the tab that is actually presenting PiP may claim sticky ownership.
            suppressStickyPipRestoreUntil = nil
            persistPipPrefer(true)
            setPictureInPictureActive(true)
            return
        }

        // Left PiP. Never reinforce here — that re-opened PiP after the user closed it.
        setPictureInPictureActive(false)
        suppressStickyPipRestoreUntil = Date().addingTimeInterval(1.2)

        if prefer == false {
            // Explicit clear from page (user dismissed PiP).
            PipProbe.log("native.preferCleared", ["host": webView?.url?.host ?? "?"])
            stickyPipEnterInFlight = false
            persistPipPrefer(false)
            suppressStickyPipRestoreUntil = nil
            return
        }

        if prefer == true {
            // Keep sticky only if this tab already owns the session (or none does yet).
            if PipSession.isOwner(self) || PipSession.owner == nil {
                persistPipPrefer(true)
            } else {
                prefersPictureInPicture = false
                MediaPlaybackSupport.applyStickyPrefer(in: webView, prefer: false)
            }
        }

        // Delay sync — YouTube/WebKit can emit a false leave during foreground resume / next video.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncPictureInPictureActiveFromPage()
        }
        pipLeaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func setPictureInPictureActive(_ active: Bool) {
        isPictureInPictureActive = active
        // Keep WKWebView visible so comments / related content stay usable under the PiP window.
        // PiP survival on foreground relies on MediaPlaybackSupport (presentation-mode / visibility guards).
        webView?.isHidden = false
        updatePipEntryButtonVisibility()
    }

    @objc private func retryTapped() {
        if let url = lastFailedURL { load(url: url) } else { webView?.reload() }
    }

    /// WKWebView KVO often arrives off the main thread — UI / delegate work must hop.
    private func notifyDelegateOnMain(_ work: @escaping (WebViewController) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                work(self)
            }
        }
    }

    deinit { cleanup() }
}

/// Avoids retain cycle: WKUserContentController strongly retains its script message handlers.
private final class WebViewScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: WebViewController?

    init(target: WebViewController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case ImageBlockManager.disableHandlerName:
            target?.handleNoImageScriptMessage(message)
        case PageCleanerManager.handlerName:
            target?.handlePageCleanerMessage(message)
        case AdBlockManager.blockCountHandlerName:
            target?.handleBlockCountMessage(message)
        case YouTubeAdShield.handlerName, YouTubeAdShield.degradedHandlerName:
            target?.handleYouTubeAdShieldMessage(message)
        case MediaPlaybackSupport.pipHandlerName:
            target?.handlePictureInPictureMessage(message)
        default:
            break
        }
    }
}

extension WebViewController: DrawingGestureControllerDelegate {
    func drawingGestureController(_ controller: DrawingGestureController, didRecognize shape: GestureShape, action: GestureBrowserAction) {
        delegate?.webViewController(self, didTriggerGestureAction: action)
    }
}

extension WebViewController: FindInPageBarDelegate {
    func findBar(_ bar: FindInPageBar, didSearch text: String, forward: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mode: String
        if trimmed.isEmpty {
            mode = "clear"
            lastFindQuery = nil
            bar.setCountText("")
        } else if trimmed == lastFindQuery {
            mode = forward ? "next" : "prev"
        } else {
            mode = "highlight"
            lastFindQuery = trimmed
        }

        let js = FindInPageScript.javaScript(query: trimmed, mode: mode)
        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("[FindInPage] \(error.localizedDescription)")
            }
            if let r = result as? String, !r.isEmpty {
                bar.setCountText(r)
            } else if mode == "clear" {
                bar.setCountText("")
            }
        }
    }

    func findBarDidDismiss(_ bar: FindInPageBar) {
        let js = FindInPageScript.javaScript(query: "", mode: "clear")
        webView?.evaluateJavaScript(js, completionHandler: nil)
        lastFindQuery = nil
        bar.removeFromSuperview()
        findBar = nil
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        YouTubeDarkMode.applyAppearance(to: webView, url: navigationAction.request.url)
        if let url = navigationAction.request.url {
            let scheme = (url.scheme ?? "").lowercased()
            // Ignore App/deeplink schemes (common on Chinese portals like Sogou) to avoid "Unsupported URL".
            let allowed = ["http", "https", "about", "blob", "data", "file"]
            if !scheme.isEmpty && !allowed.contains(scheme) {
                decisionHandler(.cancel)
                return
            }

            if let redirected = YouTubeShortsFocus.redirectTarget(for: url), redirected != url {
                decisionHandler(.cancel)
                load(url: redirected)
                return
            }

            let ext = url.pathExtension.lowercased()
            if ["pdf", "zip", "dmg", "pkg"].contains(ext), navigationAction.navigationType == .linkActivated {
                if self.isIncognito {
                    Toast.show("Downloads are disabled in Private Browsing", from: self)
                    decisionHandler(.cancel)
                    return
                }
                DownloadManager.shared.download(from: url, suggestedName: url.lastPathComponent) { [weak self] result in
                    if case .success(let item) = result {
                        if let self = self { Toast.show("Downloaded \(item.fileName)", from: self) }
                    }
                }
                decisionHandler(.cancel)
                return
            }
            if DangerousSiteGuard.isDangerous(url), navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                delegate?.webViewController(self, warnDangerous: url) { [weak webView] in
                    webView?.load(URLRequest(url: url))
                }
                return
            }

            // Optimistic address-bar update for main-frame navigations (links / typed URL / redirects).
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame, ["http", "https"].contains(scheme) {
                notifyDelegateOnMain {
                    $0.delegate?.webViewController($0, didUpdateURL: url)
                }
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        PageCleanerManager.apply(to: webView, url: webView.url)
        notifyDelegateOnMain {
            $0.delegate?.webViewController($0, didUpdateURL: webView.url)
            $0.delegate?.webViewController($0, didUpdateTitle: webView.title)
        }
        // Document JS state is reset on navigation — re-seed sticky PiP only for the owner tab.
        if AppSettings.stickyPictureInPicture, PipSession.isOwner(self) {
            PipProbe.log("nav.commit", [
                "host": webView.url?.host ?? "?",
                "isMusic": YouTubeDarkMode.isYouTubeMusic(webView.url),
                "sticky": true
            ])
            stickyPipEnterInFlight = false
            prefersPictureInPicture = true
            MediaPlaybackSupport.seedStickyPrefer(in: webView)
        } else if AppSettings.stickyPictureInPicture, !PipSession.isOwner(self) {
            prefersPictureInPicture = false
            MediaPlaybackSupport.applyStickyPrefer(in: webView, prefer: false)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorContainer.isHidden = true
        httpsFallbackAttempted = false
        delegate?.webViewController(self, didUpdateProgress: 1, isLoading: false)
        delegate?.webViewController(self, didUpdateTitle: webView.title)
        delegate?.webViewController(self, didUpdateURL: webView.url)
        if !isIncognito, let url = webView.url {
            HistoryStore.shared.add(title: webView.title ?? "", url: url)
        }
        AppLockCoordinator.shared.noteWebpageFinished(url: webView.url)
        if AppSettings.stickyPictureInPicture, PipSession.isOwner(self) {
            PipProbe.log("nav.finish", [
                "host": webView.url?.host ?? "?",
                "isMusic": YouTubeDarkMode.isYouTubeMusic(webView.url),
                "sticky": true
            ])
            restoreStickyPipIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                MediaPlaybackSupport.probePageState(in: self?.webView, reason: "nav.finish+1s")
            }
        }
        // Some sites rewrite viewport after load; re-apply carefully.
        if YouTubeDarkMode.isYouTube(webView.url) {
            refreshPipEntryPolling()
            webView.evaluateJavaScript(Self.youtubeViewportFixScript, completionHandler: nil)
            // Prevent accidental pinch from leaving YouTube zoomed wider than the screen.
            webView.scrollView.minimumZoomScale = 1
            webView.scrollView.maximumZoomScale = 1
            webView.scrollView.zoomScale = 1
            if #available(iOS 14.0, *) { webView.pageZoom = 1.0 }
            var offset = webView.scrollView.contentOffset
            if offset.x != 0 {
                offset.x = 0
                webView.scrollView.contentOffset = offset
            }
        } else {
            webView.scrollView.minimumZoomScale = 1
            webView.scrollView.maximumZoomScale = 5
            webView.evaluateJavaScript(Self.viewportZoomUnlockScript.source, completionHandler: nil)
            // Drop leftover clamp from older builds.
            webView.evaluateJavaScript(
                "(function(){var n=document.getElementById('mm-overflow-clamp');if(n&&n.parentNode)n.parentNode.removeChild(n);})();",
                completionHandler: nil
            )
        }
        PageCleanerManager.apply(to: webView, url: webView.url)
        if isPageCleanerActive {
            PageCleanerManager.setPickMode(enabled: true, on: webView)
        }
        probeSessionAvatar(in: webView)
    }

    private static let sessionAvatarProbeScript = """
    (function() {
      function abs(u) {
        try { return new URL(u, location.href).href; } catch (e) { return null; }
      }
      var selectors = [
        'img[src*="googleusercontent.com/a/"]',
        'img[src*="googleusercontent.com"]',
        'img.avatar',
        'img.Avatar',
        'img[class*="avatar" i]',
        'img[alt*="avatar" i]',
        'img[alt*="profile" i]',
        '[data-testid*="avatar" i] img',
        'header img[src]',
        'nav img[src]'
      ];
      for (var i = 0; i < selectors.length; i++) {
        var nodes;
        try { nodes = document.querySelectorAll(selectors[i]); } catch (e) { continue; }
        for (var j = 0; j < nodes.length; j++) {
          var img = nodes[j];
          var w = img.naturalWidth || img.width || 0;
          var h = img.naturalHeight || img.height || 0;
          if ((w === 0 && h === 0) || (w >= 16 && w <= 256 && h >= 16 && h <= 256)) {
            var src = abs(img.currentSrc || img.src);
            if (src && src.indexOf('data:') !== 0) return src;
          }
        }
      }
      return null;
    })();
    """

    private func probeSessionAvatar(in webView: WKWebView) {
        guard !isIncognito else {
            delegate?.webViewController(self, didDetectSessionAvatar: nil)
            return
        }
        webView.evaluateJavaScript(Self.sessionAvatarProbeScript) { [weak self] result, _ in
            guard let self else { return }
            let url = (result as? String).flatMap(URL.init(string:))
            self.delegate?.webViewController(self, didDetectSessionAvatar: url)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        // App-link / unsupported scheme failures should not blank the page.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorUnsupportedURL {
            return
        }
        if let failing = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            let scheme = (failing.scheme ?? "").lowercased()
            if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
                return
            }
        }

        // HTTPS first fallback to http once
        if !AppSettings.httpsOnly,
           !httpsFallbackAttempted,
           let url = webView?.url ?? lastFailedURL,
           url.scheme == "https",
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            httpsFallbackAttempted = true
            comps.scheme = "http"
            if let httpURL = comps.url {
                webView?.load(URLRequest(url: httpURL))
                return
            }
        }

        lastFailedURL = webView?.url
        errorLabel.text = "Couldn't load page.\n\(error.localizedDescription)"
        errorContainer.isHidden = false
        delegate?.webViewControllerDidFail(self, error: error)
        delegate?.webViewController(self, didUpdateProgress: 0, isLoading: false)
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            delegate?.webViewController(self, requestNewTabFor: url)
        }
        return nil
    }

    @available(iOS 13.0, *)
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        // Plain text / non-link: keep system selection + Copy menu.
        guard let linkURL = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }

        let href = linkURL.absoluteString
        completionHandler(
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self = self else { return nil }

                var actions: [UIMenuElement] = []

                actions.append(UIAction(title: "Open Link", image: UIImage(systemName: "safari")) { [weak self] _ in
                    self?.webView?.load(URLRequest(url: linkURL))
                })

                actions.append(UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                    self?.copyVisibleText(forLinkHREF: href)
                })

                actions.append(UIAction(title: "Select Text", image: UIImage(systemName: "selection.pin.in.out")) { [weak self] _ in
                    self?.selectVisibleText(forLinkHREF: href)
                })

                actions.append(UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { [weak self] _ in
                    UIPasteboard.general.string = href
                    if let self = self {
                        Toast.show("Link copied", from: self)
                    }
                })

                actions.append(UIAction(title: "Share...", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.shareURL(linkURL)
                })

                if !self.isIncognito {
                    actions.append(UIAction(title: "Add to Reading List", image: UIImage(systemName: "eyeglasses")) { [weak self] _ in
                        self?.addLinkToReadingList(linkURL)
                    })
                }

                return UIMenu(title: "", children: actions)
            }
        )
    }

    /// Prefer matching `<a href>`, fall back to nearest text-bearing ancestor.
    private static func linkTextJS(href: String, select: Bool) -> String {
        let escaped = href
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let selectFlag = select ? "true" : "false"
        return """
        (function() {
          var href = '\(escaped)';
          var wantSelect = \(selectFlag);
          function visibleText(el) {
            if (!el) return '';
            var t = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
            if (t) return t;
            var img = el.querySelector && el.querySelector('img[alt]');
            if (img && img.alt) return String(img.alt).trim();
            return '';
          }
          function findAnchor() {
            var nodes = document.querySelectorAll('a[href]');
            for (var i = 0; i < nodes.length; i++) {
              var a = nodes[i];
              try {
                if (a.href === href || a.getAttribute('href') === href) return a;
              } catch (e) {}
            }
            // Absolute vs relative mismatch: compare without hash.
            var target = href.split('#')[0];
            for (var j = 0; j < nodes.length; j++) {
              var b = nodes[j];
              try {
                if ((b.href || '').split('#')[0] === target) return b;
              } catch (e2) {}
            }
            return null;
          }
          var el = findAnchor();
          if (!el) return '';
          if (wantSelect) {
            try {
              var range = document.createRange();
              range.selectNodeContents(el);
              var sel = window.getSelection();
              sel.removeAllRanges();
              sel.addRange(range);
            } catch (err) {}
          }
          return visibleText(el);
        })();
        """
    }

    private func copyVisibleText(forLinkHREF href: String) {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(Self.linkTextJS(href: href, select: false)) { [weak self] result, _ in
            guard let self = self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                Toast.show("No text to copy", from: self)
                return
            }
            UIPasteboard.general.string = text
            Toast.show("Copied", from: self)
        }
    }

    private func selectVisibleText(forLinkHREF href: String) {
        guard let webView = webView else { return }
        webView.evaluateJavaScript(Self.linkTextJS(href: href, select: true)) { [weak self] result, _ in
            guard let self = self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                Toast.show("Nothing to select", from: self)
            } else {
                // Selection handles should now be visible; tip for expanding + Copy.
                Toast.show("Drag handles to adjust, then Copy", from: self)
            }
        }
    }

    private func shareURL(_ url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        present(activity, animated: true)
    }

    private func addLinkToReadingList(_ url: URL) {
        guard !isIncognito else {
            Toast.show("Not available in Private Browsing", from: self)
            return
        }
        let title = url.host ?? "Saved"
        ReadingListStore.shared.add(title: title, url: url, pdfData: nil)
        Toast.show("Saved to Reading List", from: self)
    }
}

