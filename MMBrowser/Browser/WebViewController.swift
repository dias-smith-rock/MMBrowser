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

    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init(isIncognito: Bool) {
        self.isIncognito = isIncognito
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
        if isIncognito { config.websiteDataStore = .nonPersistent() }
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
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.bouncesZoom = true
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.isDirectionalLockEnabled = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 14.0, *) {
            wv.pageZoom = 1.0
        }
        view.insertSubview(wv, at: 0)
        wv.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalToSuperview()
        }
        webView = wv

        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(
                self,
                didUpdateProgress: webView.estimatedProgress,
                isLoading: webView.isLoading && webView.estimatedProgress < 1
            )
        }
        loadingObservation = wv.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(
                self,
                didUpdateProgress: webView.estimatedProgress,
                isLoading: webView.isLoading && webView.estimatedProgress < 1
            )
        }
        titleObservation = wv.observe(\.title, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateTitle: webView.title)
        }
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            YouTubeDarkMode.applyAppearance(to: webView, url: webView.url)
            self.delegate?.webViewController(self, didUpdateURL: webView.url)
        }
        canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateNavigationState: webView.canGoBack, canGoForward: webView.canGoForward)
        }
        canGoForwardObservation = wv.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateNavigationState: webView.canGoBack, canGoForward: webView.canGoForward)
        }
        contentOffsetObservation = wv.scrollView.observe(\.contentOffset, options: [.new, .old]) { [weak self] scrollView, change in
            guard let self = self else { return }
            guard scrollView.isDragging || scrollView.isDecelerating else { return }
            let newY = scrollView.contentOffset.y
            let oldY = change.oldValue?.y ?? newY
            let delta = newY - oldY
            guard abs(delta) > 0.5 else { return }
            self.delegate?.webViewController(self, didScroll: delta, offsetY: newY)
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

        PageCleanerManager.hideSelector(selector, on: webView)

        if isIncognito {
            Toast.show("Hidden for this session", from: self)
            return
        }

        let urlString: String?
        if cleanerURLOnly, let url = webView.url {
            urlString = PageCleanerStore.canonicalURLString(url)
        } else {
            urlString = nil
        }

        if PageCleanerStore.shared.add(host: host, urlString: urlString, selector: selector, label: label) != nil {
            Toast.show(urlString == nil ? "Hidden on this site" : "Hidden on this page", from: self)
        } else {
            Toast.show("Already hidden", from: self)
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
            nav.overrideUserInterfaceStyle = .dark
            BrowserTheme.applyDarkNavigationBar(to: nav.navigationBar)
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
        if let pageCleanerObserver = pageCleanerObserver {
            NotificationCenter.default.removeObserver(pageCleanerObserver)
            self.pageCleanerObserver = nil
        }
        exitPageCleaner()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: ImageBlockManager.disableHandlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: PageCleanerManager.handlerName)
        scriptMessageProxy = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    @objc private func retryTapped() {
        if let url = lastFailedURL { load(url: url) } else { webView?.reload() }
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
        default:
            break
        }
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
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        PageCleanerManager.apply(to: webView, url: webView.url)
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
        // Some sites rewrite viewport after load; re-apply carefully.
        if YouTubeDarkMode.isYouTube(webView.url) {
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
}
