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
    func webViewController(_ controller: WebViewController, didDetectSessionAvatar url: URL?)
    func webViewController(_ controller: WebViewController, suggestComputerUserAgentFor siteName: String)
    func webViewController(_ controller: WebViewController, autoApplyComputerUserAgentFor siteName: String)
    func webViewController(_ controller: WebViewController, didOfferOfflineVideo candidate: PageMediaCandidate)
}

extension WebViewControllerDelegate {
    func webViewController(_ controller: WebViewController, didOfferOfflineVideo candidate: PageMediaCandidate) {}
}

final class WebViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: WebViewControllerDelegate?
    /// Optional Split View / embed hooks (do not replace `delegate`).
    var onNavigationStateChanged: ((Bool, Bool) -> Void)?
    var onURLChanged: ((URL?) -> Void)?
    var onProgressChanged: ((Double, Bool) -> Void)?
    /// Fired when this web view self-promotes to Computer UA (e.g. WhatsApp). Split View uses this to persist tab settings without a full `delegate`.
    var onAutoComputerUserAgent: ((TabUserAgentSettings) -> Void)?

    /// Rewrites viewport meta so pinch-zoom works like Safari on restrictive pages.
    /// Skipped on YouTube / Bilibili: unlocking scale breaks sticky players and list layout.
    private static let viewportZoomUnlockScript = WKUserScript(
        source: """
        (function() {
          var h = (location.hostname || '').toLowerCase();
          if (h === 'youtu.be' || h === 'b23.tv'
              || h.indexOf('youtube.com') !== -1 || h.indexOf('youtube-nocookie.com') !== -1
              || h.indexOf('bilibili.com') !== -1 || h.indexOf('bilibili.tv') !== -1) {
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

    /// X.com (and similar) treat missing `window.safari` as an in-app WebView and navigate to
    /// `x-safari-https://redirect…/?ct=rw-null`. Spoof enough of the Safari object to stay put.
    private static let safariCompatibilityScript = WKUserScript(
        source: """
        (function() {
          try {
            if (window.safari && window.safari.pushNotification) return;
            var perm = function() {
              return { state: 'denied', permission: 'denied' };
            };
            Object.defineProperty(window, 'safari', {
              configurable: true,
              enumerable: false,
              value: {
                pushNotification: {
                  toString: function() { return '[object SafariRemoteNotification]'; },
                  permission: perm
                }
              }
            });
          } catch (e) {}
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    /// Forces YouTube back to a sane mobile viewport if something widened it.
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
      var clamp = document.getElementById('mm-overflow-clamp');
      if (clamp && clamp.parentNode) clamp.parentNode.removeChild(clamp);
    })();
    """

    /// Bilibili `/video/` pages: sticky player covers the in-flow meta block (title / open-app /
    /// UP / tags). Measure with spacer collapsed, set an absolute height (never accumulate),
    /// and keep scrollY stable when the spacer changes.
    private static let bilibiliStickyPlayerPadScript = """
    (function() {
      var h = (location.hostname || '').toLowerCase();
      if (h.indexOf('bilibili.com') === -1 && h.indexOf('bilibili.tv') === -1 && h !== 'b23.tv') {
        return JSON.stringify({skip:1});
      }
      var path = location.pathname || '';
      var spacer = document.getElementById('mm-bili-player-spacer');
      if (path.indexOf('/video/') === -1) {
        if (spacer && spacer.parentNode) spacer.parentNode.removeChild(spacer);
        return JSON.stringify({action:'clear'});
      }
      function isFixedLike(el) {
        while (el && el !== document.documentElement) {
          var st = getComputedStyle(el);
          if (st.position === 'fixed' || st.position === 'sticky') return true;
          el = el.parentElement;
        }
        return false;
      }
      function playerBottom() {
        var max = 0;
        var nodes = document.querySelectorAll('.m-video-player,.fixed-wrapper,.m-navbar');
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          if (!isFixedLike(el)) continue;
          var r = el.getBoundingClientRect();
          if (r.width < window.innerWidth * 0.5) continue;
          if (r.bottom > max) max = r.bottom;
        }
        return Math.round(max);
      }
      // Document Y of first meta/card — independent of current scroll position.
      function firstContentDocTop() {
        var scrollY = window.pageYOffset || document.documentElement.scrollTop || 0;
        var best = null;
        function consider(el) {
          if (!el || el.id === 'mm-bili-player-spacer') return;
          if (isFixedLike(el)) return;
          var r = el.getBoundingClientRect();
          if (r.width < 40 || r.height < 16) return;
          if (r.height > window.innerHeight * 0.75
              && el.querySelector
              && el.querySelector('.m-video-player,.fixed-wrapper,.m-navbar')) return;
          var absTop = Math.round(r.top + scrollY);
          if (best === null || absTop < best) best = absTop;
        }
        var info = document.querySelectorAll(
          'h1,h2,.main-title,.video-title,[class*="video-title"],[class*="main-title"],' +
          '.m-video-info,.video-info,[class*="video-info"],[class*="videoInfo"],' +
          '.m-open-app,.open-app,[class*="open-app"],[class*="openapp"],' +
          '.up-info,[class*="up-info"],[class*="upInfo"],' +
          '[class*="video-desc"],[class*="desc-info"]'
        );
        for (var i = 0; i < info.length; i++) consider(info[i]);
        if (best === null) {
          var cards = document.querySelectorAll('.card-box,.video-card,[class*="recommend"] a');
          for (var j = 0; j < cards.length; j++) consider(cards[j]);
        }
        return best;
      }
      var need = playerBottom();
      if (need < 90) {
        if (spacer && spacer.parentNode) spacer.parentNode.removeChild(spacer);
        return JSON.stringify({action:'clear', need:need});
      }
      var clear = 6;
      var prevH = spacer ? Math.round(parseFloat(spacer.style.height) || spacer.getBoundingClientRect().height) : 0;
      var scrollY = window.pageYOffset || document.documentElement.scrollTop || 0;
      if (!spacer) {
        var root = document.querySelector('#app') || document.body;
        if (!root) return JSON.stringify({action:'no-root'});
        spacer = document.createElement('div');
        spacer.id = 'mm-bili-player-spacer';
        spacer.setAttribute('aria-hidden', 'true');
        root.insertBefore(spacer, root.firstChild);
      }
      // Collapse spacer, measure natural document top, set absolute height (no accumulate).
      spacer.style.cssText = 'display:block;width:100%;height:0;margin:0;padding:0;border:0;pointer-events:none;flex-shrink:0;';
      void spacer.offsetHeight;
      var top = firstContentDocTop();
      var target = 0;
      if (top !== null) {
        target = Math.max(0, (need + clear) - top);
        target = Math.min(target, need + clear);
      }
      if (Math.abs(target - prevH) < 2) {
        spacer.style.height = prevH + 'px';
        return JSON.stringify({action:'stable', need:need, top:top, target:prevH});
      }
      spacer.style.height = Math.round(target) + 'px';
      var delta = Math.round(target) - prevH;
      // Growing/shrinking content above the fold shifts layout; keep the same viewport content.
      if (delta !== 0 && scrollY > 0) {
        try { window.scrollTo(0, Math.max(0, scrollY + delta)); } catch (e) {}
      }
      return JSON.stringify({action: target > 0 ? 'pad' : 'shrink', need:need, top:top, prevH:prevH, target:Math.round(target), delta:delta});
    })();
    """

    /// Hosts whose sticky players / lists break if viewport height or scale thrash.
    static func isViewportFragileHost(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        if host == "youtu.be" || host == "b23.tv" { return true }
        if host.contains("youtube.com") || host.contains("youtube-nocookie.com") { return true }
        if host.contains("bilibili.com") || host.contains("bilibili.tv") || host.contains("bilivideo.com") {
            return true
        }
        return false
    }

    private static func isBilibiliVideoURL(_ url: URL?) -> Bool {
        guard isViewportFragileHost(url), let path = url?.path else { return false }
        return path.contains("/video/")
    }

    private(set) var webView: WKWebView?
    private let isIncognito: Bool
    /// Persistent store for normal tabs; ignored when `isIncognito` (uses non-persistent).
    private let websiteDataStore: WKWebsiteDataStore
    /// Geolocation deny/spoof for this tab (container-specific for normal tabs).
    private let geoConfiguration: GeolocationSpoof.Configuration
    /// Locale / UA / tracking settings for this tab's account.
    private let identityProfile: IdentityProfile
    /// Account container for history and autofill scoping.
    private let browsingContainerID: UUID?
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
    /// Last URL we intentionally started loading — kept when provisional loads fail and `webView.url` is nil.
    private var lastRequestedURL: URL?
    private var pendingURL: URL?
    /// Shared with `BrowserTab` so back/forward survives WKWebView recreation.
    var navigationHistory: TabNavigationHistory?
    private var didSetupWebView = false
    /// YouTube Dark / Shorts / AdShield / YT viewport — installed before first YT document load.
    private var didInstallYouTubeScripts = false
    /// Large media/PiP bridge — installed before first likely-media document load (or PiP intent).
    private var didInstallMediaScript = false
    private var didInstallPageMediaScript = false
    private let pageMediaProbe = PageMediaProbe()

    /// Offline-save candidate for the page menu (progressive MP4 or HLS; nil when unavailable / Private).
    var offlineVideoCandidate: PageMediaCandidate? {
        guard !isIncognito else { return nil }
        if OfflineMediaCopyrightPolicy.restrictsAudioVideo(on: webView?.url) { return nil }
        guard let candidate = pageMediaProbe.bestCandidate else { return nil }
        if pageMediaProbe.isAlreadySavedOrDownloading(candidate) { return nil }
        return candidate
    }

    /// Stream candidate for custom PiP (allows hosts blocked for offline save when a URL was discovered).
    var pipStreamCandidate: PageMediaCandidate? {
        pageMediaProbe.bestCandidate
    }
    private var httpsFallbackAttempted = false
    private var tabUserAgentSettings = TabUserAgentSettings(userAgentMode: .automatic, customUserAgent: nil)

    /// Current per-tab look settings (Automatic / Mobile / Computer / Custom).
    var currentUserAgentSettings: TabUserAgentSettings { tabUserAgentSettings }

    private var desktopUAHintGeneration = 0
    private var findBar: FindInPageBar?
    private var lastFindQuery: String?
    private(set) var isPageCleanerActive = false
    private var cleanerURLOnly = false
    var onPageCleanerActiveChanged: ((Bool) -> Void)?
    /// Rules changed while this tab was not visible — re-apply on next appear / finish.
    private var pageCleanerNeedsReapply = false
    private var scriptMessageProxy: WebViewScriptProxy?
    private var pageCleanerObserver: NSObjectProtocol?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    /// Drives chrome collapse when the page scrolls inside a nested scroller (X / shorts).
    private var chromeNestScrollPan: UIPanGestureRecognizer?
    private var chromeNestPanLastTranslationY: CGFloat = 0
    private var chromeNestPanBaseOffsetY: CGFloat = 0
    private var stickyPlayerRepairWorkItem: DispatchWorkItem?
    /// Last video URL we finished sticky-player padding for — avoids re-running on infinite scroll.
    private var stickyPlayerRepairedURL: String?
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
    private(set) var pageHasPlayingVideo = false
    /// Last time media was reported playing (for selective background keep-alive).
    private(set) var lastMediaPlayingAt: Date?
    /// Chip flicker diagnostics — last visibility + rapid flip counter.
    private var pipChipLastShown: Bool?
    private var pipChipLastToggleAt: Date?
    private var pipChipFlickerCount = 0
    private var pipChipLastPollState: String?
    /// Delay chip hide so brief pause / multi-video JS noise does not flicker.
    private var pipChipHideWorkItem: DispatchWorkItem?
    /// Prevents stacked auto-enter retries while sticky PiP waits for a video element.
    private var stickyPipEnterInFlight = false
    /// Bumps to cancel an in-flight sticky enter retry chain (video change / leave).
    private var stickyPipEnterGeneration = 0
    /// After a PiP leave, suppress sticky auto-restore briefly so a manual close can clear prefer.
    private var suppressStickyPipRestoreUntil: Date?
    /// After yielding to another tab, ignore stale active:true while system PiP tears down.
    private var suppressPipClaimUntil: Date?
    /// Last free-drag origin for the PiP button (session + UserDefaults).
    private var pipEntryButtonOrigin: CGPoint?
    private static let pipEntryOriginXKey = "media.pip.button.originX"
    private static let pipEntryOriginYKey = "media.pip.button.originY"
    /// Active `window.open` OAuth / GSI popup (must keep opener alive).
    private var authPopup: AuthPopupViewController?

    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init(
        isIncognito: Bool,
        websiteDataStore: WKWebsiteDataStore = .default(),
        geoConfiguration: GeolocationSpoof.Configuration = .fromAppSettings(),
        identityProfile: IdentityProfile = .default,
        tabUserAgentSettings: TabUserAgentSettings = TabUserAgentSettings(userAgentMode: .automatic, customUserAgent: nil),
        containerID: UUID? = nil
    ) {
        self.isIncognito = isIncognito
        self.websiteDataStore = websiteDataStore
        self.geoConfiguration = geoConfiguration
        self.identityProfile = identityProfile
        self.tabUserAgentSettings = tabUserAgentSettings
        self.browsingContainerID = containerID
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyPageCleanerIfNeeded()
    }

    private func setupWebView() {
        guard !didSetupWebView else { return }
        didSetupWebView = true
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isIncognito ? .nonPersistent() : websiteDataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        MediaPlaybackSupport.apply(to: config)
        AdBlockManager.shared.apply(to: config) { [weak self] in
            guard let self = self else { return }
            ImageBlockManager.shared.apply(to: config) {
                self.finishWebViewSetup(with: config)
            }
        }
    }

    private func finishWebViewSetup(with config: WKWebViewConfiguration) {
        // YouTube / media document-start scripts are installed on demand in
        // `ensureOnDemandScripts` so generic pages skip that cost.
        if let geoScript = GeolocationSpoof.userScript(configuration: geoConfiguration) {
            config.userContentController.addUserScript(geoScript)
        }
        if let localeScript = IdentitySpoof.userScript(localeIdentifier: identityProfile.localeIdentifier) {
            config.userContentController.addUserScript(localeScript)
        }
        if tabUserAgentSettings.userAgentMode == .custom,
           let profile = tabUserAgentSettings.customProfile {
            config.userContentController.addUserScript(IdentitySpoof.clientHintsUserScript(for: profile))
        }
        // Unlock pinch-zoom on pages that set user-scalable=no / maximum-scale=1
        // (UIScrollView.ignoresViewportScaleLimits is unavailable in this SDK).
        // YouTube / Bilibili are excluded inside the script — unlocking breaks sticky players.
        config.userContentController.addUserScript(Self.viewportZoomUnlockScript)
        // Generic video/overlay/popunder ad reduction (site-agnostic).
        if AppSettings.trackerProtectionEnabled {
            config.userContentController.addUserScript(VideoAdShield.userScript)
        }
        let proxy = WebViewScriptProxy(target: self)
        scriptMessageProxy = proxy
        config.userContentController.add(proxy, name: PageCleanerManager.handlerName)
        if AppSettings.trackerProtectionEnabled, AppSettings.accurateBlockCountEnabled {
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
        // X.com (and similar) treat missing `window.safari` as an in-app WebView and navigate to
        // `x-safari-https://redirect…/?ct=rw-null`. Spoof enough of the Safari object to stay put.
        // Must run before XSiteProbe so boot logs see hasSafari=true.
        config.userContentController.addUserScript(Self.safariCompatibilityScript)
        if XSiteProbe.isEnabled {
            config.userContentController.add(proxy, name: XSiteProbe.handlerName)
            config.userContentController.addUserScript(XSiteProbe.userScript)
        }
        if !isIncognito {
            config.userContentController.add(proxy, name: PageMediaProbe.handlerName)
            config.userContentController.addUserScript(BrowserAutofillCoordinator.userScript)
        }
        // Default WKWebView UA omits "Safari/…" which makes x.com issue x-safari-https:// kickouts.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
    // Full-page navigation uses hooked drawing strokes instead of edge swipes.
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.bounces = true
        wv.scrollView.bouncesZoom = true
        wv.scrollView.alwaysBounceVertical = true
        wv.scrollView.alwaysBounceHorizontal = false
        wv.scrollView.isDirectionalLockEnabled = false
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
        applyUserAgent(to: wv)
        if !isIncognito {
            autofillCoordinator.hostViewController = self
            autofillCoordinator.attach(
                to: wv,
                isIncognito: isIncognito,
                containerID: browsingContainerID,
                contentController: config.userContentController
            )
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

        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            let progress = webView.estimatedProgress
            let loading = webView.isLoading && webView.estimatedProgress < 1
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateProgress: progress, isLoading: loading)
                $0.onProgressChanged?(progress, loading)
            }
        }
        loadingObservation = wv.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
            let progress = webView.estimatedProgress
            let loading = webView.isLoading && webView.estimatedProgress < 1
            self?.notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateProgress: progress, isLoading: loading)
                $0.onProgressChanged?(progress, loading)
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
                // Provisional failures often clear `webView.url` — keep the failed address visible.
                if url == nil, let failed = $0.lastFailedURL, !$0.errorContainer.isHidden {
                    return
                }
                YouTubeDarkMode.applyAppearance(to: webView, url: url)
                $0.delegate?.webViewController($0, didUpdateURL: url)
                $0.onURLChanged?(url)
                $0.recordNavigationHistory(from: url)
                $0.refreshPipEntryPolling()
                // Bilibili SPA (search → video) often skips didFinish.
                $0.scheduleBilibiliStickyPlayerRepair()
            }
        }
        canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            self?.notifyDelegateOnMain { $0.publishNavigationState() }
        }
        canGoForwardObservation = wv.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
            self?.notifyDelegateOnMain { $0.publishNavigationState() }
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
        installChromeNestScrollPan(on: wv)
        contentSizeObservation = wv.scrollView.observe(\.contentSize, options: [.new, .old]) { [weak self] scrollView, change in
            guard let self else { return }
            let old = change.oldValue ?? .zero
            let new = scrollView.contentSize
            guard abs(new.height - old.height) > 8 else { return }
            // Infinite-scroll appends must not re-pad (that jumped scroll to the top and
            // grew a blank gap). Only repair until this video URL has settled once.
            let urlKey = self.webView?.url?.absoluteString
            guard Self.isBilibiliVideoURL(self.webView?.url),
                  urlKey != self.stickyPlayerRepairedURL else { return }
            self.scheduleBilibiliStickyPlayerRepair()
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
            guard let self = self else { return }
            self.pageCleanerNeedsReapply = true
            // Only refresh the visible tab immediately; others wait until shown.
            guard self.view.window != nil else { return }
            self.applyPageCleanerIfNeeded(force: true)
        }
    }

    /// Apply stored cleaner CSS when dirty or forced (visible tab / navigation finish).
    func applyPageCleanerIfNeeded(force: Bool = false) {
        guard let webView else { return }
        guard force || pageCleanerNeedsReapply else { return }
        pageCleanerNeedsReapply = false
        PageCleanerManager.apply(to: webView, url: webView.url)
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
        lastRequestedURL = url
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
        lastRequestedURL = url
        ensureOnDemandScripts(for: url)
        if XSiteProbe.isRelevant(url) || (url.scheme ?? "").lowercased().hasPrefix("x-safari-") {
            XSiteProbe.log("load.start", [
                "url": url.absoluteString,
                "ct": Self.xConsentToken(from: url) ?? "nil",
                "adblock": AppSettings.trackerProtectionEnabled
            ])
        }
        YouTubeDarkMode.applyAppearance(to: webView, url: url)
        // WhatsApp (and similar) must use Computer UA on the first request — post-load
        // hints need a delegate and often run too late after /mobile/ already rendered.
        let promoted = promoteAutoComputerUAIfNeeded(for: url)
        applyUserAgent(to: webView)
        // Fire-and-forget cookie warm-up — do not delay navigation on cookie store I/O.
        if YouTubeDarkMode.isYouTube(url) {
            YouTubeDarkMode.ensureDarkCookie(in: webView.configuration.websiteDataStore) {}
        }
        webView.load(URLRequest(url: url))
        if promoted, let site = DesktopUAHint.site(matching: url) {
            notifyAutoComputerUAApplied(siteName: site.displayName)
        }
    }

    /// Promotes this web view to Computer UA for hosts marked `autoApplyComputerUserAgent`
    /// (currently WhatsApp). Returns true when settings changed.
    @discardableResult
    private func promoteAutoComputerUAIfNeeded(for url: URL?) -> Bool {
        guard let url, let site = DesktopUAHint.site(matching: url), site.autoApplyComputerUserAgent else {
            return false
        }
        guard !tabUserAgentSettings.looksLikeComputer else { return false }
        tabUserAgentSettings = TabUserAgentSettings(userAgentMode: .desktop, customUserAgent: nil)
        return true
    }

    private func notifyAutoComputerUAApplied(siteName: String) {
        // Persist on the owning tab when a browser delegate is present (Split View may be nil).
        delegate?.webViewController(self, autoApplyComputerUserAgentFor: siteName)
        onAutoComputerUserAgent?(tabUserAgentSettings)
    }

    /// Install heavy host-specific user scripts before the document loads (document-start).
    /// Media / YouTube payloads stay off generic sites unless this tab already has PiP intent.
    private func ensureOnDemandScripts(for url: URL?) {
        guard let webView else { return }
        let ucc = webView.configuration.userContentController
        let mediaFeaturesOn = AppSettings.pictureInPictureEnabled || AppSettings.backgroundAudioEnabled
        if mediaFeaturesOn, !didInstallMediaScript {
            let onMediaHost = MediaPlaybackSupport.shouldInstallScript(for: url)
            let pipIntent = prefersPictureInPicture || isPictureInPictureActive
            if onMediaHost || pipIntent {
                didInstallMediaScript = true
                ucc.addUserScript(MediaPlaybackSupport.mediaUserScript)
            }
        }
        if !isIncognito, !didInstallPageMediaScript, PageMediaProbe.isEligiblePage(url) {
            didInstallPageMediaScript = true
            ucc.addUserScript(PageMediaProbe.userScript)
            // If the document is already loaded, user scripts alone won't run until next navigation.
            webView.evaluateJavaScript(PageMediaProbe.scriptSourceForEvaluation, completionHandler: nil)
        }
        guard YouTubeDarkMode.isYouTube(url), !didInstallYouTubeScripts else { return }
        didInstallYouTubeScripts = true
        ucc.addUserScript(YouTubeDarkMode.userScript)
        ucc.addUserScript(
            WKUserScript(
                source: Self.youtubeViewportFixScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        if YouTubeShortsFocus.isEnabled {
            ucc.addUserScript(YouTubeShortsFocus.userScript)
        }
        if YouTubeAdShield.isEffectivelyEnabled {
            ucc.addUserScript(YouTubeAdShield.userScript)
        }
    }

    /// Install media bridge when the user explicitly starts PiP on a non-listed host (then reload).
    private func ensureMediaScriptForPictureInPicture() {
        guard AppSettings.pictureInPictureEnabled || AppSettings.backgroundAudioEnabled else { return }
        guard !didInstallMediaScript, let webView else { return }
        didInstallMediaScript = true
        webView.configuration.userContentController.addUserScript(MediaPlaybackSupport.mediaUserScript)
    }

    func goBack() {
        if webView?.canGoBack == true {
            // Keep persisted stack aligned with the native list when possible.
            if navigationHistory?.canGoBack == true {
                _ = navigationHistory?.goBack()
            } else {
                navigationHistory?.suppressNextRecord = true
            }
            webView?.goBack()
            publishNavigationState()
            return
        }
        if let url = navigationHistory?.goBack() {
            load(url: url)
            publishNavigationState()
        }
    }

    func goForward() {
        if webView?.canGoForward == true {
            if navigationHistory?.canGoForward == true {
                _ = navigationHistory?.goForward()
            } else {
                navigationHistory?.suppressNextRecord = true
            }
            webView?.goForward()
            publishNavigationState()
            return
        }
        if let url = navigationHistory?.goForward() {
            load(url: url)
            publishNavigationState()
        }
    }

    var canGoBack: Bool {
        (webView?.canGoBack == true) || (navigationHistory?.canGoBack == true)
    }

    var canGoForward: Bool {
        (webView?.canGoForward == true) || (navigationHistory?.canGoForward == true)
    }

    /// Short-video / SPA pages often scroll inside nested overflow containers, so WKWebView's
    /// root `contentOffset` never moves. Mirror vertical pans into chrome collapse intents.
    private func installChromeNestScrollPan(on webView: WKWebView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleChromeNestScrollPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        webView.addGestureRecognizer(pan)
        chromeNestScrollPan = pan
    }

    @objc private func handleChromeNestScrollPan(_ pan: UIPanGestureRecognizer) {
        guard let scrollView = webView?.scrollView else { return }
        switch pan.state {
        case .began:
            chromeNestPanLastTranslationY = 0
            chromeNestPanBaseOffsetY = scrollView.contentOffset.y
        case .changed:
            let translationY = pan.translation(in: webView).y
            let fingerDelta = translationY - chromeNestPanLastTranslationY
            chromeNestPanLastTranslationY = translationY
            // Root scroller is already driving chrome via KVO — avoid double-counting.
            if abs(scrollView.contentOffset.y - chromeNestPanBaseOffsetY) > 2 {
                chromeNestPanBaseOffsetY = scrollView.contentOffset.y
                return
            }
            // Finger moving up (negative) ⇒ content moving up ⇒ positive content delta.
            let contentDelta = -fingerDelta
            guard abs(contentDelta) > 0.5 else { return }
            // Keep offset above the "near top" expand threshold so nested swipes can collapse.
            let reportedOffset = max(scrollView.contentOffset.y, 21)
            notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didScroll: contentDelta, offsetY: reportedOffset)
            }
        default:
            chromeNestPanLastTranslationY = 0
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === chromeNestScrollPan
    }

    private func publishNavigationState() {
        let back = canGoBack
        let forward = canGoForward
        delegate?.webViewController(
            self,
            didUpdateNavigationState: back,
            canGoForward: forward
        )
        onNavigationStateChanged?(back, forward)
    }

    private func recordNavigationHistory(from url: URL?) {
        guard let url else { return }
        navigationHistory?.record(url)
        publishNavigationState()
    }
    func reload() {
        if let url = lastFailedURL ?? lastRequestedURL,
           webView?.url == nil || !errorContainer.isHidden {
            load(url: url)
            return
        }
        if let url = lastRequestedURL, webView?.url == nil {
            load(url: url)
            return
        }
        webView?.reload()
    }

    func applyTabUserAgentSettings(_ settings: TabUserAgentSettings, reload: Bool = true) {
        tabUserAgentSettings = settings
        guard let webView = webView else { return }
        applyUserAgent(to: webView)
        if settings.userAgentMode == .custom, let profile = settings.customProfile {
            webView.configuration.userContentController.addUserScript(
                IdentitySpoof.clientHintsUserScript(for: profile)
            )
        }
        if reload {
            webView.reload()
        }
    }

    private func applyUserAgent(to webView: WKWebView) {
        webView.customUserAgent = IdentitySpoof.resolvedUserAgent(for: tabUserAgentSettings)
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
        let containerID = browsingContainerID ?? ContainerScope.resolveContainerID(nil)
        if #available(iOS 14.0, *) {
            let config = WKPDFConfiguration()
            webView.createPDF(configuration: config) { [weak self] result in
                guard let self else { return }
                let data = try? result.get()
                ReadingListStore.shared.add(title: title, url: url, pdfData: data, containerID: containerID)
                Toast.show("Saved to Reading List", from: self)
            }
        } else {
            ReadingListStore.shared.add(title: title, url: url, pdfData: nil, containerID: containerID)
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
                    PlatformSupport.configurePopover(activity, sourceView: self.view)
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
            PlatformSupport.configurePopover(activity, sourceView: self.view)
            self.delegate?.webViewController(self, present: activity)
        }
    }

    func downloadCurrentIfFile() {
        guard let url = webView?.url else {
            Toast.show("No page to download", from: self)
            return
        }
        guard DownloadManager.isLikelyDownloadURL(url) else {
            Toast.show("Open a downloadable file URL first", from: self)
            return
        }
        beginDownload(url: url, suggestedName: url.lastPathComponent)
    }

    /// Starts a cookie-aware download and shows a brief status toast.
    func beginDownload(url: URL, suggestedName: String? = nil, mimeType: String? = nil) {
        guard !isIncognito else {
            Toast.show("Downloads are disabled in Private Browsing", from: self)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else {
            Toast.show("Can't download this link", from: self)
            return
        }
        DownloadManager.shared.start(
            url: url,
            suggestedName: suggestedName,
            mimeType: mimeType,
            from: webView
        ) { [weak self] item in
            guard let self else { return }
            Toast.show("Downloading \(item.fileName)…", from: self)
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
        contentSizeObservation = nil
        if let chromeNestScrollPan {
            webView?.removeGestureRecognizer(chromeNestScrollPan)
        }
        chromeNestScrollPan = nil
        stickyPlayerRepairWorkItem?.cancel()
        stickyPlayerRepairWorkItem = nil
        if let pageCleanerObserver = pageCleanerObserver {
            NotificationCenter.default.removeObserver(pageCleanerObserver)
            self.pageCleanerObserver = nil
        }
        exitPageCleaner()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: ImageBlockManager.disableHandlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: PageCleanerManager.handlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: BrowserAutofillCoordinator.messageName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: MediaPlaybackSupport.pipHandlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: XSiteProbe.handlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: AdBlockManager.blockCountHandlerName)
        if let pipForegroundObserver {
            NotificationCenter.default.removeObserver(pipForegroundObserver)
            self.pipForegroundObserver = nil
        }
        scriptMessageProxy = nil
        pipLeaveWorkItem?.cancel()
        pipLeaveWorkItem = nil
        pipChipHideWorkItem?.cancel()
        pipChipHideWorkItem = nil
        pipVideoPollTimer?.invalidate()
        pipVideoPollTimer = nil
        PipSession.releaseIfOwner(self)
        prefersPictureInPicture = false
        setPictureInPictureActive(false)
        authPopup?.dismissPopup()
        authPopup = nil
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
        updatePipEntryButtonVisibility(reason: "refreshPolling")
        guard AppSettings.pictureInPictureEnabled,
              !YouTubeDarkMode.isYouTubeMusic(webView?.url)
        else { return }

        let isForegroundTab = view.window != nil
        let isPipOwner = isPictureInPictureActive || PipSession.isOwner(self)
        // Background live tabs: no native poll (page script still runs at reduced rate).
        guard isForegroundTab || isPipOwner else {
            pollPlayableVideoForPiP()
            return
        }

        pollPlayableVideoForPiP()
        let interval: TimeInterval = isPipOwner && !isForegroundTab ? 2.0 : 0.8
        pipVideoPollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollPlayableVideoForPiP()
        }
    }

    /// Whether this tab should receive background media keep-alive.
    var needsBackgroundMediaKeepAlive: Bool {
        if isPictureInPictureActive || PipSession.isOwner(self) { return true }
        guard AppSettings.backgroundAudioEnabled else { return false }
        if pageHasPlayingVideo { return true }
        if let last = lastMediaPlayingAt, Date().timeIntervalSince(last) < 4 { return true }
        return false
    }

    /// Tabs UI speaker badge: PiP or an actively playing `<video>` / `<audio>`.
    var indicatesPlayingMedia: Bool {
        if isPictureInPictureActive || PipSession.isOwner(self) { return true }
        return pageHasPlayingVideo
    }

    /// Refresh `pageHasPlayingVideo` for the tab-switcher speaker badge (includes `<audio>`).
    func refreshPlayingMediaState(completion: ((Bool) -> Void)? = nil) {
        if isPictureInPictureActive || PipSession.isOwner(self) {
            pageHasPlayingVideo = true
            lastMediaPlayingAt = Date()
            completion?(true)
            return
        }
        guard let webView else {
            pageHasPlayingVideo = false
            completion?(false)
            return
        }
        let js = """
        (function(){
          try {
            if (typeof window.__mmAnyInPiP === 'function' && window.__mmAnyInPiP()) return true;
            if (window.__mmTabInactive === true) return false;
            var els = document.querySelectorAll('video,audio');
            for (var i = 0; i < els.length; i++) {
              var m = els[i];
              if (m.paused || m.ended) continue;
              if ((m.currentTime || 0) > 0.05) return true;
              if (m.dataset && m.dataset.mmWantPlay === '1') return true;
            }
          } catch (e) {}
          return false;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            let playing = (result as? Bool) ?? false
            DispatchQueue.main.async {
                guard let self else {
                    completion?(playing)
                    return
                }
                self.pageHasPlayingVideo = playing
                if playing { self.lastMediaPlayingAt = Date() }
                completion?(playing)
            }
        }
    }

    private func pollPlayableVideoForPiP() {
        guard AppSettings.pictureInPictureEnabled,
              !YouTubeDarkMode.isYouTubeMusic(webView?.url) else {
            pageHasPlayingVideo = false
            updatePipEntryButtonVisibility(reason: "poll.disabled")
            return
        }
        let js = """
        (function(){
          try {
            if (typeof window.__mmPipChipState === 'function') return window.__mmPipChipState();
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
            function inView(v) {
              try {
                if (v.webkitPresentationMode === 'picture-in-picture') return true;
                if (document.pictureInPictureElement === v) return true;
                var r = v.getBoundingClientRect();
                var vw = window.innerWidth || 0, vh = window.innerHeight || 0;
                if (r.width < 16 || r.height < 16 || vw < 1 || vh < 1) return false;
                var left = Math.max(r.left, 0), top = Math.max(r.top, 0);
                var right = Math.min(r.right, vw), bottom = Math.min(r.bottom, vh);
                var iw = right - left, ih = bottom - top;
                if (iw < 16 || ih < 16) return false;
                var area = r.width * r.height, visible = iw * ih;
                return visible / area >= 0.2 || visible >= 96 * 96;
              } catch (e) { return false; }
            }
            var vids = walk(document, []);
            if (!vids.length) return { state: 'none', count: 0, visible: 0, paused: 0, ready: -1, t: -1 };
            var paused = 0, visible = 0, bestReady = -1, bestT = -1;
            for (var i = 0; i < vids.length; i++) {
              var v = vids[i];
              if (v.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === v) {
                return { state: 'pip', count: vids.length, visible: visible + 1, paused: paused, ready: v.readyState|0, t: v.currentTime||0 };
              }
              if (!inView(v)) continue;
              visible++;
              bestReady = Math.max(bestReady, v.readyState|0);
              if (typeof v.currentTime === 'number') bestT = Math.max(bestT, v.currentTime);
              if (!v.paused && !v.ended) {
                return { state: 'playing', count: vids.length, visible: visible, paused: paused, ready: v.readyState|0, t: v.currentTime||0 };
              }
              if (v.paused) paused++;
            }
            return { state: visible ? 'idle' : 'none', count: vids.length, visible: visible, paused: paused, ready: bestReady, t: bestT };
          } catch (e) { return { state: 'none', count: 0, visible: 0, paused: 0, ready: -1, t: -1, err: String(e) }; }
        })();
        """
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let dict = result as? [String: Any]
                let state = (dict?["state"] as? String) ?? (result as? String) ?? "none"
                let inPip = state == "pip"
                let playing = state == "playing" || inPip
                let prevPlaying = self.pageHasPlayingVideo
                let prevState = self.pipChipLastPollState
                self.pageHasPlayingVideo = playing
                if playing { self.lastMediaPlayingAt = Date() }
                if state != prevState || playing != prevPlaying {
                    PipProbe.log("chip.poll", [
                        "state": state,
                        "prev": prevState ?? "nil",
                        "playing": playing,
                        "prevPlaying": prevPlaying,
                        "nativeActive": self.isPictureInPictureActive,
                        "chipShown": !(self.pipEntryButton.isHidden),
                        "count": dict?["count"] ?? -1,
                        "visible": dict?["visible"] ?? -1,
                        "paused": dict?["paused"] ?? -1,
                        "ready": dict?["ready"] ?? -1,
                        "t": dict?["t"] ?? -1,
                        "host": self.webView?.url?.host ?? "?"
                    ])
                }
                self.pipChipLastPollState = state
                if inPip {
                    if let until = self.suppressPipClaimUntil, Date() < until {
                        MediaPlaybackSupport.releasePictureInPicture(in: self.webView)
                        self.setPictureInPictureActive(false, reason: "poll.suppressYield")
                        return
                    }
                    self.stickyPipEnterInFlight = false
                    self.persistPipPrefer(true)
                    self.setPictureInPictureActive(true, reason: "poll.inPip")
                } else if self.isPictureInPictureActive {
                    // Avoid a stuck "active" flag after a false leave.
                    // Do not auto-restore sticky here — that re-opened PiP after a manual close.
                    self.syncPictureInPictureActiveFromPage()
                } else {
                    self.updatePipEntryButtonVisibility(reason: "poll.\(state)")
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
        stickyPipEnterGeneration += 1
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
        ensureOnDemandScripts(for: webView?.url)
        if !didInstallMediaScript {
            ensureMediaScriptForPictureInPicture()
        }
        MediaPlaybackSupport.applyStickyPrefer(in: webView, prefer: true)
        guard !stickyPipEnterInFlight else {
            PipProbe.log("sticky.restore.skip", ["why": "inFlight"])
            return
        }
        stickyPipEnterGeneration += 1
        stickyPipEnterInFlight = true
        attemptStickyPipEnter(retriesLeft: 4, delay: 0.35)
    }

    private func cancelStickyPipEnterAttempts() {
        stickyPipEnterGeneration += 1
        stickyPipEnterInFlight = false
    }

    private func attemptStickyPipEnter(retriesLeft: Int, delay: TimeInterval) {
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
        let generation = stickyPipEnterGeneration
        PipProbe.log("sticky.attempt", [
            "left": retriesLeft,
            "host": webView?.url?.host ?? "?",
            "isMusic": YouTubeDarkMode.isYouTubeMusic(webView?.url)
        ])
        MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: webView)
        MediaPlaybackSupport.enterPictureInPicture(in: webView) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.stickyPipEnterGeneration == generation else { return }
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
                    "delay": delay,
                    "host": self.webView?.url?.host ?? "?"
                ])
                let nextDelay = min(delay * 1.7, 2.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.stickyPipEnterGeneration == generation else { return }
                    self.attemptStickyPipEnter(retriesLeft: retriesLeft - 1, delay: nextDelay)
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

    private func updatePipEntryButtonVisibility(reason: String = "unknown") {
        // Floating PiP chip stays off. System PiP still starts from the page menu.
        let wantShow = false

        if wantShow {
            pipChipHideWorkItem?.cancel()
            pipChipHideWorkItem = nil
            applyPipChipVisibility(show: true, reason: reason)
            return
        }

        // Hide path: debounce. CNN / multi-<video> pages spam pause → JS videoPlaying=false
        // while another clip (or the same clip after a buffer blip) is still playing.
        if pipEntryButton.isHidden {
            pipChipHideWorkItem?.cancel()
            pipChipHideWorkItem = nil
            return
        }
        if pipChipHideWorkItem != nil {
            PipProbe.log("chip.hide.pending", [
                "reason": reason,
                "playing": pageHasPlayingVideo,
                "host": webView?.url?.host ?? "?"
            ])
            return
        }
        PipProbe.log("chip.hide.schedule", [
            "reason": reason,
            "playing": pageHasPlayingVideo,
            "poll": pipChipLastPollState ?? "nil",
            "host": webView?.url?.host ?? "?"
        ])
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pipChipHideWorkItem = nil
            let stillWantShow = false
            if stillWantShow {
                PipProbe.log("chip.hide.cancelled", [
                    "why": "playingAgain",
                    "host": self.webView?.url?.host ?? "?"
                ])
                self.applyPipChipVisibility(show: true, reason: "hide.cancelled")
                return
            }
            self.applyPipChipVisibility(show: false, reason: "\(reason).debounced")
        }
        pipChipHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: work)
    }

    private func applyPipChipVisibility(show: Bool, reason: String) {
        let wasHidden = pipEntryButton.isHidden
        let previousShown = pipChipLastShown
        if show != previousShown {
            let now = Date()
            var flicker = false
            var dtMs = -1
            if let last = pipChipLastToggleAt {
                dtMs = Int(now.timeIntervalSince(last) * 1000)
                if dtMs < 1500 {
                    pipChipFlickerCount += 1
                    flicker = true
                }
            }
            pipChipLastToggleAt = now
            pipChipLastShown = show
            PipProbe.log(flicker ? "chip.flicker" : "chip.visibility", [
                "show": show,
                "wasHidden": wasHidden,
                "reason": reason,
                "playing": pageHasPlayingVideo,
                "nativeActive": isPictureInPictureActive,
                "webHidden": webView?.isHidden ?? false,
                "ytMusic": YouTubeDarkMode.isYouTubeMusic(webView?.url),
                "pipEnabled": AppSettings.pictureInPictureEnabled,
                "poll": pipChipLastPollState ?? "nil",
                "flickerN": pipChipFlickerCount,
                "dtMs": dtMs,
                "host": webView?.url?.host ?? "?"
            ])
        }
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
        if pipStreamCandidate != nil,
           let hostView = parent?.view ?? view.window {
            let started = CustomPipController.shared.startFromUserAction(
                web: self,
                hostView: hostView
            ) { [weak self] usedCustom in
                guard let self, !usedCustom else { return }
                self.enterPictureInPictureFromUserAction(showFailureToast: false, completion: nil)
            }
            if started { return }
        }
        enterPictureInPictureFromUserAction(showFailureToast: false, completion: nil)
    }

    /// Menu / floating chip entry — ensures the JS bridge is live, then requests system PiP.
    func enterPictureInPictureFromUserAction(
        showFailureToast: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        let host = webView?.url?.host ?? "?"
        PipProbe.log("enter.userAction.begin", [
            "host": host,
            "url": webView?.url?.absoluteString ?? "",
            "settingOn": AppSettings.pictureInPictureEnabled,
            "didInstallMediaScript": didInstallMediaScript,
            "prefer": prefersPictureInPicture,
            "nativeActive": isPictureInPictureActive,
            "pageHasPlayingVideo": pageHasPlayingVideo,
            "fromMenu": showFailureToast
        ])
        // Explicit user intent — allow PiP again after a prior yield suppress window.
        suppressPipClaimUntil = nil
        let pipSource = showFailureToast ? "menu" : "chip"
        AppAnalytics.logPipEnter(source: pipSource, host: AppAnalytics.privacyHost(webView?.url))
        guard !YouTubeDarkMode.isYouTubeMusic(webView?.url) else {
            PipProbe.log("enter.userAction.skip", ["why": "youtubeMusic", "host": host])
            AppAnalytics.logPipResult(source: pipSource, success: false, host: AppAnalytics.privacyHost(webView?.url), reason: "youtube_music")
            completion?(false)
            return
        }
        guard AppSettings.pictureInPictureEnabled else {
            PipProbe.log("enter.userAction.skip", ["why": "settingOff", "host": host])
            AppAnalytics.logPipResult(source: pipSource, success: false, host: AppAnalytics.privacyHost(webView?.url), reason: "setting_off")
            completion?(false)
            return
        }
        ensureMediaScriptForPictureInPicture()
        PipProbe.log("enter.userAction.afterEnsureScript", [
            "host": host,
            "didInstallMediaScript": didInstallMediaScript
        ])
        persistPipPrefer(true)
        MediaPlaybackSupport.applyStickyPrefer(in: webView, prefer: true)
        MediaPlaybackSupport.enterPictureInPicture(in: webView, detailedCompletion: { [weak self] ok, detail in
            DispatchQueue.main.async {
                guard let self else {
                    completion?(false)
                    return
                }
                PipProbe.log("enter.userAction.done", [
                    "host": host,
                    "ok": ok,
                    "detail": detail,
                    "nativeActive": self.isPictureInPictureActive
                ])
                AppAnalytics.logPipResult(
                    source: pipSource,
                    success: ok,
                    host: AppAnalytics.privacyHost(self.webView?.url),
                    reason: ok ? nil : detail
                )
                if ok {
                    self.setPictureInPictureActive(true)
                } else if showFailureToast {
                    self.persistPipPrefer(false)
                }
                completion?(ok)
                // Stash last failure detail for the menu toast.
                self.lastPipEnterDetail = detail
            }
        })
    }

    /// Last PiP enter detail string (for DEBUG toasts).
    private(set) var lastPipEnterDetail: String = ""

    private func reinforcePictureInPictureAfterForeground() {
        guard PipSession.isOwner(self),
              prefersPictureInPicture || isPictureInPictureActive || AppSettings.stickyPictureInPicture,
              let webView else { return }
        // User may have tapped the PiP window to restore the app — only reinforce if
        // system PiP is still active. Forcing re-enter here leaves the page unresponsive.
        MediaPlaybackSupport.configureAudioSessionIfNeeded(forceReactivate: true)
        webView.evaluateJavaScript(
            "(function(){try{return !!(window.__mmAnyInPiP&&window.__mmAnyInPiP());}catch(e){return false;}})();"
        ) { [weak self] result, _ in
            guard let self else { return }
            let stillInPip = (result as? Bool) ?? false
            guard stillInPip else {
                // Restored to inline — clear sticky so we don't immediately reclaim PiP.
                if self.prefersPictureInPicture || AppSettings.stickyPictureInPicture {
                    self.persistPipPrefer(false)
                }
                self.setPictureInPictureActive(false)
                return
            }
            MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, PipSession.isOwner(self),
                      AppSettings.stickyPictureInPicture || self.prefersPictureInPicture else { return }
                MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: self.webView)
                self.syncPictureInPictureActiveFromPage()
            }
        }
    }

    fileprivate func handleXSiteProbeMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            XSiteProbe.log("js.unparsed", ["raw": String(describing: message.body)])
            return
        }
        XSiteProbe.logJS(body)
    }

    fileprivate func handlePageMediaMessage(_ message: WKScriptMessage) {
        guard !isIncognito else { return }
        guard let body = message.body as? [String: Any] else { return }
        let event = (body["event"] as? String) ?? ""
        guard event == "playing" || event == "resources" || event == "play" else {
            return
        }

        let pageURL = body["pageURL"] as? String
        let statusID = body["statusID"] as? String
        let currentSrc = body["currentSrc"] as? String
        let resources = body["resources"] as? [String] ?? []
        PageMediaProbe.log("js.\(event)", [
            "statusID": statusID ?? "",
            "currentSrc": currentSrc ?? "",
            "resourceCount": resources.count,
            "w": body["width"] as? Int ?? 0,
            "h": body["height"] as? Int ?? 0
        ])

        pageMediaProbe.notePageContext(pageURL: pageURL, statusID: statusID)
        pageMediaProbe.noteCurrentSrc(currentSrc)
        for raw in resources {
            let cleaned = raw.replacingOccurrences(of: "\\/", with: "/")
            guard let url = URL(string: cleaned) else { continue }
            _ = pageMediaProbe.noteMediaURL(url, mimeType: nil)
        }

        if event == "playing" || event == "play" {
            _ = pageMediaProbe.notePlaying(pageURL: pageURL, statusID: statusID, currentSrc: currentSrc)
        }
        // Auto toast disabled — Save / Watch Later are user-triggered.
    }

    /// Starts a cookie-aware download for the best offline candidate (progressive MP4, else HLS).
    @discardableResult
    func startOfflineVideoDownload() -> Bool {
        guard !isIncognito else {
            PageMediaProbe.log("download.abort", ["why": "incognito"])
            return false
        }
        if OfflineMediaCopyrightPolicy.restrictsAudioVideo(on: webView?.url) {
            PageMediaProbe.log("download.abort", ["why": "copyrightPolicy"])
            Toast.show(OfflineMediaCopyrightPolicy.saveVideoBlockedNotice, from: self)
            return false
        }
        if RemoteConfigManager.shared.watchLaterRequiresOnlineMedia(for: webView?.url) {
            PageMediaProbe.log("download.abort", ["why": "watchLaterBlacklist"])
            Toast.show(WatchLaterMediaPolicy.onlineMediaRequiredNotice, from: self)
            return false
        }
        let candidate = pageMediaProbe.bestCandidate
        guard let candidate else {
            PageMediaProbe.log("download.abort", [
                "why": "noCandidate",
                "armed": pageMediaProbe.isArmed
            ])
            return false
        }
        if pageMediaProbe.isAlreadySavedOrDownloading(candidate) {
            PageMediaProbe.log("download.abort", ["why": "alreadySavedOrDownloading"])
            pageMediaProbe.markDownloadStarted(candidate)
            return false
        }
        pageMediaProbe.markDownloadStarted(candidate)
        PageMediaProbe.log("download.start", [
            "file": candidate.suggestedFileName,
            "mime": candidate.mimeType ?? (candidate.isHLS ? "application/vnd.apple.mpegurl" : "video/mp4"),
            "rank": candidate.rank,
            "hls": candidate.isHLS,
            "statusID": candidate.statusID ?? "",
            "url": candidate.url.absoluteString
        ])
        let refererPair = PageMediaProbe.downloadRefererOrigin(
            for: candidate.url,
            pageURL: candidate.pageURL ?? webView?.url?.absoluteString
        )
        let siteHeaders = [
            "Referer": refererPair.referer,
            "Origin": refererPair.origin
        ]
        if candidate.isHLS {
            DownloadManager.shared.startHLSOffline(
                masterURL: candidate.url,
                suggestedName: candidate.suggestedFileName,
                from: webView
            ) { [weak self] item in
                guard let self else { return }
                Toast.show("Downloading \(item.fileName)…", from: self)
            }
            return true
        }
        DownloadManager.shared.start(
            url: candidate.url,
            suggestedName: candidate.suggestedFileName,
            mimeType: candidate.mimeType ?? "video/mp4",
            from: webView
        ) { [weak self] item in
            guard let self else { return }
            Toast.show("Downloading \(item.fileName)…", from: self)
        }
        PageMediaProbe.log("download.headers", [
            "referer": siteHeaders["Referer"] ?? "",
            "origin": siteHeaders["Origin"] ?? ""
        ])
        return true
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
                    MediaPlaybackSupport.configureAudioSessionIfNeeded()
                    // Trusted page play exits custom float so inline video can take over.
                    CustomPipController.shared.dismissForPageUserPlay(from: self)
                    PipSession.handleTrustedUserPlay(from: self)
                }
            }
            if let playing = body["videoPlaying"] as? Bool {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let prev = self.pageHasPlayingVideo
                    self.pageHasPlayingVideo = playing
                if playing {
                    self.lastMediaPlayingAt = Date()
                    if !prev {
                        MediaPlaybackSupport.configureAudioSessionIfNeeded()
                    }
                }
                    if prev != playing {
                        PipProbe.log("chip.js.videoPlaying", [
                            "playing": playing,
                            "prev": prev,
                            "videoReady": body["videoReady"] as? Bool ?? false,
                            "nativeActive": self.isPictureInPictureActive,
                            "host": self.webView?.url?.host ?? "?"
                        ])
                    }
                    self.updatePipEntryButtonVisibility(reason: "js.videoPlaying")
                }
            } else if body["videoReady"] as? Bool != nil {
                DispatchQueue.main.async { [weak self] in
                    // Sticky reenter after next-track / media swap is owned by page JS.
                    // Restoring from every videoReady pulse re-opened PiP after a manual close.
                    self?.updatePipEntryButtonVisibility(reason: "js.videoReady")
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
            cancelStickyPipEnterAttempts()
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

    private func setPictureInPictureActive(_ active: Bool, reason: String = "setActive") {
        let changed = isPictureInPictureActive != active
        isPictureInPictureActive = active
        // Keep WKWebView visible so comments / related content stay usable under the PiP window.
        // PiP survival on foreground relies on MediaPlaybackSupport (presentation-mode / visibility guards).
        webView?.isHidden = false
        if changed {
            if active {
                MediaPlaybackSupport.configureAudioSessionIfNeeded()
            }
            PipProbe.log("chip.nativeActive", [
                "active": active,
                "reason": reason,
                "playing": pageHasPlayingVideo,
                "host": webView?.url?.host ?? "?"
            ])
        }
        updatePipEntryButtonVisibility(reason: "nativeActive.\(reason)")
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
        case XSiteProbe.handlerName:
            target?.handleXSiteProbeMessage(message)
        case PageMediaProbe.handlerName:
            target?.handlePageMediaMessage(message)
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
    /// X.com (and similar) kick embedded WebViews to Safari via Apple's private
    /// `x-safari-https://…` / `x-safari-http://…` schemes. Rewrite to normal https/http.
    private static func urlByUnwrappingSafariEscapeScheme(_ url: URL) -> URL? {
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme.hasPrefix("x-safari-") else { return nil }
        let realScheme = String(scheme.dropFirst("x-safari-".count))
        guard realScheme == "http" || realScheme == "https" else { return nil }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = realScheme
        return comps?.url
    }

    /// Empty kickout (`ct=rw-null`) — X detected a non-Safari client. Reloading x.com loops forever.
    private static func isXSafariKickoutNavigation(_ url: URL) -> Bool {
        let candidate: URL
        if let unwrapped = urlByUnwrappingSafariEscapeScheme(url) {
            candidate = unwrapped
        } else {
            candidate = url
        }
        guard let host = candidate.host?.lowercased(),
              host == "redirect.x.com" || host == "redirect.twitter.com" else { return false }
        return isXSafariKickoutURL(candidate)
    }

    private static func isXSafariKickoutURL(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let ct = items.first(where: { $0.name.lowercased() == "ct" })?.value?.lowercased()
        return ct == nil || ct == "rw-null" || ct == "null" || ct?.isEmpty == true
    }

    private static func xConsentToken(from url: URL) -> String? {
        let candidate = urlByUnwrappingSafariEscapeScheme(url) ?? url
        return URLComponents(url: candidate, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "ct" })?
            .value
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        YouTubeDarkMode.applyAppearance(to: webView, url: navigationAction.request.url)
        if let url = navigationAction.request.url {
            let cleaned = URLTrackingCleaner.cleaned(url, enabled: identityProfile.stripTrackingParams)
            if cleaned != url, navigationAction.targetFrame?.isMainFrame ?? true {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: cleaned))
                return
            }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if XSiteProbe.isRelevant(url) || (url.scheme ?? "").lowercased().hasPrefix("x-safari-")
                || url.absoluteString.lowercased().contains("oauth")
                || url.absoluteString.lowercased().contains("accounts.google") {
                XSiteProbe.log("nav.decide", [
                    "url": url.absoluteString,
                    "main": isMainFrame,
                    "type": navigationAction.navigationType.rawValue,
                    "source": navigationAction.sourceFrame.request.url?.absoluteString ?? "nil",
                    "adblock": AppSettings.trackerProtectionEnabled,
                    "ct": Self.xConsentToken(from: url) ?? "nil",
                    "targetNil": navigationAction.targetFrame == nil
                ])
            }

            // Drop Safari kickouts — reloading https://x.com causes an endless loop.
            if Self.isXSafariKickoutNavigation(url) {
                XSiteProbe.log("nav.ignoreKickout", [
                    "url": url.absoluteString,
                    "page": webView.url?.absoluteString ?? "nil",
                    "ct": Self.xConsentToken(from: url) ?? "nil"
                ])
                decisionHandler(.cancel)
                return
            }

            if let unwrapped = Self.urlByUnwrappingSafariEscapeScheme(url) {
                XSiteProbe.log("nav.rewriteXSafari", [
                    "from": url.absoluteString,
                    "to": unwrapped.absoluteString,
                    "main": isMainFrame
                ])
                decisionHandler(.cancel)
                load(url: unwrapped)
                return
            }

            if !isIncognito, PageMediaProbe.isLikelyMediaURL(url) {
                _ = pageMediaProbe.noteMediaURL(url, mimeType: nil)
            }

            let scheme = (url.scheme ?? "").lowercased()
            // Ignore App/deeplink schemes (common on Chinese portals like Sogou) to avoid "Unsupported URL".
            let allowed = ["http", "https", "about", "blob", "data", "file"]
            if !scheme.isEmpty && !allowed.contains(scheme) {
                if XSiteProbe.isRelevant(url) || scheme.contains("safari") || scheme.contains("twitter")
                    || scheme.contains("x-") || scheme.contains("google") {
                    XSiteProbe.log("nav.cancelScheme", ["url": url.absoluteString, "scheme": scheme])
                }
                decisionHandler(.cancel)
                return
            }

            if let redirected = YouTubeShortsFocus.redirectTarget(for: url), redirected != url {
                decisionHandler(.cancel)
                load(url: redirected)
                return
            }

            if isMainFrame,
               let whatsappWeb = DesktopUAHint.canonicalWebAppURL(for: url),
               whatsappWeb.absoluteString != url.absoluteString {
                decisionHandler(.cancel)
                load(url: whatsappWeb)
                return
            }

            // In-page / redirect navigations to WhatsApp: upgrade UA before the request goes out.
            if isMainFrame, promoteAutoComputerUAIfNeeded(for: url) {
                applyUserAgent(to: webView)
                if let site = DesktopUAHint.site(matching: url) {
                    notifyAutoComputerUAApplied(siteName: site.displayName)
                }
            }

            // Document-start scripts only apply to loads that begin after they are added.
            // First hit on YouTube / a media host: install then cancel+reload so scripts run.
            if isMainFrame, ["http", "https"].contains(scheme) {
                let mediaFeaturesOn = AppSettings.pictureInPictureEnabled || AppSettings.backgroundAudioEnabled
                let needsYouTubeScripts = YouTubeDarkMode.isYouTube(url) && !didInstallYouTubeScripts
                let needsMediaScript = mediaFeaturesOn
                    && !didInstallMediaScript
                    && MediaPlaybackSupport.shouldInstallScript(for: url)
                let needsOfflineVideoScript = !isIncognito
                    && !didInstallPageMediaScript
                    && PageMediaProbe.isEligiblePage(url)
                if needsYouTubeScripts || needsMediaScript || needsOfflineVideoScript {
                    ensureOnDemandScripts(for: url)
                    decisionHandler(.cancel)
                    load(url: url)
                    return
                }
            }

            if DownloadManager.isLikelyDownloadURL(url),
               navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                beginDownload(url: url, suggestedName: url.lastPathComponent)
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
            if isMainFrame, ["http", "https"].contains(scheme) {
                notifyDelegateOnMain {
                    $0.delegate?.webViewController($0, didUpdateURL: url)
                }
            }
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        let isMain = navigationResponse.isForMainFrame
        if !isIncognito, let url = response.url {
            let mime = response.mimeType
            if PageMediaProbe.isLikelyMediaURL(url)
                || mime?.lowercased().hasPrefix("video/") == true
                || (mime?.lowercased().contains("mpegurl") == true) {
                _ = pageMediaProbe.noteMediaURL(url, mimeType: mime)
            }
        }
        guard DownloadManager.shouldDownload(response: response, isForMainFrame: isMain),
              let url = response.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else {
            decisionHandler(.allow)
            return
        }
        // Never cancel inline media playback to download it automatically.
        if PageMediaProbe.isLikelyMediaURL(url)
            || response.mimeType?.lowercased().hasPrefix("video/") == true
            || (response.mimeType?.lowercased().contains("mpegurl") == true) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        let name = DownloadManager.suggestedFileName(from: response, url: url)
        beginDownload(url: url, suggestedName: name, mimeType: response.mimeType)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if PageCleanerManager.shouldApplyEarly(on: webView.url) {
            PageCleanerManager.apply(to: webView, url: webView.url)
        }
        // Fresh document — clear armed state / candidates, unless same watch page
        // (embedded players / ad iframes often commit navigations that would wipe HLS masters).
        let stayingOnPage = PageMediaProbe.isEligiblePage(webView.url)
        let prevVideoID = PageMediaProbe.videoID(fromPageURL: pageMediaProbe.pageURL)
        let nextVideoID = PageMediaProbe.videoID(fromPageURL: webView.url?.absoluteString)
        let sameWatchPage = prevVideoID != nil && prevVideoID == nextVideoID
        if sameWatchPage {
            pageMediaProbe.notePageContext(pageURL: webView.url?.absoluteString, statusID: nextVideoID)
        } else {
            pageMediaProbe.reset()
            if !stayingOnPage {
                pageMediaProbe.clearSessionOffers()
            }
        }
        desktopUAHintGeneration += 1
        recordNavigationHistory(from: webView.url)
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
            stickyPipEnterGeneration += 1
            stickyPipEnterInFlight = false
            prefersPictureInPicture = true
            MediaPlaybackSupport.seedStickyPrefer(in: webView)
        } else if AppSettings.stickyPictureInPicture, !PipSession.isOwner(self) {
            prefersPictureInPicture = false
            MediaPlaybackSupport.applyStickyPrefer(in: webView, prefer: false)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if XSiteProbe.isRelevant(webView.url) {
            XSiteProbe.log("nav.finish", [
                "url": webView.url?.absoluteString ?? "nil",
                "title": webView.title ?? "",
                "adblock": AppSettings.trackerProtectionEnabled,
                "hasOpenerProbe": true
            ])
            // Dump effective UA once page is ready.
            webView.evaluateJavaScript(
                "(function(){return {ua:navigator.userAgent,hasOpener:!!window.opener,href:location.href};})()"
            ) { result, _ in
                if let dict = result as? [String: Any] {
                    XSiteProbe.log("page.state", dict)
                } else {
                    XSiteProbe.log("ua.effective", ["ua": String(describing: result ?? "nil")])
                }
            }
        }
        errorContainer.isHidden = true
        httpsFallbackAttempted = false
        lastFailedURL = nil
        if let url = webView.url {
            lastRequestedURL = url
            recordNavigationHistory(from: url)
        }
        delegate?.webViewController(self, didUpdateProgress: 1, isLoading: false)
        delegate?.webViewController(self, didUpdateTitle: webView.title)
        delegate?.webViewController(self, didUpdateURL: webView.url)
        if !isIncognito, let url = webView.url, let containerID = browsingContainerID {
            HistoryStore.shared.add(title: webView.title ?? "", url: url, containerID: containerID)
        }
        AppAnalytics.logPageLoad(url: webView.url, incognito: isIncognito)
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
            webView.scrollView.minimumZoomScale = 1
            webView.scrollView.maximumZoomScale = 1
            webView.scrollView.zoomScale = 1
            if #available(iOS 14.0, *) { webView.pageZoom = 1.0 }
            var offset = webView.scrollView.contentOffset
            if offset.x != 0 {
                offset.x = 0
                webView.scrollView.contentOffset = offset
            }
        } else if Self.isViewportFragileHost(webView.url) {
            // Keep Bilibili zoom locked; do not rewrite their viewport meta.
            webView.scrollView.minimumZoomScale = 1
            webView.scrollView.maximumZoomScale = 1
            webView.scrollView.zoomScale = 1
            if #available(iOS 14.0, *) { webView.pageZoom = 1.0 }
            scheduleBilibiliStickyPlayerRepair()
        } else {
            webView.scrollView.minimumZoomScale = 1
            webView.scrollView.maximumZoomScale = 5
            webView.evaluateJavaScript(Self.viewportZoomUnlockScript.source, completionHandler: nil)
            webView.evaluateJavaScript(
                "(function(){var n=document.getElementById('mm-overflow-clamp');if(n&&n.parentNode)n.parentNode.removeChild(n);})();",
                completionHandler: nil
            )
        }
        pageCleanerNeedsReapply = false
        PageCleanerManager.apply(to: webView, url: webView.url)
        if isPageCleanerActive {
            PageCleanerManager.setPickMode(enabled: true, on: webView)
        }
        probeSessionAvatar(in: webView)
        considerDesktopUAHint(for: webView.url)
    }

    /// Public entry used after keyboard hide / manual refresh.
    func repairBilibiliStickyPlayerIfNeeded() {
        scheduleBilibiliStickyPlayerRepair()
    }

    private func scheduleBilibiliStickyPlayerRepair() {
        guard let host = webView?.url?.host?.lowercased() else { return }
        let isBili = host.contains("bilibili.com") || host.contains("bilibili.tv") || host == "b23.tv"
        guard isBili else { return }

        let urlKey = webView?.url?.absoluteString
        // New route → allow padding again.
        if urlKey != stickyPlayerRepairedURL {
            stickyPlayerRepairedURL = nil
        }

        stickyPlayerRepairWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.repairBilibiliStickyPlayerNow(markSettledAfterStable: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.webView?.url?.absoluteString == urlKey else { return }
                self.repairBilibiliStickyPlayerNow(markSettledAfterStable: true)
            }
        }
        stickyPlayerRepairWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func repairBilibiliStickyPlayerNow(markSettledAfterStable: Bool) {
        guard let webView else { return }
        webView.evaluateJavaScript(Self.bilibiliStickyPlayerPadScript) { [weak self] result, _ in
            guard let self else { return }
            guard markSettledAfterStable,
                  let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = obj["action"] as? String else { return }
            // stable / pad / clear all mean we are done fighting this URL's first paint.
            if action == "stable" || action == "pad" || action == "shrink" || action == "clear" {
                self.stickyPlayerRepairedURL = webView.url?.absoluteString
            }
        }
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

    private func considerDesktopUAHint(for url: URL?) {
        desktopUAHintGeneration += 1
        let generation = desktopUAHintGeneration
        guard let url, let site = DesktopUAHint.site(matching: url) else { return }
        guard !tabUserAgentSettings.looksLikeComputer else { return }

        if site.autoApplyComputerUserAgent {
            // Fallback if the first request somehow used Phone UA (e.g. restored session).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, generation == self.desktopUAHintGeneration else { return }
                guard self.promoteAutoComputerUAIfNeeded(for: url) else { return }
                guard let webView = self.webView else { return }
                self.applyUserAgent(to: webView)
                self.notifyAutoComputerUAApplied(siteName: site.displayName)
                webView.reload()
            }
            return
        }

        let path = url.path.lowercased()
        if site.loginPathTokens.contains(where: { path.contains($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, generation == self.desktopUAHintGeneration else { return }
                self.delegate?.webViewController(self, suggestComputerUserAgentFor: site.displayName)
            }
            return
        }
        scheduleDesktopUAHint(generation: generation, delay: 1.1, site: site, lastChance: false)
    }

    private func scheduleDesktopUAHint(generation: Int, delay: TimeInterval, site: DesktopUAHint.Site, lastChance: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.desktopUAHintGeneration else { return }
            self.webView?.evaluateJavaScript(site.probeJavaScript) { [weak self] result, _ in
                guard let self, generation == self.desktopUAHintGeneration else { return }
                let state = (result as? String) ?? "unknown"
                if state == "logged-in" { return }
                if state == "login" {
                    self.delegate?.webViewController(self, suggestComputerUserAgentFor: site.displayName)
                    return
                }
                if !lastChance {
                    self.scheduleDesktopUAHint(generation: generation, delay: 1.8, site: site, lastChance: true)
                }
            }
        }
    }

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
        if XSiteProbe.isRelevant(webView?.url)
            || XSiteProbe.isRelevant(Self.urlFromNavigationError(nsError))
            || ((nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)?.contains("x.com") == true)
            || ((nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)?.contains("x-safari") == true) {
            XSiteProbe.log("nav.fail", [
                "code": nsError.code,
                "domain": nsError.domain,
                "desc": nsError.localizedDescription,
                "failing": (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? "nil",
                "page": webView?.url?.absoluteString ?? "nil"
            ])
        }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        // App-link / unsupported scheme failures should not blank the page.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorUnsupportedURL {
            if let failing = Self.urlFromNavigationError(nsError)
                ?? (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:)) {
                if Self.isXSafariKickoutNavigation(failing) {
                    XSiteProbe.log("nav.fail.ignoreKickout", ["from": failing.absoluteString])
                    return
                }
                if let unwrapped = Self.urlByUnwrappingSafariEscapeScheme(failing) {
                    XSiteProbe.log("nav.fail.unwrap", [
                        "from": failing.absoluteString,
                        "to": unwrapped.absoluteString
                    ])
                    load(url: unwrapped)
                }
            }
            return
        }
        if let failing = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            if Self.isXSafariKickoutNavigation(failing) {
                XSiteProbe.log("nav.fail.ignoreKickoutKey", ["from": failing.absoluteString])
                return
            }
            if let unwrapped = Self.urlByUnwrappingSafariEscapeScheme(failing) {
                XSiteProbe.log("nav.fail.unwrapKey", [
                    "from": failing.absoluteString,
                    "to": unwrapped.absoluteString
                ])
                load(url: unwrapped)
                return
            }
            let scheme = (failing.scheme ?? "").lowercased()
            if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
                return
            }
        }

        let failedURL = Self.urlFromNavigationError(nsError)
            ?? webView?.url
            ?? lastRequestedURL
            ?? lastFailedURL

        // HTTPS first fallback to http once
        if !AppSettings.httpsOnly,
           !httpsFallbackAttempted,
           let url = failedURL,
           url.scheme == "https",
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            httpsFallbackAttempted = true
            comps.scheme = "http"
            if let httpURL = comps.url {
                lastRequestedURL = httpURL
                webView?.load(URLRequest(url: httpURL))
                return
            }
        }

        lastFailedURL = failedURL
        if let failedURL {
            lastRequestedURL = failedURL
            notifyDelegateOnMain {
                $0.delegate?.webViewController($0, didUpdateURL: failedURL)
            }
        }
        AppAnalytics.logNavigationError(url: failedURL, domain: nsError.domain, code: nsError.code)
        errorLabel.text = "Couldn't load page.\n\(error.localizedDescription)"
        errorContainer.isHidden = false
        delegate?.webViewControllerDidFail(self, error: error)
        delegate?.webViewController(self, didUpdateProgress: 0, isLoading: false)
    }

    private static func urlFromNavigationError(_ error: NSError) -> URL? {
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        if let raw = error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
           let url = URL(string: raw) {
            return url
        }
        return nil
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        let urlString = url?.absoluteString ?? "nil"
        let isAuth = XSiteProbe.isRelevant(url)
            || XSiteProbe.isRelevant(webView.url)
            || urlString.lowercased().contains("google")
            || urlString.lowercased().contains("oauth")
            || urlString == "about:blank"
            || url == nil
        if XSiteProbe.isEnabled, isAuth || (navigationAction.targetFrame == nil) {
            XSiteProbe.log("ui.createWebView", [
                "url": urlString,
                "page": webView.url?.absoluteString ?? "nil",
                "targetNil": navigationAction.targetFrame == nil,
                "navType": navigationAction.navigationType.rawValue,
                "hasWidth": windowFeatures.width != nil,
                "hasHeight": windowFeatures.height != nil,
                "configProcessPool": ObjectIdentifier(configuration.processPool).debugDescription
            ])
        }

        guard navigationAction.targetFrame == nil else {
            return nil
        }

        // Block known ad-network / popunder window.open when tracker protection is on.
        if AppSettings.trackerProtectionEnabled,
           let url,
           VideoAdShield.isLikelyAdPopup(url) {
            PipProbe.log("ui.blockAdPopup", ["url": url.host ?? url.absoluteString])
            return nil
        }

        if let url, Self.isXSafariKickoutNavigation(url) {
            XSiteProbe.log("ui.ignoreKickoutPopup", ["url": url.absoluteString])
            return nil
        }

        let looksLikeWindowOpen = windowFeatures.width != nil || windowFeatures.height != nil
        let looksLikeAuthPopup = isAuth || looksLikeWindowOpen
            || urlString.lowercased().contains("accounts.google")
            || urlString.lowercased().contains("oauth")
            || urlString.lowercased().contains("appleid")

        // Plain target=_blank links keep the old new-tab behavior.
        if !looksLikeAuthPopup, let url {
            if let unwrapped = Self.urlByUnwrappingSafariEscapeScheme(url) {
                load(url: unwrapped)
            } else {
                XSiteProbe.log("ui.createWebView.newTab", ["url": url.absoluteString])
                delegate?.webViewController(self, requestNewTabFor: url)
            }
            return nil
        }

        // Prefer a real popup WebView so window.open() returns a WindowProxy and
        // Google GSI (ux_mode=popup) can postMessage back to the opener.
        if let existing = authPopup?.popupWebView {
            // The existing view was created with a different configuration. Returning it
            // throws NSInternalInconsistencyException. Load real URLs into it instead.
            XSiteProbe.log("ui.createWebView.reusePopup", ["url": urlString, "action": "loadExisting"])
            if let url, Self.canLoadInExistingPopup(url) {
                existing.load(URLRequest(url: url))
            }
            return nil
        }

        // Use WebKit's configuration exactly once. Do not call load() — WebKit loads
        // the request into the returned web view. Manual load() clears window.opener
        // and leaves Google stuck on a blank /gsi/transform page.
        let popupWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        // Must be in the view hierarchy before this method returns or opener stays null.
        popupWebView.isHidden = true
        view.addSubview(popupWebView)

        let popup = AuthPopupViewController(webView: popupWebView)
        popup.onDismissed = { [weak self] in
            self?.authPopup = nil
            XSiteProbe.log("ui.popupCleared", [:])
        }
        authPopup = popup

        let host: UIViewController = {
            var candidate: UIViewController = self
            while let parent = candidate.parent { candidate = parent }
            return candidate
        }()
        XSiteProbe.log("ui.createWebView.returnPopup", [
            "url": urlString,
            "inHierarchy": popupWebView.superview != nil,
            "pool": ObjectIdentifier(configuration.processPool).debugDescription
        ])
        DispatchQueue.main.async { [weak host] in
            guard let host else { return }
            if host.presentedViewController is AuthPopupViewController { return }
            if let presented = host.presentedViewController {
                presented.dismiss(animated: false) {
                    popup.present(from: host)
                }
            } else {
                popup.present(from: host)
            }
        }
        return popupWebView
    }

    fileprivate static func canLoadInExistingPopup(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https"
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === authPopup?.popupWebView {
            XSiteProbe.log("ui.webViewDidClose.popup", ["url": webView.url?.absoluteString ?? "nil"])
            authPopup?.dismissPopup()
            authPopup = nil
        }
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
                    let canDownload = DownloadManager.isLikelyDownloadURL(linkURL)
                        || ["http", "https"].contains((linkURL.scheme ?? "").lowercased())
                    if canDownload {
                        actions.append(UIAction(title: "Download Linked File", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
                            self?.beginDownload(url: linkURL, suggestedName: linkURL.lastPathComponent)
                        })
                    }
                    actions.append(UIAction(title: "Add to Watch Later", image: UIImage(systemName: "clock.badge.checkmark")) { [weak self] _ in
                        self?.addLinkToWatchLater(linkURL)
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

    private func addLinkToWatchLater(_ url: URL) {
        guard !isIncognito else {
            Toast.show("Not available in Private Browsing", from: self)
            return
        }
        let title = url.host ?? "Saved"
        let containerID = browsingContainerID ?? ContainerScope.resolveContainerID(nil)
        if WatchLaterStore.shared.add(title: title, url: url, containerID: containerID) != nil {
            if OfflineMediaCopyrightPolicy.restrictsAudioVideo(on: url) {
                Toast.show(
                    "Added to Watch Later. \(OfflineMediaCopyrightPolicy.watchLaterNotice)",
                    from: self
                )
            } else {
                Toast.show("Added to Watch Later", from: self)
            }
            if webView?.url?.absoluteString == url.absoluteString {
                cacheCurrentPageForWatchLater(matching: url)
            }
        } else {
            Toast.show("Already in Watch Later", from: self)
        }
    }

    /// Saves a page snapshot for Watch Later (text/images). May also keep playable media when policy allows.
    func cacheCurrentPageForWatchLater(matching url: URL) {
        guard let webView else { return }
        let containerID = browsingContainerID ?? ContainerScope.resolveContainerID(nil)
        guard let item = WatchLaterStore.shared.items(containerID: containerID).first(where: { $0.urlString == url.absoluteString }) else {
            return
        }
        // Offline media only when Remote Config blacklist + copyright policy both allow it.
        let candidate = WatchLaterMediaPolicy.allowsOfflineMedia(on: url)
            ? pageMediaProbe.bestCandidate
            : nil
        WatchLaterStore.shared.markCaching(id: item.id, hasVideo: candidate != nil)
        let itemID = item.id
        // Capture a grid thumbnail while the live page is still on-screen.
        captureSnapshot { image in
            guard let image,
                  let data = image.jpegData(compressionQuality: 0.72) else { return }
            let name = "\(itemID.uuidString).jpg"
            let dest = WatchLaterStore.fileURL(named: name, containerID: containerID)
            do {
                try data.write(to: dest, options: .atomic)
                WatchLaterStore.shared.markPreviewSaved(id: itemID, fileName: name)
            } catch {}
        }
        // Media download runs in parallel with page-image warming when policy allows.
        if let candidate {
            downloadWatchLaterVideo(candidate, itemID: itemID, containerID: containerID)
        }
        preparePageImagesForOfflineArchive(in: webView) { [weak self] in
            self?.writeWatchLaterWebArchive(from: webView, itemID: itemID, containerID: containerID)
        }
    }

    private func writeWatchLaterWebArchive(from webView: WKWebView, itemID: UUID, containerID: UUID) {
        webView.createWebArchiveData { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    let name = "\(itemID.uuidString).webarchive"
                    let dest = WatchLaterStore.fileURL(named: name, containerID: containerID)
                    do {
                        try data.write(to: dest, options: .atomic)
                        WatchLaterStore.shared.markPageArchived(id: itemID, fileName: name)
                    } catch {
                        WatchLaterStore.shared.markCacheFailed(id: itemID)
                    }
                case .failure:
                    WatchLaterStore.shared.markCacheFailed(id: itemID)
                }
            }
        }
    }

    /// Eager-load lazy images, then inline them as data URIs before archiving.
    private func preparePageImagesForOfflineArchive(in webView: WKWebView, completion: @escaping () -> Void) {
        let finish = { DispatchQueue.main.async { completion() } }
        webView.callAsyncJavaScript(
            Self.prepareImagesForArchiveScript,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { finish(); return }
            var urls: [String] = []
            if case .success(let value) = result {
                if let dict = value as? [String: Any] {
                    urls = dict["urls"] as? [String] ?? []
                    PageMediaProbe.log("archive.images", [
                        "loaded": dict["loaded"] ?? 0,
                        "urlCount": urls.count
                    ])
                } else {
                    PageMediaProbe.log("archive.images", ["loaded": "\(value)"])
                }
            } else if case .failure(let error) = result {
                PageMediaProbe.log("archive.images", ["error": error.localizedDescription])
            }
            self.inlineRemoteImagesForArchive(urls: urls, in: webView, completion: finish)
        }
    }

    private func inlineRemoteImagesForArchive(urls: [String], in webView: WKWebView, completion: @escaping () -> Void) {
        // Prefer first N (JS already ranks); keep payload small enough for JS bridges.
        let unique = urls
            .filter { $0.lowercased().hasPrefix("http") }
            .reduce(into: [String]()) { acc, u in
                if !acc.contains(u) { acc.append(u) }
            }
            .prefix(48)
        guard !unique.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: completion)
            return
        }
        let pageURL = webView.url?.absoluteString
        let pageUA = webView.customUserAgent
            ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [weak self] all in
            guard let self else { completion(); return }
            let group = DispatchGroup()
            let lock = NSLock()
            var dataURLs: [String: String] = [:]
            let session = URLSession(configuration: {
                let c = URLSessionConfiguration.ephemeral
                c.timeoutIntervalForRequest = 10
                c.httpMaximumConnectionsPerHost = 6
                return c
            }())
            for raw in unique {
                guard let url = URL(string: raw) else { continue }
                group.enter()
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue(pageUA, forHTTPHeaderField: "User-Agent")
                let pair = PageMediaProbe.downloadRefererOrigin(for: url, pageURL: pageURL)
                if !pair.referer.isEmpty {
                    request.setValue(pair.referer, forHTTPHeaderField: "Referer")
                    request.setValue(pair.origin, forHTTPHeaderField: "Origin")
                }
                let related = PageMediaProbe.relatedCookieHosts(for: url, pageURL: pageURL)
                let cookies = all.filter { cookie in
                    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return related.contains { host in
                        host == domain || host.hasSuffix("." + domain) || domain.hasSuffix(host)
                    }
                }
                if !cookies.isEmpty {
                    for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
                        request.setValue(v, forHTTPHeaderField: k)
                    }
                }
                session.dataTask(with: request) { data, response, _ in
                    defer { group.leave() }
                    guard let data, !data.isEmpty, data.count <= 2_000_000 else { return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<400).contains(status) || status == 0 else { return }
                    var mime = (response as? HTTPURLResponse)?.mimeType
                        ?? response?.mimeType
                        ?? Self.guessImageMIME(for: url, data: data)
                    if mime == "application/octet-stream" || mime.isEmpty {
                        mime = Self.guessImageMIME(for: url, data: data)
                    }
                    // Accept image/* and octet-stream that looks like an image.
                    let looksImage = mime.hasPrefix("image/")
                        || Self.guessImageMIME(for: url, data: data).hasPrefix("image/")
                    guard looksImage else { return }
                    if !mime.hasPrefix("image/") {
                        mime = Self.guessImageMIME(for: url, data: data)
                    }
                    let dataURL = "data:\(mime);base64,\(data.base64EncodedString())"
                    lock.lock()
                    dataURLs[raw] = dataURL
                    lock.unlock()
                }.resume()
            }
            group.notify(queue: .main) {
                guard !dataURLs.isEmpty else {
                    PageMediaProbe.log("archive.inline", ["count": 0, "attempted": unique.count])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: completion)
                    return
                }
                PageMediaProbe.log("archive.inline", ["count": dataURLs.count, "attempted": unique.count])
                self.applyDataURIReplacements(dataURLs, in: webView, completion: completion)
            }
        }
    }

    /// Apply in small batches — a single huge argument map often fails silently in WK.
    private func applyDataURIReplacements(
        _ dataURLs: [String: String],
        in webView: WKWebView,
        completion: @escaping () -> Void
    ) {
        let pairs = Array(dataURLs)
        let batchSize = 4
        var index = 0
        var totalApplied = 0

        func applyNext() {
            if index >= pairs.count {
                PageMediaProbe.log("archive.inlineApplied", ["n": totalApplied])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: completion)
                return
            }
            let end = min(index + batchSize, pairs.count)
            var slice: [String: String] = [:]
            for i in index..<end {
                slice[pairs[i].key] = pairs[i].value
            }
            index = end
            webView.callAsyncJavaScript(
                Self.replaceImagesWithDataURIScript,
                arguments: ["map": slice],
                in: nil,
                in: .page
            ) { result in
                if case .success(let value) = result {
                    totalApplied += (value as? Int) ?? (value as? Double).map(Int.init) ?? 0
                }
                applyNext()
            }
        }
        applyNext()
    }

    private static func guessImageMIME(for url: URL, data: Data) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico": return "image/x-icon"
        default: break
        }
        if data.count >= 12, data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,
           data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50 {
            return "image/webp"
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if data.starts(with: [0x3C, 0x73, 0x76, 0x67]) || data.starts(with: [0x3C, 0x3F, 0x78, 0x6D]) {
            return "image/svg+xml"
        }
        return "image/jpeg"
    }

    /// Site-agnostic: promote lazy attrs, harvest performance/DOM URLs, rank for offline keep.
    private static let prepareImagesForArchiveScript = #"""
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pickFromSrcset(srcset) {
  if (!srcset) return null;
  const parts = String(srcset).split(',').map((s) => s.trim()).filter(Boolean);
  if (!parts.length) return null;
  // Prefer the widest candidate when descriptors exist.
  let best = null, bestW = -1;
  for (const part of parts) {
    const bits = part.split(/\s+/);
    const u = bits[0];
    const w = parseInt((bits[1] || '').replace(/[^\d]/g, ''), 10) || 0;
    if (!best || w >= bestW) { best = u; bestW = w; }
  }
  return best || parts[parts.length - 1].split(/\s+/)[0] || null;
}

function isMediaURL(u) {
  return /\.(mp4|m3u8|webm|m4s|ts|mpd)(\?|$)/i.test(u || '');
}

function isLikelyImageURL(u) {
  if (!u || !/^https?:/i.test(u)) return false;
  if (isMediaURL(u)) return false;
  if (/^data:/i.test(u)) return false;
  if (/\.(jpg|jpeg|png|webp|gif|svg|ico|avif|bmp)(\?|$)/i.test(u)) return true;
  if (/\/(i|img|image|images|imgs|thumb|thumbnail|avatar|icon|icons|static|media|photo|photos|pic|pics)\b/i.test(u)) return true;
  if (/[?&](format|fm|type)=(jpg|jpeg|png|webp|gif|image)/i.test(u)) return true;
  // Path tokens that usually mean a raster asset (no host allowlists).
  if (/\/(?:vi|img|image|images|thumb|thumbs|avatar|avatars|icon|icons|media|photos?)\/[^/]+/i.test(u)) return true;
  return false;
}

function upgradeImage(img) {
  try {
    const attrs = [
      'data-src', 'data-lazy-src', 'data-original', 'data-thumb', 'data-thumbnail',
      'data-url', 'data-image', 'data-bg', 'data-background', 'data-poster',
      'data-lazy', 'data-src-large', 'data-full-src'
    ];
    for (const name of attrs) {
      const v = img.getAttribute && img.getAttribute(name);
      if (v && /^https?:/i.test(v)) {
        if (img.tagName === 'VIDEO') {
          if (!img.getAttribute('poster')) img.setAttribute('poster', v);
        } else if (!img.getAttribute('src') || /placeholder|data:image\/svg|1x1|pixel|blur/i.test(img.getAttribute('src') || '')) {
          img.setAttribute('src', v);
        }
      }
    }
    const srcset = img.getAttribute('srcset') || img.getAttribute('data-srcset');
    const best = pickFromSrcset(srcset);
    if (best && /^https?:/i.test(best)) {
      img.setAttribute('src', best);
      img.removeAttribute('srcset');
      img.removeAttribute('data-srcset');
    }
    if (img.tagName === 'IMG' || img.tagName === 'SOURCE' || img.tagName === 'IMAGE') {
      img.setAttribute('loading', 'eager');
      img.loading = 'eager';
      img.setAttribute('decoding', 'sync');
      try { img.decode && img.decode().catch(() => {}); } catch (e) {}
    }
  } catch (e) {}
}

function upgradeBackground(el) {
  try {
    const attrs = ['data-bg', 'data-background', 'data-src', 'data-thumb', 'data-image', 'data-thumbnail'];
    for (const name of attrs) {
      const v = el.getAttribute && el.getAttribute(name);
      if (v && /^https?:/i.test(v)) {
        const style = el.getAttribute('style') || '';
        if (!/background(-image)?\s*:/i.test(style)) {
          el.setAttribute('style', style + ';background-image:url("' + v + '")');
        }
        break;
      }
    }
  } catch (e) {}
}

function walk(root) {
  if (!root || !root.querySelectorAll) return;
  root.querySelectorAll('img, source, video, image').forEach(upgradeImage);
  root.querySelectorAll('[data-bg], [data-background], [data-thumb], [data-image], [data-thumbnail], [data-src]').forEach(upgradeBackground);
  root.querySelectorAll('*').forEach((el) => {
    try { if (el.shadowRoot) walk(el.shadowRoot); } catch (e) {}
  });
}

function scoreURL(u, el) {
  let s = 0;
  if (/thumbnail|thumb|avatar|profile|poster|cover|preview/i.test(u)) s += 50;
  if (/\.(jpg|jpeg|png|webp)(\?|$)/i.test(u)) s += 15;
  if (/\.svg(\?|$)/i.test(u)) s += 5;
  if (/icon|sprite|logo|favicon/i.test(u)) s += 8;
  try {
    if (el && el.getBoundingClientRect) {
      const r = el.getBoundingClientRect();
      const area = Math.max(0, r.width) * Math.max(0, r.height);
      if (area > 20000) s += 40;
      else if (area > 4000) s += 25;
      else if (area > 400) s += 10;
      if (r.top < (window.innerHeight || 800) && r.bottom > 0) s += 20;
    }
  } catch (e) {}
  return s;
}

function collectImageURLs(root) {
  const scored = [];
  const seen = {};
  function push(u, el, bonus) {
    if (!u) return;
    u = String(u).trim();
    if (!isLikelyImageURL(u)) return;
    if (seen[u]) return;
    seen[u] = 1;
    scored.push({ u, s: scoreURL(u, el) + (bonus || 0) });
  }
  function urlsInString(s, el, bonus) {
    if (!s) return;
    const re = /https?:\/\/[^\s"'\\<>]+/g;
    let m;
    while ((m = re.exec(String(s)))) {
      let u = m[0].replace(/[),.;]+$/, '');
      push(u, el, bonus);
    }
  }
  function visit(node) {
    if (!node || !node.querySelectorAll) return;
    node.querySelectorAll('img, source, image').forEach((el) => {
      push(el.currentSrc || el.getAttribute('src'), el, 30);
      push(el.getAttribute('data-src'), el, 20);
      push(el.getAttribute('data-thumb'), el, 20);
      push(pickFromSrcset(el.getAttribute('srcset') || el.getAttribute('data-srcset')), el, 25);
    });
    node.querySelectorAll('video').forEach((el) => push(el.getAttribute('poster'), el, 35));
    node.querySelectorAll('meta[property="og:image"], meta[name="twitter:image"], link[rel="icon"], link[rel="apple-touch-icon"]').forEach((el) => {
      push(el.getAttribute('content') || el.getAttribute('href'), el, 50);
    });
    const all = node.querySelectorAll('*');
    for (let i = 0; i < all.length; i++) {
      const el = all[i];
      try {
        if (el.attributes) {
          for (let a = 0; a < el.attributes.length; a++) {
            const v = el.attributes[a].value;
            if (v && v.indexOf('http') !== -1) urlsInString(v, el, 5);
          }
        }
        const inline = (el.getAttribute && el.getAttribute('style')) || '';
        urlsInString(inline, el, 10);
        try {
          const bg = (window.getComputedStyle && getComputedStyle(el).backgroundImage) || '';
          urlsInString(bg, el, 15);
        } catch (e) {}
        if (el.shadowRoot) visit(el.shadowRoot);
      } catch (e) {}
    }
  }
  visit(root);
  try {
    const entries = performance.getEntriesByType('resource') || [];
    for (const e of entries) {
      const name = e.name || '';
      const init = e.initiatorType || '';
      if (init === 'img' || init === 'css' || init === 'link' || isLikelyImageURL(name)) {
        push(name, null, init === 'img' ? 40 : 10);
      }
    }
  } catch (e) {}
  scored.sort((a, b) => b.s - a.s);
  return scored.map((x) => x.u).slice(0, 56);
}

async function waitForImages(root) {
  const imgs = [];
  function collect(node) {
    if (!node || !node.querySelectorAll) return;
    node.querySelectorAll('img').forEach((img) => imgs.push(img));
    node.querySelectorAll('*').forEach((el) => {
      try { if (el.shadowRoot) collect(el.shadowRoot); } catch (e) {}
    });
  }
  collect(root);
  await Promise.all(imgs.slice(0, 80).map((img) => new Promise((resolve) => {
    try {
      if (img.complete && img.naturalWidth > 0) { resolve(); return; }
      const done = () => resolve();
      img.addEventListener('load', done, { once: true });
      img.addEventListener('error', done, { once: true });
      setTimeout(done, 2800);
    } catch (e) { resolve(); }
  })));
  return imgs.filter((img) => img.naturalWidth > 0).length;
}

walk(document);
try {
  const h = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 0);
  for (const y of [0, 900, 1800, 2700, Math.min(h, 3600)]) {
    window.scrollTo(0, y);
    await sleep(220);
    walk(document);
  }
  window.scrollTo(0, 0);
  await sleep(160);
} catch (e) {}
walk(document);
const loaded = await waitForImages(document);
const urls = collectImageURLs(document);
return { loaded, urls };
"""#

    private static let replaceImagesWithDataURIScript = #"""
const replacements = (typeof map === 'object' && map) ? map : {};
const keys = Object.keys(replacements);

function norm(u) {
  if (!u) return '';
  try { return String(u).trim().split('#')[0]; } catch (e) { return String(u); }
}

function lookup(u) {
  if (!u) return null;
  const n = norm(u);
  if (replacements[u]) return replacements[u];
  if (replacements[n]) return replacements[n];
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (norm(k) === n) return replacements[k];
    // Match when query params differ but path is identical.
    try {
      const a = new URL(k);
      const b = new URL(n, document.baseURI);
      if (a.origin === b.origin && a.pathname === b.pathname) return replacements[k];
    } catch (e) {}
  }
  return null;
}

function setBg(el, dataUrl) {
  try {
    const style = el.getAttribute('style') || '';
    if (/url\(["']?data:/i.test(style)) return false;
    const cleaned = style.replace(/background-image\s*:\s*[^;]+;?/ig, '');
    el.setAttribute('style', cleaned + ';background-image:url("' + dataUrl + '");background-size:cover;background-position:center;');
    return true;
  } catch (e) { return false; }
}

function apply(root) {
  if (!root || !root.querySelectorAll) return 0;
  let n = 0;
  root.querySelectorAll('img, source, image').forEach((el) => {
    try {
      const candidates = [
        el.getAttribute('src'), el.currentSrc,
        el.getAttribute('data-src'), el.getAttribute('data-thumb'),
        el.getAttribute('data-original'), el.getAttribute('data-lazy-src')
      ];
      const srcset = el.getAttribute('srcset') || el.getAttribute('data-srcset');
      if (srcset) {
        String(srcset).split(',').forEach((part) => candidates.push(part.trim().split(/\s+/)[0]));
      }
      for (const c of candidates) {
        const data = lookup(c);
        if (data) {
          el.setAttribute('src', data);
          el.removeAttribute('srcset');
          el.removeAttribute('data-srcset');
          n += 1;
          break;
        }
      }
    } catch (e) {}
  });
  root.querySelectorAll('video').forEach((el) => {
    const data = lookup(el.getAttribute('poster'));
    if (data) { el.setAttribute('poster', data); n += 1; }
  });
  root.querySelectorAll('*').forEach((el) => {
    try {
      if (el.shadowRoot) n += apply(el.shadowRoot);
      if (el.attributes) {
        for (let a = 0; a < el.attributes.length; a++) {
          const attr = el.attributes[a];
          const data = lookup(attr.value);
          if (data && /src|thumb|image|poster|bg|background|url|icon/i.test(attr.name)) {
            if (attr.name === 'src' || attr.name === 'poster') {
              el.setAttribute(attr.name, data);
            } else {
              setBg(el, data);
            }
            n += 1;
          }
        }
      }
      const style = el.getAttribute('style') || '';
      const m = style.match(/url\(["']?(https?:[^"')]+)["']?\)/i);
      if (m) {
        const data = lookup(m[1]);
        if (data) {
          el.setAttribute('style', style.replace(m[0], 'url("' + data + '")'));
          n += 1;
        }
      }
      try {
        const bg = (window.getComputedStyle && getComputedStyle(el).backgroundImage) || '';
        const cm = bg.match(/url\(["']?(https?:[^"')]+)["']?\)/i);
        if (cm) {
          const data = lookup(cm[1]);
          if (data) { if (setBg(el, data)) n += 1; }
        }
      } catch (e) {}
    } catch (e) {}
  });
  return n;
}
return apply(document);
"""#

    private func downloadWatchLaterVideo(_ candidate: PageMediaCandidate, itemID: UUID, containerID: UUID) {
        let fileName = "\(itemID.uuidString).mp4"
        let dest = WatchLaterStore.fileURL(named: fileName, containerID: containerID)
        let pageURLString = candidate.pageURL ?? webView?.url?.absoluteString
        let referer = PageMediaProbe.downloadRefererOrigin(for: candidate.url, pageURL: pageURLString)
        let begin: ([HTTPCookie]) -> Void = { [weak self] cookies in
            guard let self else { return }
            var headers = [
                "Referer": referer.referer,
                "Origin": referer.origin,
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                "Accept": "*/*"
            ]
            if !cookies.isEmpty {
                for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                    headers[key] = value
                }
            }
            let packageHLS: (URL) -> Void = { masterURL in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        _ = try MediaHLSOfflinePackager.package(
                            masterURL: masterURL,
                            destinationURL: dest,
                            headers: headers,
                            progress: nil,
                            isCancelled: { false }
                        )
                        DispatchQueue.main.async {
                            WatchLaterStore.shared.markVideoSaved(id: itemID, fileName: fileName)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            WatchLaterStore.shared.markCacheFailed(id: itemID)
                        }
                    }
                }
            }
            if candidate.isHLS {
                packageHLS(candidate.url)
                return
            }
            var request = URLRequest(url: candidate.url)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            URLSession.shared.downloadTask(with: request) { [weak self] temp, response, error in
                let http = response as? HTTPURLResponse
                let ok = error == nil && http.map { (200..<300).contains($0.statusCode) } == true
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard ok, let temp else {
                        // Progressive failed — fall back to HLS master when available.
                        if let hls = self.pageMediaProbe.bestHLSCandidate {
                            packageHLS(hls.url)
                        } else {
                            WatchLaterStore.shared.markCacheFailed(id: itemID)
                        }
                        return
                    }
                    try? FileManager.default.removeItem(at: dest)
                    do {
                        try FileManager.default.moveItem(at: temp, to: dest)
                        let size = ((try? FileManager.default.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber)?.int64Value ?? 0
                        // Tiny / non-MP4 bodies are almost always previews or CDN error pages.
                        if size < 64_768 || !Self.fileLooksLikePlayableMP4(dest) {
                            try? FileManager.default.removeItem(at: dest)
                            if let hls = self.pageMediaProbe.bestHLSCandidate {
                                packageHLS(hls.url)
                            } else {
                                WatchLaterStore.shared.markCacheFailed(id: itemID)
                            }
                            return
                        }
                        WatchLaterStore.shared.markVideoSaved(id: itemID, fileName: fileName)
                    } catch {
                        WatchLaterStore.shared.markCacheFailed(id: itemID)
                    }
                }
            }.resume()
        }
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else {
            begin([])
            return
        }
        store.getAllCookies { all in
            let related = PageMediaProbe.relatedCookieHosts(
                for: candidate.url,
                pageURL: pageURLString
            )
            let matched = all.filter { cookie in
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return related.contains { host in
                    host == domain || host.hasSuffix("." + domain) || domain.hasSuffix(host)
                }
            }
            DispatchQueue.main.async { begin(matched) }
        }
    }

    private static func fileLooksLikePlayableMP4(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let prefix = handle.readData(ofLength: 12)
        guard prefix.count >= 8 else { return false }
        let ftyp = prefix.subdata(in: 4..<8)
        return String(data: ftyp, encoding: .ascii) == "ftyp"
    }

    private func addLinkToReadingList(_ url: URL) {
        guard !isIncognito else {
            Toast.show("Not available in Private Browsing", from: self)
            return
        }
        let title = url.host ?? "Saved"
        let containerID = browsingContainerID ?? ContainerScope.resolveContainerID(nil)
        ReadingListStore.shared.add(title: title, url: url, pdfData: nil, containerID: containerID)
        Toast.show("Saved to Reading List", from: self)
    }
}

/// Modal popup WebView for `window.open` / OAuth (Google GSI, Apple, etc.).
/// Must be created with the `WKWebViewConfiguration` from `createWebViewWith`
/// so `window.opener` and postMessage keep working.
final class AuthPopupViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    let popupWebView: WKWebView
    var onDismissed: (() -> Void)?
    private let closeBar = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let header = UIView()
    private var didLayOutWebView = false

    /// - Important: `webView` must already be created with WebKit's `createWebViewWith`
    ///   configuration and must already be in a UIWindow hierarchy before that delegate
    ///   returns — otherwise `window.opener` stays null and Google GSI hangs on
    ///   `/gsi/transform`.
    init(webView: WKWebView) {
        self.popupWebView = webView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.text = "Sign in"

        closeBar.setTitle("Done", for: .normal)
        closeBar.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        closeBar.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        closeBar.accessibilityLabel = "Done"

        view.addSubview(header)
        header.addSubview(titleLabel)
        header.addSubview(closeBar)

        header.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
        closeBar.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(72)
            make.trailing.lessThanOrEqualTo(closeBar.snp.leading).offset(-8)
        }
    }

    /// Move the already-created WebView into this sheet (do not recreate / reload it).
    func attachPopupWebViewIfNeeded() {
        guard !didLayOutWebView else { return }
        didLayOutWebView = true
        popupWebView.isHidden = false
        popupWebView.alpha = 1
        popupWebView.removeFromSuperview()
        view.addSubview(popupWebView)
        popupWebView.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        attachPopupWebViewIfNeeded()
    }

    func present(from host: UIViewController) {
        XSiteProbe.log("popup.present", [
            "url": popupWebView.url?.absoluteString ?? "pending",
            "pool": ObjectIdentifier(popupWebView.configuration.processPool).debugDescription,
            "hasSuperview": popupWebView.superview != nil
        ])
        host.present(self, animated: true)
    }

    @objc private func doneTapped() {
        XSiteProbe.log("popup.done", ["url": popupWebView.url?.absoluteString ?? "nil"])
        dismissPopup()
    }

    func dismissPopup() {
        let finish = { [weak self] in
            guard let self else { return }
            self.popupWebView.stopLoading()
            self.popupWebView.uiDelegate = nil
            self.popupWebView.navigationDelegate = nil
            self.popupWebView.removeFromSuperview()
            self.onDismissed?()
            self.onDismissed = nil
        }
        if presentingViewController != nil {
            dismiss(animated: true, completion: finish)
        } else {
            finish()
        }
    }

    // MARK: - WKUIDelegate

    func webViewDidClose(_ webView: WKWebView) {
        XSiteProbe.log("popup.webViewDidClose", ["url": webView.url?.absoluteString ?? "nil"])
        dismissPopup()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // This web view was not created with `configuration`. Returning it crashes
        // with "Returned WKWebView was not created with the given configuration."
        let nestedURL = navigationAction.request.url
        XSiteProbe.log("popup.nestedOpen", [
            "url": nestedURL?.absoluteString ?? "nil",
            "action": "loadExisting"
        ])
        if let nestedURL, WebViewController.canLoadInExistingPopup(nestedURL) {
            webView.load(URLRequest(url: nestedURL))
        }
        return nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme.hasPrefix("x-safari-") {
            XSiteProbe.log("popup.ignoreXSafari", ["url": url.absoluteString])
            decisionHandler(.cancel)
            return
        }
        let allowed = ["http", "https", "about", "blob", "data"]
        if !scheme.isEmpty && !allowed.contains(scheme) {
            XSiteProbe.log("popup.cancelScheme", ["url": url.absoluteString, "scheme": scheme])
            decisionHandler(.cancel)
            return
        }
        if XSiteProbe.isRelevant(url) {
            XSiteProbe.log("popup.nav", [
                "url": url.absoluteString,
                "main": navigationAction.targetFrame?.isMainFrame ?? true
            ])
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            titleLabel.text = title
        }
        let href = webView.url?.absoluteString ?? "nil"
        XSiteProbe.log("popup.finish", [
            "url": href,
            "title": titleLabel.text ?? ""
        ])
        webView.evaluateJavaScript(
            "(function(){return {opener:!!window.opener,href:location.href,bodyLen:(document.body&&document.body.innerText||'').length};})()"
        ) { result, _ in
            if let dict = result as? [String: Any] {
                XSiteProbe.log("popup.state", dict)
            }
        }

        // If GSI transform still has no opener, the page stays blank — close so the
        // user is not stuck (credential cannot be delivered without opener).
        if href.contains("/gsi/transform") {
            webView.evaluateJavaScript("(function(){return !!window.opener;})()") { [weak self] result, _ in
                let hasOpener = (result as? Bool) ?? false
                XSiteProbe.log("popup.transform", ["hasOpener": hasOpener])
                if !hasOpener {
                    // Give GSI a brief moment in case opener is assigned late.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.popupWebView.evaluateJavaScript("(function(){return !!window.opener;})()") { result, _ in
                            let ok = (result as? Bool) ?? false
                            XSiteProbe.log("popup.transform.retry", ["hasOpener": ok])
                        }
                    }
                }
            }
        }
    }
}
