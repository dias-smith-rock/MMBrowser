import UIKit
import SnapKit
import AVKit

final class BrowserViewController: UIViewController {
    let tabManager = TabManager()

    private let statusBarFill = UIView()
    private let contentClipView = UIView()
    private let contentContainer = UIView()
    private let adjacentTabPreview = UIImageView()
    private var preparedAdjacentTabOffset: Int?
    private let addressBar = AddressBarView()
    private let toolbar = BottomToolbarView()
    private let chromeHost = BrowserChromeView()
    private let chromeCard = UIView()
    private let chromeStack = UIStackView()
    /// Shown only while loading AND bottom chrome is collapsed.
    private let collapsedProgressView = UIProgressView(progressViewStyle: .bar)

    private var accountHubController: AccountHubViewController?
    private var privateNewTabController: PrivateNewTabViewController?
    private var currentContent: UIViewController?

    private var chromeBottomConstraint: Constraint?
    private var chromeHeightConstraint: Constraint?
    private var contentTopConstraint: Constraint?
    private var isChromeCollapsed = false
    /// Tab to restore when user taps Forward after a synthetic Back→Home.
    private var chromeReturnTabID: UUID?
    private var scrollAccumulator: CGFloat = 0
    private let chromeScrollThreshold: CGFloat = 10
    /// Blocks scroll→chrome feedback while we resize chrome or nudge `contentOffset`.
    private var isAdjustingChromeLayout = false
    /// Space Hub NTP hides the bottom address bar + toolbar entirely.
    private var isBrowserChromeHiddenForHub = false
    private var isPageLoading = false
    private var pageLoadProgress: Double = 0
    /// Keyboard overlap with this view (from bottom), in view coordinates.
    private var keyboardOverlap: CGFloat = 0

    private var didAttemptOnboarding = false
    /// Keeps sticky PiP advancing to the next video while JS timers are throttled in background.
    private var stickyPipBackgroundTimer: Timer?
    private var stickyPipBackgroundTask = UIBackgroundTaskIdentifier.invalid
    private var webViewRebuildWorkItem: DispatchWorkItem?
    private var contentRulesRefreshWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        tabManager.delegate = self
        setupChrome()
        showSelectedTab()
        NotificationCenter.default.addObserver(self, selector: #selector(trackerChanged), name: .trackerProtectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accurateBlockCountChanged), name: .accurateBlockCountChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(noImagesChanged), name: .noImagesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .shortsFocusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .youtubeAdShieldChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .mediaPlaybackSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contentRulesChanged), name: .filterManifestUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .locationPrivacyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClearOptionSessionCleanup), name: .clearOptionSessionCleanup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClearOptionSettingsChanged), name: .clearOptionSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pipProbeDumpTabs(_:)), name: PipProbe.dumpTabsNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadDidFinish(_:)), name: DownloadManager.didFinishNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openDownloadsFromNotification),
            name: DownloadLocalNotifications.openDownloadsNotification,
            object: nil
        )
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateWebChromeContentInset()
    }

    @objc private func downloadDidFinish(_ note: Notification) {
        guard UIApplication.shared.applicationState == .active else { return }
        guard let item = note.userInfo?["item"] as? DownloadItem else { return }
        switch item.status {
        case .completed:
            let isVideo = (item.mimeType?.lowercased().hasPrefix("video/") == true)
                || ["mp4", "mov", "m4v", "webm"].contains(
                    (item.fileName as NSString).pathExtension.lowercased()
                )
            if isVideo, FileManager.default.fileExists(atPath: item.fileURL.path) {
                Toast.show(
                    "Downloaded \(item.fileName)",
                    from: self,
                    actionTitle: "Play",
                    action: { [weak self] in
                        self?.playDownloadedFile(item)
                    },
                    duration: 4.5
                )
            } else {
                Toast.show("Downloaded \(item.fileName)", from: self)
            }
        case .failed:
            let detail = (item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown error"
            Toast.show("Download failed · \(detail)", from: self)
        default:
            break
        }
    }

    private var offlinePlayStatusObserver: NSKeyValueObservation?
    private var offlinePlayItem: AVPlayerItem?

    private func playDownloadedFile(_ item: DownloadItem) {
        var probe = PageMediaProbe.fileProbeSummary(at: item.fileURL)
        probe["file"] = item.fileName
        probe["mime"] = item.mimeType ?? ""
        probe["source"] = item.sourceURL
        PageMediaProbe.log("play.begin", probe)

        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            PageMediaProbe.log("play.fail", ["why": "missing", "file": item.fileName])
            Toast.show("File missing", from: self)
            return
        }
        let playerItem = AVPlayerItem(url: item.fileURL)
        offlinePlayItem = playerItem
        offlinePlayStatusObserver = playerItem.observe(\.status, options: [.initial, .new]) { item, _ in
            let name = (item.asset as? AVURLAsset)?.url.lastPathComponent ?? "?"
            switch item.status {
            case .readyToPlay:
                PageMediaProbe.log("play.ready", [
                    "file": name,
                    "duration": CMTimeGetSeconds(item.duration)
                ])
            case .failed:
                let err = item.error as NSError?
                PageMediaProbe.log("play.fail", [
                    "why": "avplayer",
                    "file": name,
                    "domain": err?.domain ?? "",
                    "code": err?.code ?? 0,
                    "error": err?.localizedDescription ?? "unknown"
                ])
            case .unknown:
                PageMediaProbe.log("play.status", ["status": "unknown", "file": name])
            @unknown default:
                PageMediaProbe.log("play.status", ["status": "other", "file": name])
            }
        }
        let player = AVPlayer(playerItem: playerItem)
        let controller = AVPlayerViewController()
        controller.player = player
        let presentPlayer = { [weak self] in
            guard let self else { return }
            self.present(controller, animated: true) {
                PageMediaProbe.log("play.presented", ["file": item.fileName])
                player.play()
            }
        }
        if presentedViewController != nil {
            dismiss(animated: false, completion: presentPlayer)
        } else {
            presentPlayer()
        }
    }

    @objc private func openDownloadsFromNotification() {
        if tabManager.selectedTab?.isIncognito == true {
            Toast.show("Downloads are disabled in Private Browsing", from: self)
            return
        }
        // Dismiss any presented sheets so Downloads can present cleanly.
        if presentedViewController != nil {
            dismiss(animated: false) { [weak self] in
                self?.openDownloads()
            }
        } else {
            openDownloads()
        }
    }

    @objc private func pipProbeDumpTabs(_ note: Notification) {
        let reason = (note.userInfo?["reason"] as? String) ?? "?"
        let rows: [[String: Any]] = tabManager.tabs.enumerated().map { idx, tab in
            [
                "i": idx,
                "host": tab.url?.host ?? (tab.isNewTabPage ? "ntp" : "?"),
                "incognito": tab.isIncognito,
                "selected": idx == tabManager.selectedIndex,
                "nativePip": tab.webController?.isPictureInPictureActive ?? false,
                "hasWeb": tab.webController != nil,
                "isMusic": YouTubeDarkMode.isYouTubeMusic(tab.url)
            ]
        }
        PipProbe.log("tabs.dump", [
            "reason": reason,
            "sticky": AppSettings.stickyPictureInPicture,
            "selected": tabManager.selectedIndex,
            "count": tabManager.tabs.count,
            "tabs": rows
        ])
    }

    @objc private func appDidEnterBackground() {
        let pipOwner = PipSession.owner
        let pipActive = (pipOwner?.isPictureInPictureActive == true)
            || tabManager.tabs.contains { $0.webController?.isPictureInPictureActive == true }

        // While system PiP owns audio, do not touch AVAudioSession or snapshot any WebView —
        // both cause a noticeable hitch in the floating video on suspend.
        if pipActive {
            startStickyPipBackgroundKeepAlive()
            // Persist already-captured previews only.
            if !AppSettings.closeAllTabsOnExit, AppSettings.showTabsPreviewImages {
                for tab in tabManager.tabs where !tab.isIncognito && !tab.isNewTabPage {
                    if let snapshot = tab.snapshot {
                        TabSnapshotStore.save(snapshot, for: tab.id)
                    }
                }
            }
            HistoryStore.shared.flush()
            tabManager.persistSessionIfNeeded(force: true)
            return
        }

        let tabsNeedingKeepAlive = tabManager.tabs.filter { $0.webController?.needsBackgroundMediaKeepAlive == true }
        if !tabsNeedingKeepAlive.isEmpty {
            for tab in tabsNeedingKeepAlive {
                MediaPlaybackSupport.keepBackgroundMediaAlive(in: tab.webController?.webView)
            }
        }

        // Refresh previews for live tabs so thumbnails survive relaunch.
        guard !AppSettings.closeAllTabsOnExit, AppSettings.showTabsPreviewImages else {
            HistoryStore.shared.flush()
            tabManager.persistSessionIfNeeded(force: true)
            return
        }
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "PersistTabSnapshots") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        let snapshotTabs = tabManager.tabs.filter { !$0.isIncognito && !$0.isNewTabPage }
        captureSnapshotsSerially(tabs: snapshotTabs, index: 0) { [weak self] in
            guard let self else { return }
            HistoryStore.shared.flush()
            self.tabManager.persistSessionIfNeeded(force: true)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
    }

    @objc private func appWillEnterForeground() {
        stopStickyPipBackgroundKeepAlive()
    }

    /// Native timer + background task so sticky PiP can hand off to the next video after `ended`
    /// (page `setTimeout` is heavily throttled while suspended).
    /// While PiP is healthy/playing, the page script no-ops — avoids play↔pause thrash.
    private func startStickyPipBackgroundKeepAlive() {
        stopStickyPipBackgroundKeepAlive()
        guard AppSettings.pictureInPictureEnabled, AppSettings.stickyPictureInPicture else { return }
        guard let owner = PipSession.owner, owner.webView != nil else { return }

        stickyPipBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "StickyPipNext") { [weak self] in
            self?.stopStickyPipBackgroundKeepAlive()
        }
        var ticks = 0
        // ≤ ~20s total; JS tick no-ops when PiP playback is already healthy.
        let timer = Timer(timeInterval: 3.5, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            ticks += 1
            guard ticks <= 6,
                  AppSettings.stickyPictureInPicture,
                  let owner = PipSession.owner else {
                self.stopStickyPipBackgroundKeepAlive()
                return
            }
            // Single reinforce path (no-ops when PiP is already playing).
            MediaPlaybackSupport.reinforcePictureInPictureIfNeeded(in: owner.webView)
        }
        stickyPipBackgroundTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopStickyPipBackgroundKeepAlive() {
        stickyPipBackgroundTimer?.invalidate()
        stickyPipBackgroundTimer = nil
        if stickyPipBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(stickyPipBackgroundTask)
            stickyPipBackgroundTask = .invalid
        }
    }

    @objc private func themeChanged() {
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        let isPrivate = tabManager.selectedTab?.isIncognito == true
        applyPrivateChrome(isPrivate)
        accountHubController?.reloadFromExternalChange()
        privateNewTabController?.applyTheme()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Keep the visible tab; reclaim everything else under the normal LRU caps.
        tabManager.evictExcessWebViews(protecting: tabManager.selectedTab)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAttemptOnboarding else { return }
        didAttemptOnboarding = true
        #if DEBUG
        presentOnboarding()
        #else
        if !AppSettings.didShowOnboarding {
            presentOnboarding()
        } else {
            AdLifecycleCoordinator.shared.noteHostReadyForConsent(from: self)
        }
        #endif
    }

    /// Called when entering background so tab/container state is on disk before cleanup.
    func persistSessionForBackground() {
        tabManager.persistSessionIfNeeded()
    }

    /// Opens an external `http`/`https` link (default-browser / universal open).
    func handleIncomingURL(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return }
        // Dismiss lightweight chrome that would block the new page.
        if presentedViewController is MenuViewController
            || presentedViewController is UIAlertController {
            presentedViewController?.dismiss(animated: false)
        }
        openURLInNewTab(url)
    }

    @objc private func handleClearOptionSessionCleanup() {
        guard AppSettings.closeAllTabsOnExit else { return }
        // Never dismiss first-run onboarding / other setup sheets on session cleanup.
        #if !DEBUG
        if !AppSettings.didShowOnboarding { return }
        #endif
        if presentedViewController is OnboardingViewController { return }
        presentedViewController?.dismiss(animated: false)
        tabManager.closeAllTabsAndReset()
        showSelectedTab()
        refreshToolbar()
    }

    @objc private func handleClearOptionSettingsChanged() {
        if !AppSettings.showTabsPreviewImages {
            tabManager.clearAllSnapshots()
        }
        // Keep persisting while browsing so crash recovery still works when
        // "Close All Tabs on Exit" is enabled; that option only clears on leave.
        tabManager.persistSessionIfNeeded()
    }

    @objc private func trackerChanged() {
        scheduleContentRulesRefresh()
    }

    @objc private func contentRulesChanged() {
        scheduleContentRulesRefresh()
    }

    @objc private func accurateBlockCountChanged() {
        scheduleFullWebViewRebuild()
    }

    @objc private func noImagesChanged() {
        // Image-block user script is baked at WebView creation; recreate after debounce.
        scheduleFullWebViewRebuild()
    }

    @objc private func rebuildWebViews() {
        scheduleFullWebViewRebuild()
    }

    /// Debounced destroy/recreate — needed when document-start scripts / handlers change.
    private func scheduleFullWebViewRebuild() {
        contentRulesRefreshWorkItem?.cancel()
        contentRulesRefreshWorkItem = nil
        webViewRebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.webViewRebuildWorkItem = nil
            self.tabManager.invalidateAllWebViews()
            self.showSelectedTab()
        }
        webViewRebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Debounced hot-swap of WK content rule lists + reload live tabs (no WebView destroy).
    private func scheduleContentRulesRefresh() {
        guard webViewRebuildWorkItem == nil else { return }
        contentRulesRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.contentRulesRefreshWorkItem = nil
            let webs = self.tabManager.liveWebViews
            guard !webs.isEmpty else {
                self.addressBar.setBlockCount(0)
                return
            }
            AdBlockManager.shared.refreshContentRuleLists(on: webs) { [weak self] in
                guard let self else { return }
                self.addressBar.setBlockCount(0)
                self.tabManager.reloadLiveWebViews()
            }
        }
        contentRulesRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func presentOnboarding() {
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .fullScreen
        onboarding.onFinished = { [weak self, weak onboarding] in
            onboarding?.dismiss(animated: true) {
                self?.maybeShowAddressBarSwipeTip()
                if self?.maybeShowAccountWow() != true {
                    AdLifecycleCoordinator.shared.noteHostReadyForConsent(from: self)
                }
            }
            self?.accountHubController?.reloadFromExternalChange()
        }
        present(onboarding, animated: true)
    }

    @discardableResult
    private func maybeShowAccountWow() -> Bool {
        guard !UserDefaults.standard.bool(forKey: ContainerScope.didShowAccountWowKey) else {
            maybeShowAccountChipTip()
            return false
        }
        let wow = AccountOnboardingWowViewController(tabManager: tabManager)
        wow.onFinished = { [weak self, weak wow] in
            wow?.dismiss(animated: true) {
                self?.maybeShowAccountChipTip()
            }
            AdLifecycleCoordinator.shared.noteHostReadyForConsent(from: self)
        }
        wow.onStartedSplitDemo = { [weak self] in
            // Split View dismisses the modal chain; tip not needed after a live demo.
            UserDefaults.standard.set(false, forKey: ContainerScope.needsAccountChipTipKey)
            self?.refreshAccountChip()
            AdLifecycleCoordinator.shared.noteHostReadyForConsent(from: self)
        }
        present(wow, animated: true)
        return true
    }

    private func maybeShowAccountChipTip() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ContainerScope.needsAccountChipTipKey),
              !defaults.bool(forKey: ContainerScope.didShowAccountChipTipKey) else { return }
        defaults.set(true, forKey: ContainerScope.didShowAccountChipTipKey)
        defaults.set(false, forKey: ContainerScope.needsAccountChipTipKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            Toast.show("Tap the space chip to switch identities — long-press for the previous space", from: self)
        }
    }

    func presentDualAccountCompare(leftID: UUID? = nil, rightID: UUID? = nil) {
        let containers = tabManager.sortedContainers
        guard containers.count >= 2 else {
            Toast.show("Add another space first", from: self)
            return
        }

        let currentID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        let left = containers.first(where: { $0.id == leftID })
            ?? containers.first(where: { $0.id == currentID })
            ?? containers[0]
        let right = containers.first(where: { $0.id == rightID && $0.id != left.id })
            ?? containers.first(where: { $0.id != left.id })
            ?? containers[1]

        let url: URL = {
            if let selected = tabManager.selectedTab, !selected.isIncognito, let page = selected.url {
                return page
            }
            return URL(string: "https://www.google.com")!
        }()
        let compare = DualAccountCompareViewController(
            tabManager: tabManager,
            leftContainer: left,
            rightContainer: right,
            url: url
        )
        compare.delegate = self
        compare.modalPresentationStyle = .fullScreen
        present(compare, animated: true)
    }

    private func setupChrome() {
        contentClipView.backgroundColor = BrowserTheme.background
        contentClipView.clipsToBounds = true
        contentContainer.backgroundColor = BrowserTheme.background
        adjacentTabPreview.contentMode = .scaleAspectFill
        adjacentTabPreview.clipsToBounds = true
        adjacentTabPreview.isHidden = true
        addressBar.delegate = self
        toolbar.delegate = self

        chromeStack.axis = .vertical
        chromeStack.alignment = .fill
        chromeStack.spacing = 4
        chromeStack.addArrangedSubview(addressBar)
        chromeStack.addArrangedSubview(toolbar)

        chromeCard.backgroundColor = BrowserTheme.spaceElevatedColor(spaceColor: nil)
        chromeCard.layer.cornerRadius = 28
        chromeCard.layer.cornerCurve = .continuous
        chromeCard.clipsToBounds = true
        chromeCard.addSubview(chromeStack)

        chromeHost.backgroundColor = .clear
        chromeHost.clipsToBounds = false
        chromeHost.addSubview(chromeCard)

        statusBarFill.backgroundColor = BrowserTheme.background
        view.addSubview(statusBarFill)
        view.addSubview(contentClipView)
        contentClipView.addSubview(contentContainer)
        contentClipView.addSubview(adjacentTabPreview)
        view.addSubview(chromeHost)
        view.addSubview(collapsedProgressView)

        collapsedProgressView.progressTintColor = BrowserTheme.chromeBlue
        collapsedProgressView.trackTintColor = .clear
        collapsedProgressView.isHidden = true
        collapsedProgressView.progress = 0

        addressBar.snp.makeConstraints { make in
            make.height.equalTo(BrowserTheme.addressBarHeight)
        }
        toolbar.snp.makeConstraints { make in
            make.height.equalTo(BrowserTheme.toolbarHeight)
        }
        statusBarFill.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top)
        }
        chromeHost.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            chromeHeightConstraint = make.height.equalTo(BrowserTheme.chromeHeight).constraint
            chromeBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).constraint
        }
        chromeCard.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(BrowserTheme.chromeCardInset)
            make.top.bottom.equalToSuperview()
        }
        chromeStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 8, bottom: 6, right: 8))
        }
        contentClipView.snp.makeConstraints { make in
            contentTopConstraint = make.top.equalTo(view.safeAreaLayoutGuide.snp.top).constraint
            make.leading.trailing.equalToSuperview()
            // Full-bleed to the physical bottom so the home-indicator band stays transparent.
            make.bottom.equalToSuperview()
        }
        contentContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        adjacentTabPreview.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        collapsedProgressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(2)
        }
    }

    /// Scroll-down: shrink address into a bottom domain pill and hide the toolbar.
    /// Scroll-up / tap pill: restore the full chrome card.
    private func setChromeCollapsed(_ collapsed: Bool, animated: Bool) {
        if collapsed {
            guard tabManager.selectedTab?.isNewTabPage != true else { return }
            guard !isBrowserChromeHiddenForHub else { return }
            guard !addressBar.isHidden else { return }
            // Don't collapse chrome while the keyboard is up — address field would stay covered.
            guard keyboardOverlap < 1 else { return }
            // Cleaner mode stays in the capsule chrome — never dismiss it on collapse.
            if tabManager.selectedTab?.webController?.isPageCleanerActive != true {
                addressBar.hideCleanerMenu()
            }
        }
        guard !isBrowserChromeHiddenForHub else { return }
        guard collapsed != isChromeCollapsed else { return }

        let heightBefore = tabManager.selectedTab?.webController?.webView?.bounds.height ?? 0

        isChromeCollapsed = collapsed
        isAdjustingChromeLayout = true
        applyCompactChromeLayout(collapsed)
        updateChromeBottomOffset(animated: false)

        let animations = {
            self.view.layoutIfNeeded()
            self.compensateWebScrollForChromeHeightChange(heightBefore: heightBefore)
        }
        let finish = {
            // Defer clearing so any same-turn scroll KVO still sees the suppress flag.
            DispatchQueue.main.async {
                self.isAdjustingChromeLayout = false
                self.scrollAccumulator = 0
            }
        }
        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: animations,
                completion: { _ in finish() }
            )
        } else {
            animations()
            finish()
        }
        // Keep only one progress UI: address bar when expanded, thin bar when compact.
        addressBar.setProgress(pageLoadProgress, isLoading: isPageLoading && !collapsed)
        updateCollapsedProgressVisibility()
        updateWebChromeContentInset()
        setNeedsStatusBarAppearanceUpdate()
    }

    private func applyCompactChromeLayout(_ compact: Bool) {
        let host = Self.compactHostDisplay(
            for: tabManager.selectedTab?.url ?? tabManager.selectedTab?.webController?.webView?.url
        )
        let cleanerOn = tabManager.selectedTab?.webController?.isPageCleanerActive == true
            || addressBar.cleanerMenuExtraHeight > 0
        let cleanerExtra = addressBar.cleanerMenuExtraHeight
        let pillWidth = compactChromeWidth(for: host)
        // Cleaner mode keeps the capsule pill, with the chip bar above it (full-width host).
        addressBar.setCompact(compact, host: host, pillWidth: (compact && cleanerOn) ? pillWidth : nil)
        toolbar.isHidden = compact
        toolbar.alpha = compact ? 0 : 1

        chromeHeightConstraint?.update(
            offset: (compact ? BrowserTheme.chromeCompactHeight : BrowserTheme.chromeHeight) + cleanerExtra
        )
        addressBar.snp.updateConstraints { make in
            make.height.equalTo(
                (compact ? BrowserTheme.chromeCompactPillHeight : BrowserTheme.addressBarHeight) + cleanerExtra
            )
        }

        let cleanerCapsule = compact && cleanerOn
        chromeCard.backgroundColor = compact
            ? .clear
            : chromeCardFillColor()
        chromeCard.layer.cornerRadius = compact ? 0 : 28
        // Allow the compact pill / cleaner chips to draw outside the card.
        chromeCard.clipsToBounds = !compact

        chromeCard.snp.remakeConstraints { make in
            make.top.bottom.equalToSuperview()
            if compact && !cleanerCapsule {
                make.centerX.equalToSuperview()
                make.width.equalTo(pillWidth)
            } else {
                make.leading.trailing.equalToSuperview().inset(BrowserTheme.chromeCardInset)
            }
        }
        chromeStack.snp.remakeConstraints { make in
            if compact {
                make.edges.equalToSuperview()
            } else {
                make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 8, bottom: 6, right: 8))
            }
        }
        if compact {
            view.bringSubviewToFront(chromeHost)
        }
    }

    /// Menu / tools entry: select This site, collapse to capsule, stay until Exit.
    private func enterWebCleanerMode() {
        guard let web = tabManager.selectedTab?.webController else {
            Toast.show("No page to clean", from: self)
            return
        }
        web.enterPageCleaner(urlOnly: false)
        guard web.isPageCleanerActive else { return }
        addressBar.enterCleanerMode(urlOnly: false)
        if isChromeCollapsed {
            applyCompactChromeLayout(true)
            updateChromeBottomOffset(animated: false)
            updateWebChromeContentInset()
            UIView.animate(withDuration: 0.22) { self.view.layoutIfNeeded() }
        } else {
            setChromeCollapsed(true, animated: true)
        }
    }

    private func compactChromeWidth(for host: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 15, weight: .medium)
        let textW = ceil((host as NSString).size(withAttributes: [.font: font]).width)
        let width = textW + 64
        let maxW = max(view.bounds.width - 72, 160)
        return min(max(width, 148), maxW)
    }

    private static func compactHostDisplay(for url: URL?) -> String {
        guard let host = url?.host, !host.isEmpty else { return "Search" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// When bottom chrome shows, the web view shrinks from the bottom. Without adjusting
    /// `contentOffset`, the last screenful of the page stays behind the address bar.
    private func compensateWebScrollForChromeHeightChange(heightBefore: CGFloat) {
        guard let webView = tabManager.selectedTab?.webController?.webView,
              heightBefore > 1 else { return }
        let heightAfter = webView.bounds.height
        let delta = heightBefore - heightAfter
        // Only when chrome expands (webview shrinks). Collapsing during a scroll gesture
        // already reveals more content; adjusting there fights the user's finger.
        guard delta > 0.5 else { return }

        let scrollView = webView.scrollView
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(
            minY,
            scrollView.contentSize.height - scrollView.bounds.height + inset.bottom
        )
        var offset = scrollView.contentOffset
        let nextY = min(max(offset.y + delta, minY), maxY)
        guard abs(nextY - offset.y) > 0.5 else { return }
        offset.y = nextY
        // Setting contentOffset while the user is still dragging re-enters didScroll and
        // would flip chrome hide↔show forever — keep isAdjustingChromeLayout set by caller.
        scrollView.contentOffset = offset
    }

    /// Places chrome above the home indicator, or above the keyboard when it overlaps.
    /// When compact, the domain pill sits near the physical bottom of the screen.
    private func updateChromeBottomOffset(animated: Bool) {
        guard !isBrowserChromeHiddenForHub else { return }
        let safeBottom = view.safeAreaInsets.bottom
        let liftAboveSafeArea = max(0, keyboardOverlap - safeBottom)
        let offset: CGFloat
        if liftAboveSafeArea > 0 {
            offset = -liftAboveSafeArea
        } else if isChromeCollapsed {
            // Move down into the home-indicator band so the pill floats at screen bottom.
            offset = max(0, safeBottom - 10)
        } else {
            offset = 0
        }
        chromeBottomConstraint?.update(offset: offset)
        // Keep collapsed progress just above the compact pill / home indicator.
        collapsedProgressView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(2)
            if liftAboveSafeArea > 0 {
                make.bottom.equalTo(chromeHost.snp.top)
            } else if isChromeCollapsed {
                make.bottom.equalTo(chromeHost.snp.top).offset(-2)
            } else {
                make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            }
        }

        guard animated else { return }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
            animations: { self.view.layoutIfNeeded() }
        )
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        // Ignore tiny changes / floating keyboard fully off the bottom.
        keyboardOverlap = overlap > 20 ? overlap : 0
        if keyboardOverlap > 0 {
            isChromeCollapsed = false
            statusBarFill.alpha = 1
            contentTopConstraint?.deactivate()
            contentClipView.snp.prepareConstraints { make in
                contentTopConstraint = make.top.equalTo(view.safeAreaLayoutGuide.snp.top).constraint
            }
            contentTopConstraint?.activate()
            updateCollapsedProgressVisibility()
        }
        animateChromeWithKeyboard(notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardOverlap = 0
        animateChromeWithKeyboard(notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.tabManager.selectedTab?.webController?.repairBilibiliStickyPlayerIfNeeded()
        }
    }

    private func animateChromeWithKeyboard(_ notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16).union(.beginFromCurrentState)
        let heightBefore = tabManager.selectedTab?.webController?.webView?.bounds.height ?? 0
        isAdjustingChromeLayout = true
        updateChromeBottomOffset(animated: false)
        UIView.animate(withDuration: duration, delay: 0, options: options, animations: {
            self.view.layoutIfNeeded()
            self.compensateWebScrollForChromeHeightChange(heightBefore: heightBefore)
        }, completion: { _ in
            DispatchQueue.main.async {
                self.isAdjustingChromeLayout = false
                self.scrollAccumulator = 0
            }
        })
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // Content stays below the status bar fill even when chrome is collapsed.
        .default
    }

    private func updateCollapsedProgressVisibility() {
        let shouldShow = isChromeCollapsed && isPageLoading && !(tabManager.selectedTab?.isNewTabPage ?? true)
        collapsedProgressView.isHidden = !shouldShow
        if shouldShow {
            collapsedProgressView.setProgress(Float(pageLoadProgress), animated: true)
            view.bringSubviewToFront(collapsedProgressView)
        } else if !isPageLoading {
            collapsedProgressView.setProgress(0, animated: false)
        }
    }

    private func applyLoadingProgress(_ progress: Double, isLoading: Bool) {
        // WKWebView often keeps isLoading=true after estimatedProgress hits 1.0;
        // never keep the bar visible once progress is complete.
        let activelyLoading = isLoading && progress < 1
        isPageLoading = activelyLoading
        pageLoadProgress = progress
        addressBar.setProgress(progress, isLoading: activelyLoading && !isChromeCollapsed)
        if activelyLoading {
            collapsedProgressView.setProgress(Float(max(progress, 0.02)), animated: true)
        } else {
            collapsedProgressView.setProgress(0, animated: false)
        }
        updateCollapsedProgressVisibility()
    }

    private func resetChromeForCurrentTab() {
        scrollAccumulator = 0
        setChromeCollapsed(false, animated: false)
        applyLoadingProgress(0, isLoading: false)
    }

    /// Hides address bar + toolbar for Space Hub; restores them for web / private NTP.
    private func setBrowserChromeHiddenForHub(_ hidden: Bool) {
        guard hidden != isBrowserChromeHiddenForHub else { return }
        isBrowserChromeHiddenForHub = hidden
        chromeHost.isHidden = hidden
        chromeHost.isUserInteractionEnabled = !hidden
        addressBar.isHidden = hidden
        if !hidden {
            isChromeCollapsed = false
            updateChromeBottomOffset(animated: false)
        }
        contentClipView.snp.remakeConstraints { make in
            contentTopConstraint = make.top.equalTo(view.safeAreaLayoutGuide.snp.top).constraint
            make.leading.trailing.equalToSuperview()
            make.bottom.equalToSuperview()
        }
        updateWebChromeContentInset()
        view.layoutIfNeeded()
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Keep page content scrollable above the floating chrome; page paints through the home-indicator band.
    private func updateWebChromeContentInset() {
        let safeBottom = view.safeAreaInsets.bottom
        let chromeBottom: CGFloat
        if isBrowserChromeHiddenForHub || chromeHost.isHidden {
            chromeBottom = 0
        } else if isChromeCollapsed {
            // Pill floats in/near the home-indicator band — don't double-count safe area.
            chromeBottom = BrowserTheme.chromeCompactHeight
        } else {
            chromeBottom = BrowserTheme.chromeHeight
        }
        // WebView reaches the physical bottom; expanded chrome also clears the home indicator.
        let bottom = isChromeCollapsed ? chromeBottom : (chromeBottom + safeBottom)
        for tab in tabManager.tabs {
            guard let scrollView = tab.webController?.webView?.scrollView else { continue }
            var inset = scrollView.contentInset
            var indicator = scrollView.verticalScrollIndicatorInsets
            guard abs(inset.bottom - bottom) > 0.5 || abs(indicator.bottom - bottom) > 0.5 else { continue }
            inset.bottom = bottom
            indicator.bottom = bottom
            scrollView.contentInset = inset
            scrollView.verticalScrollIndicatorInsets = indicator
        }
        // Account hub content sits above the floating chrome (system safe area already
        // excludes the home indicator).
        accountHubController?.additionalSafeAreaInsets.bottom =
            (isBrowserChromeHiddenForHub || chromeHost.isHidden) ? 0 : BrowserTheme.chromeHeight
    }

    private func showSelectedTab() {
        guard let tab = tabManager.selectedTab else { return }
        // Keep a preview of the tab we're leaving so the switcher isn't blank.
        if AppSettings.showTabsPreviewImages,
           let currentWeb = currentContent as? WebViewController,
           let outgoing = tabManager.tabs.first(where: { $0.webController === currentWeb }),
           outgoing.id != tab.id,
           !outgoing.isNewTabPage {
            captureSnapshot(for: outgoing, completion: nil)
        }
        // Drop synthetic Forward→page if the user switched to some other real tab.
        if let returnID = chromeReturnTabID, !tab.isNewTabPage, tab.id != returnID {
            chromeReturnTabID = nil
        }
        applyPrivateChrome(tab.isIncognito)
        resetChromeForCurrentTab()
        refreshAccountChip()
        if tab.isNewTabPage {
            if tab.isIncognito {
                showPrivateNewTab()
            } else {
                showNewTab(for: tab)
            }
            // NTP has no WebView; still reclaim others under the global/account caps.
            tabManager.evictExcessWebViews(protecting: tab)
        } else {
            showWeb(for: tab)
        }
        refreshToolbar()
        updateWebChromeContentInset()
    }

    private func refreshAccountChip() {
        guard let tab = tabManager.selectedTab else {
            toolbar.setAccount(name: "", color: .clear, visible: false)
            applyPrivateChrome(false)
            return
        }
        if tab.isIncognito {
            toolbar.setAccount(name: "", color: .clear, visible: false)
            applyPrivateChrome(true)
            return
        }
        let container = tabManager.container(id: tab.containerID) ?? tabManager.defaultContainer
        toolbar.setAccount(
            name: container.name,
            color: AccountColor.color(for: container),
            visible: true
        )
        applyPrivateChrome(false)
    }

    /// Switch space and show a strong, hard-to-miss identity change.
    private func switchToAccountWithFeedback(_ id: UUID, subtitle: String? = nil) {
        guard let container = tabManager.container(id: id) else { return }
        _ = tabManager.switchToAccount(id)
        showSelectedTab()
        refreshAccountChip()
        toolbar.pulseAccountChip()
        AppAnalytics.logAccountSwitch(accountName: container.name)
        let color = AccountColor.color(for: container)
        let detail = subtitle
            ?? "Cookies, history, bookmarks & home stay with this space"
        presentAccountSwitchBanner(name: container.name, detail: detail, color: color)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flashChrome(with: color)
    }

    private func presentAccountSwitchBanner(name: String, detail: String, color: UIColor) {
        view.subviews.filter { $0.tag == 9_401_122 }.forEach { $0.removeFromSuperview() }

        let banner = UIView()
        banner.tag = 9_401_122
        banner.backgroundColor = BrowserTheme.elevated
        banner.layer.cornerRadius = 14
        banner.layer.borderWidth = 1.5
        banner.layer.borderColor = color.cgColor
        banner.clipsToBounds = true
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: -12)

        let dot = UIView()
        dot.backgroundColor = color
        dot.layer.cornerRadius = 5

        let title = UILabel()
        title.text = "Now browsing as \(name)"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = BrowserTheme.textPrimary
        title.numberOfLines = 1

        let body = UILabel()
        body.text = detail
        body.font = .systemFont(ofSize: 13)
        body.textColor = BrowserTheme.textSecondary
        body.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [title, body])
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [dot, textStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        banner.addSubview(row)
        view.addSubview(banner)

        dot.snp.makeConstraints { $0.size.equalTo(10) }
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        }
        banner.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(10)
            make.leading.trailing.equalToSuperview().inset(16)
        }

        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
            banner.alpha = 1
            banner.transform = .identity
        }
        UIView.animate(withDuration: 0.35, delay: 2.2, options: .curveEaseIn) {
            banner.alpha = 0
            banner.transform = CGAffineTransform(translationX: 0, y: -8)
        } completion: { _ in
            banner.removeFromSuperview()
        }
    }

    private func flashChrome(with color: UIColor) {
        let flash = UIView()
        flash.backgroundColor = color.withAlphaComponent(0.2)
        flash.isUserInteractionEnabled = false
        flash.alpha = 0
        view.addSubview(flash)
        flash.snp.makeConstraints { $0.edges.equalToSuperview() }
        UIView.animate(withDuration: 0.15, animations: {
            flash.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.45, animations: {
                flash.alpha = 0
            }, completion: { _ in
                flash.removeFromSuperview()
            })
        })
    }

    private func presentAccountHub() {
        setChromeCollapsed(false, animated: false)
        view.layoutIfNeeded()

        let previewID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.defaultContainer.id
        let hub = AccountHubViewController(
            tabManager: tabManager,
            previewAccountID: previewID,
            isOverlay: true
        )
        hub.delegate = self
        hub.modalPresentationStyle = .overFullScreen
        hub.modalTransitionStyle = .coverVertical
        present(hub, animated: true) { [weak self] in
            guard let self else { return }
            if self.tabManager.selectedTab?.webController?.isPictureInPictureActive != true {
                MediaPlaybackSupport.resumeMediaIfNeeded(in: self.tabManager.selectedTab?.webController?.webView)
            }
        }
    }

    private func presentAccountSwitcher() {
        presentAccountHub()
    }

    private func presentAccountManager(from presenter: UIViewController? = nil) {
        let vc = ContainerManageViewController(tabManager: tabManager)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        // Prefer the requester (e.g. overlay Space Hub) so we don't fail when BVC
        // is already presenting another modal.
        let host = presenter
            ?? presentedViewController
            ?? self
        host.present(nav, animated: true)
    }

    private func presentAddAccount() {
        let edit = ContainerEditViewController(
            container: nil,
            tabManager: tabManager,
            suggestedPresetIndex: tabManager.containers.count
        )
        edit.delegate = self
        let nav = UINavigationController(rootViewController: edit)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func applyPrivateChrome(_ isPrivate: Bool) {
        let spaceColor: UIColor? = {
            guard !isPrivate,
                  let tab = tabManager.selectedTab,
                  !tab.isIncognito else { return nil }
            let container = tabManager.container(id: tab.containerID) ?? tabManager.defaultContainer
            return AccountColor.color(for: container)
        }()
        let onHome = !isPrivate && tabManager.selectedTab?.isNewTabPage == true
        let bg = isPrivate
            ? BrowserTheme.privateBackground
            : (onHome
                ? BrowserTheme.spaceHomeColor(spaceColor: spaceColor)
                : BrowserTheme.spaceSurfaceColor(spaceColor: spaceColor))
        view.backgroundColor = bg
        statusBarFill.backgroundColor = bg
        contentClipView.backgroundColor = bg
        contentContainer.backgroundColor = bg
        chromeHost.backgroundColor = .clear
        // Shared floating card (same on home and web). Home-indicator band stays clear of this fill.
        if !isChromeCollapsed {
            chromeCard.backgroundColor = chromeCardFillColor(isPrivate: isPrivate, spaceColor: spaceColor)
        }
        addressBar.setPrivateMode(isPrivate)
        toolbar.setPrivateMode(isPrivate)
        if isPrivate {
            addressBar.setSpaceChrome(nil)
            toolbar.setSpaceChrome(nil)
            collapsedProgressView.progressTintColor = BrowserTheme.privateAccent
        } else {
            addressBar.setSpaceChrome(spaceColor)
            toolbar.setSpaceChrome(spaceColor)
            collapsedProgressView.progressTintColor = spaceColor ?? BrowserTheme.chromeBlue
        }
        accountHubController?.applySpaceChrome(spaceColor: spaceColor)
    }

    /// Floating address+toolbar card fill — Space accent when not Private.
    private func chromeCardFillColor(
        isPrivate: Bool? = nil,
        spaceColor: UIColor? = nil
    ) -> UIColor {
        let priv = isPrivate ?? (tabManager.selectedTab?.isIncognito == true)
        if priv { return BrowserTheme.privateElevated }
        let tint = spaceColor ?? {
            guard let tab = tabManager.selectedTab, !tab.isIncognito else { return nil }
            let container = tabManager.container(id: tab.containerID) ?? tabManager.defaultContainer
            return AccountColor.color(for: container)
        }()
        return BrowserTheme.spaceElevatedColor(spaceColor: tint)
    }

    private func showNewTab(for tab: BrowserTab) {
        // Keep address bar + toolbar visible so home matches the simple Favorites layout.
        setBrowserChromeHiddenForHub(false)
        let hub: AccountHubViewController
        if let existing = accountHubController {
            hub = existing
            hub.updatePreviewAccount(tab.containerID)
        } else {
            hub = AccountHubViewController(
                tabManager: tabManager,
                previewAccountID: tab.containerID,
                isOverlay: false
            )
            hub.delegate = self
            accountHubController = hub
        }
        embed(hub)
        addressBar.setURLText("")
        addressBar.setProgress(0, isLoading: false)
        refreshToolbar()
    }

    private func showPrivateNewTab() {
        setBrowserChromeHiddenForHub(false)
        let ntp: PrivateNewTabViewController
        if let existing = privateNewTabController {
            ntp = existing
        } else {
            ntp = PrivateNewTabViewController()
            ntp.delegate = self
            privateNewTabController = ntp
        }
        embed(ntp)
        addressBar.setURLText("")
        addressBar.setProgress(0, isLoading: false)
    }

    private func makeWebController(for tab: BrowserTab) -> WebViewController {
        if tab.isIncognito {
            return WebViewController(
                isIncognito: true,
                geoConfiguration: .fromAppSettings(),
                tabUserAgentSettings: tab.userAgentSettings
            )
        }
        let container = tabManager.container(id: tab.containerID) ?? tabManager.defaultContainer
        return WebViewController(
            isIncognito: false,
            websiteDataStore: TabSessionStore.dataStore(for: tabManager.sessionID(for: tab)),
            geoConfiguration: .from(container: container),
            identityProfile: container.identity,
            tabUserAgentSettings: tab.userAgentSettings,
            containerID: container.id
        )
    }

    private func embed(_ child: UIViewController) {
        if currentContent === child, child.view.superview === contentContainer { return }
        if currentContent === child {
            contentContainer.addSubview(child.view)
            child.view.snp.remakeConstraints { make in make.edges.equalToSuperview() }
            return
        }
        if let current = currentContent {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(child)
        contentContainer.addSubview(child.view)
        child.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        child.didMove(toParent: self)
        currentContent = child
    }

    /// Lets Split View take ownership of a tab's live WebView without destroying its session.
    func detachEmbeddedIfNeeded(_ child: UIViewController) {
        if currentContent === child {
            currentContent = nil
        }
        guard child.parent === self else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }

    private func navigate(to url: URL, in tab: BrowserTab? = nil) {
        guard let tab = tab ?? tabManager.selectedTab else { return }
        chromeReturnTabID = nil
        tab.isNewTabPage = false
        tab.url = url
        tab.title = url.host ?? "Untitled"
        tab.lastAccessed = Date()
        setBrowserChromeHiddenForHub(false)
        addressBar.setURLText(Self.addressBarDisplayText(for: url))

        let web: WebViewController
        if let existing = tab.webController {
            web = existing
            configureWebController(web, for: tab)
        } else {
            web = makeWebController(for: tab)
            configureWebController(web, for: tab)
            tab.webController = web
        }
        embed(web)
        web.load(url: url)
        tabManager.evictExcessWebViews(protecting: tab)
        refreshToolbar()
        accountHubController?.reloadFromExternalChange()
        tabManager.persistSessionIfNeeded()
    }

    /// Full page URL for the address bar (empty for about: pages / missing URL).
    private static func addressBarDisplayText(for url: URL?) -> String {
        guard let url else { return "" }
        let text = url.absoluteString
        if text.hasPrefix("about:") { return "" }
        return text
    }

    /// Opens `url` in a new tab in the given / parent / currently selected container session.
    private func openURLInNewTab(
        _ url: URL,
        incognito: Bool = false,
        inheritContainerFrom parent: BrowserTab? = nil,
        containerID: UUID? = nil
    ) {
        let resolvedContainerID: UUID? = {
            guard !incognito else { return nil }
            if let containerID { return containerID }
            if let parent, !parent.isIncognito { return parent.containerID }
            if let selected = tabManager.selectedTab, !selected.isIncognito {
                return selected.containerID
            }
            return nil
        }()
        let parentForUA = parent
            ?? (incognito ? tabManager.selectedTab.flatMap { $0.isIncognito ? $0 : nil } : nil)
        let tab = tabManager.addTab(
            incognito: incognito,
            select: true,
            containerID: resolvedContainerID,
            inheritUserAgentFrom: parentForUA
        )
        XSiteProbe.log("browser.openURLInNewTab", [
            "url": url.absoluteString,
            "incognito": incognito,
            "tabID": tab.id.uuidString
        ])
        navigate(to: url, in: tab)
    }

    func refreshToolbar() {
        let tab = tabManager.selectedTab
        let web = tab?.webController
        let isPrivate = tab?.isIncognito ?? false
        let isNTP = tab?.isNewTabPage == true
        let webCanGoBack = web?.canGoBack ?? false
        let webCanGoForward = web?.canGoForward ?? false
        // After Back→Home, keep Forward available to restore the previous tab.
        let hasHomeReturn = chromeReturnTabID != nil && isNTP
        let canGoForward = webCanGoForward || hasHomeReturn
        // Back works for web history, or to leave a page for Home when history is empty.
        let backActionable = webCanGoBack || (!isNTP && tab?.url != nil)
        toolbar.update(
            canGoBack: webCanGoBack,
            canGoForward: canGoForward,
            tabCount: tabManager.toolbarTabCount(incognito: isPrivate),
            isPrivate: isPrivate,
            backActionable: backActionable
        )
        addressBar.updateNavigation(
            canGoBack: webCanGoBack,
            canGoForward: webCanGoForward,
            visible: false
        )
        addressBar.setPageCleanerActive(tabManager.selectedTab?.webController?.isPageCleanerActive == true)
        maybeShowAddressBarSwipeTip()
    }

    /// Opens / selects the Home (NTP) tab without clearing a pending Forward→page return.
    private func openHomeTabPreservingReturn() {
        if tabManager.selectedTab?.isNewTabPage == true, tabManager.selectedTab?.isIncognito != true {
            refreshToolbar()
            return
        }
        let containerID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
        if let existing = tabManager.tabs.first(where: {
            !$0.isIncognito && $0.isNewTabPage && $0.containerID == containerID
        }) {
            tabManager.selectTab(id: existing.id)
        } else {
            _ = tabManager.addTab(incognito: false, select: true, containerID: containerID)
        }
        showSelectedTab()
    }

    private weak var addressBarSwipeTip: AddressBarSwipeTipView?

    private func maybeShowAddressBarSwipeTip() {
        guard addressBarSwipeTip == nil else { return }
        guard !AppSettings.didShowAddressBarSwipeTip else { return }
        guard presentedViewController == nil else { return }
        guard !addressBar.isHidden, addressBar.window != nil else { return }
        let isPrivate = tabManager.selectedTab?.isIncognito ?? false
        guard tabManager.toolbarTabCount(incognito: isPrivate) > 1 else { return }

        // Wait a beat so chrome finishes layout after opening a second tab.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self else { return }
            guard self.addressBarSwipeTip == nil else { return }
            guard !AppSettings.didShowAddressBarSwipeTip else { return }
            guard self.presentedViewController == nil else { return }
            guard !self.addressBar.isHidden, self.addressBar.superview != nil else { return }
            let isPrivate = self.tabManager.selectedTab?.isIncognito ?? false
            guard self.tabManager.toolbarTabCount(incognito: isPrivate) > 1 else { return }

            self.addressBarSwipeTip = AddressBarSwipeTipView.present(in: self.view, anchoring: self.addressBar) { [weak self] in
                self?.markAddressBarSwipeTipSeen()
            }
            AppAnalytics.logEvent("tip_address_bar_swipe_shown")
        }
    }

    private func markAddressBarSwipeTipSeen() {
        guard !AppSettings.didShowAddressBarSwipeTip || addressBarSwipeTip != nil else { return }
        AppSettings.didShowAddressBarSwipeTip = true
        if let tip = addressBarSwipeTip {
            addressBarSwipeTip = nil
            tip.removeFromSuperview()
        }
    }

    private func configureWebController(_ web: WebViewController, for tab: BrowserTab? = nil) {
        web.delegate = self
        if let tab {
            web.navigationHistory = tab.navigationHistory
        }
        web.onPageCleanerActiveChanged = { [weak self, weak web] active in
            guard let self = self, let web = web else { return }
            guard self.tabManager.selectedTab?.webController === web else { return }
            self.addressBar.setPageCleanerActive(active)
        }
    }

    private func showWeb(for tab: BrowserTab) {
        setBrowserChromeHiddenForHub(false)
        let web: WebViewController
        if let existing = tab.webController {
            web = existing
            configureWebController(web, for: tab)
        } else {
            web = makeWebController(for: tab)
            configureWebController(web, for: tab)
            tab.webController = web
            if let url = tab.url {
                // Restore without pushing a duplicate history entry.
                tab.navigationHistory.suppressNextRecord = true
                DispatchQueue.main.async {
                    web.load(url: url)
                }
            }
        }
        tab.lastAccessed = Date()
        embed(web)
        web.applyPageCleanerIfNeeded()
        addressBar.setURLText(Self.addressBarDisplayText(for: tab.url ?? web.webView?.url))
        tabManager.evictExcessWebViews(protecting: tab)
        refreshToolbar()
    }

    private func presentTabSwitcher() {
        setChromeCollapsed(false, animated: false)
        view.layoutIfNeeded()

        // Never block the switcher on WKWebView.takeSnapshot — a slow/frozen page can
        // delay or never deliver the callback, which made the tabs button feel dead.
        if tabManager.selectedTab?.isNewTabPage == true {
            tabManager.selectedTab?.snapshot = nil
        }

        let switcher = TabSwitcherViewController(tabManager: tabManager)
        switcher.delegate = self
        // Keep the browser (and WKWebView) in the window so HTML5 / YouTube audio keeps playing.
        switcher.modalPresentationStyle = .overFullScreen
        switcher.modalTransitionStyle = .coverVertical

        present(switcher, animated: true) { [weak self] in
            guard let self else { return }
            if self.tabManager.selectedTab?.webController?.isPictureInPictureActive != true {
                MediaPlaybackSupport.resumeMediaIfNeeded(in: self.tabManager.selectedTab?.webController?.webView)
            }

            let reload: () -> Void = { [weak switcher] in
                switcher?.reloadPreviews()
            }
            if let tab = self.tabManager.selectedTab, !tab.isNewTabPage {
                self.captureSnapshot(for: tab, completion: reload)
            }
            self.refreshBackgroundTabSnapshots(completion: reload)
        }
    }

    private func presentMenu() {
        // Page actions and app library share one sheet (former ··· + ≡ menus).
        presentPageRichMenu()
    }

    private func presentPageRichMenu() {
        setChromeCollapsed(false, animated: true)
        let tab = tabManager.selectedTab
        let context = PageRichMenuContext(
            url: tab?.url,
            title: tab?.title ?? "",
            isIncognito: tab?.isIncognito ?? false,
            userAgentMode: tab?.userAgentMode ?? .automatic,
            adBlockerEnabled: AppSettings.trackerProtectionEnabled,
            hasLoadablePage: tab?.isNewTabPage != true && tab?.url != nil
        )
        let menu = PageRichMenuViewController(context: context)
        menu.delegate = self
        configurePageRichMenuPresentation(menu)
        present(menu, animated: true) { [weak self] in
            guard self?.tabManager.selectedTab?.webController?.isPictureInPictureActive != true else { return }
            MediaPlaybackSupport.resumeMediaIfNeeded(in: self?.tabManager.selectedTab?.webController?.webView)
        }
    }

    private func configurePageRichMenuPresentation(_ menu: UIViewController) {
        let isPad = traitCollection.userInterfaceIdiom == .pad
        if isPad {
            // Wider / taller card than the default iPad page-sheet footprint.
            menu.modalPresentationStyle = .formSheet
            let width = min(max(view.bounds.width * 0.72, 560), 720)
            let height = min(max(view.bounds.height * 0.86, 640), 920)
            menu.preferredContentSize = CGSize(width: width, height: height)
            return
        }
        menu.modalPresentationStyle = .pageSheet
        if let sheet = menu.sheetPresentationController {
            sheet.prefersGrabberVisible = true
            // ~68% screen height so the first content cards + Long screenshot sit comfortably in view.
            let pageMenu = UISheetPresentationController.Detent.custom(
                identifier: .init("pageRichMenu")
            ) { context in
                min(context.maximumDetentValue * 0.68, context.maximumDetentValue)
            }
            sheet.detents = [pageMenu, .large()]
            sheet.selectedDetentIdentifier = pageMenu.identifier
        }
    }

    private func captureSnapshot(for tab: BrowserTab, completion: (() -> Void)?) {
        guard AppSettings.showTabsPreviewImages else {
            completion?()
            return
        }
        if tab.isNewTabPage {
            tab.snapshot = nil
            TabSnapshotStore.remove(for: tab.id)
            completion?()
            return
        }
        guard let web = tab.webController else {
            completion?()
            return
        }
        // Snapshotting a WebView that owns system PiP stalls the floating video.
        if web.isPictureInPictureActive || PipSession.isOwner(web) {
            if let snapshot = tab.snapshot {
                TabSnapshotStore.save(snapshot, for: tab.id)
            }
            completion?()
            return
        }

        var finished = false

        web.captureSnapshot { [weak tab] image in
            DispatchQueue.main.async {
                if AppSettings.showTabsPreviewImages, let image {
                    let thumb = TabSnapshotStore.thumbnailForMemory(image)
                    tab?.snapshot = thumb
                    if let id = tab?.id {
                        TabSnapshotStore.save(image, for: id)
                    }
                }
                if tab?.webController?.isPictureInPictureActive != true {
                    MediaPlaybackSupport.resumeMediaIfNeeded(in: tab?.webController?.webView)
                }
                // Completion at most once — late snapshots after the timeout still update the image.
                guard !finished else { return }
                finished = true
                completion?()
            }
        }
        // Frozen / hung content processes may never invoke takeSnapshot's callback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard !finished else { return }
            finished = true
            completion?()
        }
    }

    /// Capture tab previews one at a time to avoid parallel WK snapshot pressure.
    private func captureSnapshotsSerially(tabs: [BrowserTab], index: Int, completion: @escaping () -> Void) {
        guard index < tabs.count else {
            completion()
            return
        }
        let tab = tabs[index]
        if tab.webController != nil {
            captureSnapshot(for: tab) { [weak self] in
                self?.captureSnapshotsSerially(tabs: tabs, index: index + 1, completion: completion)
            }
        } else if let snapshot = tab.snapshot {
            TabSnapshotStore.save(snapshot, for: tab.id)
            captureSnapshotsSerially(tabs: tabs, index: index + 1, completion: completion)
        } else {
            captureSnapshotsSerially(tabs: tabs, index: index + 1, completion: completion)
        }
    }

    /// Refresh previews for non-selected tabs that still have a live WebView.
    private func refreshBackgroundTabSnapshots(completion: (() -> Void)?) {
        guard AppSettings.showTabsPreviewImages else {
            completion?()
            return
        }
        let selectedID = tabManager.selectedTab?.id
        let candidates = tabManager.tabs.filter {
            $0.id != selectedID && !$0.isNewTabPage && $0.webController != nil
        }
        guard !candidates.isEmpty else {
            completion?()
            return
        }
        captureSnapshotsSerially(tabs: candidates, index: 0) {
            completion?()
        }
    }

    private func openLibraryList(isBookmarks: Bool) {
        let containerID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        let sheet = LibrarySheetViewController(initialMode: isBookmarks ? .bookmarks : .history, containerID: containerID)
        if let tab = tabManager.selectedTab,
           !tab.isIncognito,
           !tab.isNewTabPage,
           let url = tab.url {
            sheet.currentPageURL = url
            sheet.currentPageTitle = tab.title
        }
        sheet.onSelectURL = { [weak self] url in
            self?.dismiss(animated: true) {
                self?.navigate(to: url)
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        if #available(iOS 15.0, *) {
            if let sheetPC = nav.sheetPresentationController {
                sheetPC.detents = [.large()]
                sheetPC.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    private func openWatchLater() {
        if tabManager.selectedTab?.isIncognito == true {
            Toast.show("Not available in Private Browsing", from: self)
            return
        }
        let containerID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        let list = WatchLaterViewController()
        list.containerID = containerID
        if let tab = tabManager.selectedTab, !tab.isIncognito, !tab.isNewTabPage, let url = tab.url {
            list.currentPageURL = url
            list.currentPageTitle = tab.title
        }
        list.onSelectURL = { [weak self] url in
            self?.dismiss(animated: true) {
                self?.navigate(to: url)
            }
        }
        let nav = UINavigationController(rootViewController: list)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        if let sheetPC = nav.sheetPresentationController {
            sheetPC.detents = [.large()]
            sheetPC.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func addCurrentPageToWatchLater() {
        guard let tab = tabManager.selectedTab else { return }
        if tab.isIncognito {
            Toast.show("Not available in Private Browsing", from: self)
            return
        }
        guard let url = tab.url, !tab.isNewTabPage else {
            Toast.show("No page to save", from: self)
            return
        }
        if WatchLaterStore.shared.add(title: tab.title, url: url, containerID: tab.containerID) != nil {
            if OfflineMediaCopyrightPolicy.restrictsAudioVideo(on: url) {
                Toast.show(
                    "Added to Watch Later. \(OfflineMediaCopyrightPolicy.watchLaterNotice)",
                    from: self
                )
            } else {
                Toast.show("Added to Watch Later", from: self)
            }
            tab.webController?.cacheCurrentPageForWatchLater(matching: url)
        } else {
            Toast.show("Already in Watch Later", from: self)
        }
    }
}

extension BrowserViewController: TabManagerDelegate {
    func tabManagerDidUpdate(_ manager: TabManager) {
        refreshToolbar()
        refreshAccountChip()
    }

    func tabManager(_ manager: TabManager, didSelect tab: BrowserTab) {
        showSelectedTab()
    }
}

extension BrowserViewController: AddressBarViewDelegate {
    func addressBarDidSubmit(_ text: String) {
        setChromeCollapsed(false, animated: true)
        navigate(to: URLInputResolver.resolve(text))
    }

    func addressBarDidBeginEditing() {
        setChromeCollapsed(false, animated: true)
        // Ensure the field shows the full URL while editing (not a stale compact label).
        if let url = tabManager.selectedTab?.url ?? tabManager.selectedTab?.webController?.webView?.url {
            let full = Self.addressBarDisplayText(for: url)
            if !full.isEmpty {
                addressBar.setURLTextForcing(full)
            }
        }
    }

    func addressBarDidTapReload() {
        setChromeCollapsed(false, animated: true)
        tabManager.selectedTab?.webController?.reload()
    }

    func addressBarDidTapBack() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "address_back")
        tabManager.selectedTab?.webController?.goBack()
    }

    func addressBarDidTapForward() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "address_forward")
        tabManager.selectedTab?.webController?.goForward()
    }

    func addressBarDidTapRichMenu() {
        presentPageRichMenu()
    }

    func addressBarCanSwipeToPreviousTab() -> Bool {
        tabManager.canSelectAdjacentTab(offset: -1)
    }

    func addressBarCanSwipeToNextTab() -> Bool {
        tabManager.canSelectAdjacentTab(offset: 1)
    }

    func addressBarTitleForAdjacentTab(offset: Int) -> String? {
        guard let tab = tabManager.tab(adjacentOffset: offset) else { return nil }
        if let host = tab.url?.host, !host.isEmpty { return host }
        if tab.isNewTabPage { return "New Tab" }
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Tab" : title
    }

    func addressBarSwipeDidUpdate(offset: CGFloat, width: CGFloat) {
        updateContentSwipe(offset: offset, addressWidth: width)
    }

    func addressBarDidSwipeToPreviousTab() {
        markAddressBarSwipeTipSeen()
        finishContentSwipe(selectOffset: -1)
    }

    func addressBarDidSwipeToNextTab() {
        markAddressBarSwipeTipSeen()
        finishContentSwipe(selectOffset: 1)
    }

    private func updateContentSwipe(offset: CGFloat, addressWidth: CGFloat) {
        let width = max(contentClipView.bounds.width, view.bounds.width, 1)
        let scale = width / max(addressWidth, 1)
        let contentOffset = offset * scale

        if abs(offset) < 0.5 {
            contentContainer.transform = .identity
            adjacentTabPreview.transform = .identity
            adjacentTabPreview.isHidden = true
            adjacentTabPreview.image = nil
            preparedAdjacentTabOffset = nil
            return
        }

        let towardNext = offset < 0
        let adj = towardNext ? 1 : -1
        if preparedAdjacentTabOffset != adj {
            preparedAdjacentTabOffset = adj
            if let tab = tabManager.selectedTab {
                captureSnapshot(for: tab, completion: nil)
            }
            configureAdjacentPreview(forTabOffset: adj)
        }

        contentContainer.transform = CGAffineTransform(translationX: contentOffset, y: 0)
        let peekStart: CGFloat = towardNext ? width : -width
        adjacentTabPreview.transform = CGAffineTransform(translationX: peekStart + contentOffset, y: 0)
        adjacentTabPreview.isHidden = false
    }

    private func configureAdjacentPreview(forTabOffset offset: Int) {
        guard let tab = tabManager.tab(adjacentOffset: offset) else {
            adjacentTabPreview.image = nil
            adjacentTabPreview.backgroundColor = BrowserTheme.background
            return
        }
        if let snapshot = tab.snapshot {
            adjacentTabPreview.image = snapshot
            adjacentTabPreview.backgroundColor = .clear
        } else if tab.isNewTabPage {
            adjacentTabPreview.image = nil
            adjacentTabPreview.backgroundColor = tab.isIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
        } else {
            adjacentTabPreview.image = nil
            adjacentTabPreview.backgroundColor = BrowserTheme.card
            // Best-effort live snapshot for a smoother peek.
            tab.webController?.captureSnapshot { [weak self, weak tab] image in
                guard let self = self, let tab = tab, let image else { return }
                let thumb = TabSnapshotStore.thumbnailForMemory(image)
                tab.snapshot = thumb
                if AppSettings.showTabsPreviewImages {
                    TabSnapshotStore.save(image, for: tab.id)
                }
                guard self.preparedAdjacentTabOffset == offset else { return }
                self.adjacentTabPreview.image = thumb
            }
        }
    }

    private func finishContentSwipe(selectOffset: Int) {
        contentContainer.transform = .identity
        adjacentTabPreview.transform = .identity
        adjacentTabPreview.isHidden = true
        adjacentTabPreview.image = nil
        preparedAdjacentTabOffset = nil
        if tabManager.selectAdjacentTab(offset: selectOffset) {
            showSelectedTab()
        }
    }

    func addressBarDidChoosePageCleaner(urlOnly: Bool) {
        tabManager.selectedTab?.webController?.enterPageCleaner(urlOnly: urlOnly)
        addressBar.setPageCleanerActive(tabManager.selectedTab?.webController?.isPageCleanerActive == true)
        // Keep capsule chrome while picking elements.
        if !isChromeCollapsed {
            setChromeCollapsed(true, animated: true)
        } else {
            applyCompactChromeLayout(true)
        }
    }

    func addressBarDidExitPageCleaner() {
        tabManager.selectedTab?.webController?.exitPageCleaner()
        addressBar.setPageCleanerActive(false)
        setChromeCollapsed(false, animated: true)
    }

    func addressBarDidTapCompactExpand() {
        // Cleaner mode stays on the capsule until Exit.
        guard tabManager.selectedTab?.webController?.isPageCleanerActive != true else { return }
        setChromeCollapsed(false, animated: true)
    }

    func addressBarDidChangeCleanerMenuVisible(_ visible: Bool, extraHeight: CGFloat) {
        let compact = isChromeCollapsed
            || tabManager.selectedTab?.webController?.isPageCleanerActive == true
        let baseAddress = compact ? BrowserTheme.chromeCompactPillHeight : BrowserTheme.addressBarHeight
        let baseChrome = compact ? BrowserTheme.chromeCompactHeight : BrowserTheme.chromeHeight
        addressBar.snp.updateConstraints { make in
            make.height.equalTo(baseAddress + extraHeight)
        }
        chromeHeightConstraint?.update(offset: baseChrome + extraHeight)
        if compact {
            applyCompactChromeLayout(true)
        }
        UIView.animate(withDuration: 0.18) {
            self.view.layoutIfNeeded()
        }
    }

    func addressBarDidTapShield(blockCount: Int) {
        let tpOn = AppSettings.trackerProtectionEnabled
        let shortsOn = AppSettings.hideShortsEnabled
        let ytOn = AppSettings.youtubeAdShieldEnabled

        var lines: [String] = []
        if blockCount > 0 {
            lines.append("Blocked \(blockCount) ads & trackers on this page.")
        } else if tpOn, !AppSettings.accurateBlockCountEnabled {
            lines.append("Ads & trackers are blocked. Turn on Accurate Block Count in Settings for a page badge.")
        } else {
            lines.append("No ads or trackers blocked on this page yet.")
        }
        lines.append("")
        lines.append("Block Ads & Trackers: \(tpOn ? "On" : "Off")")
        lines.append("Hide Shorts: \(shortsOn ? "On" : "Off")")
        lines.append("Fewer YouTube Ads: \(ytOn ? "On" : "Off")")

        let alert = UIAlertController(
            title: "Privacy Protection",
            message: lines.joined(separator: "\n"),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { [weak self] _ in
            self?.openSettings()
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = addressBar
            pop.sourceRect = addressBar.bounds
        }
        present(alert, animated: true)
    }
}

extension BrowserViewController: BottomToolbarViewDelegate {
    func toolbarDidTapAccount() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_account")
        presentTabSwitcher()
    }

    func toolbarDidLongPressAccount() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_account_longpress")
        guard let targetID = tabManager.quickSwitchTargetAccountID() else {
            presentAccountSwitcher()
            return
        }
        switchToAccountWithFeedback(targetID)
    }

    func toolbarDidTapBack() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_back")
        let tab = tabManager.selectedTab
        let web = tab?.webController
        if web?.canGoBack == true {
            web?.goBack()
            return
        }
        // No web history: Back goes to Home, and Forward can restore this tab.
        guard let tab, !tab.isNewTabPage, tab.url != nil else { return }
        chromeReturnTabID = tab.id
        openHomeTabPreservingReturn()
    }

    func toolbarDidTapForward() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_forward")
        let web = tabManager.selectedTab?.webController
        if web?.canGoForward == true {
            chromeReturnTabID = nil
            web?.goForward()
            return
        }
        // Synthetic Forward after Back→Home: restore the previous tab.
        if let returnID = chromeReturnTabID,
           tabManager.tabs.contains(where: { $0.id == returnID }) {
            chromeReturnTabID = nil
            tabManager.selectTab(id: returnID)
            showSelectedTab()
            return
        }
    }

    func toolbarDidTapHome() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_home")
        chromeReturnTabID = nil
        openHomeTabPreservingReturn()
    }

    func toolbarDidTapNewTab() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_new_tab")
        chromeReturnTabID = nil
        let containerID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
        _ = tabManager.addTab(incognito: false, select: true, containerID: containerID)
        showSelectedTab()
    }

    func toolbarDidTapTabs() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_tabs")
        presentTabSwitcher()
    }

    func toolbarDidTapMenu() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_menu")
        presentMenu()
    }

    func toolbarDidTapDownloads() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_downloads")
        openDownloads()
    }
}

extension BrowserViewController: AccountHubViewControllerDelegate {
    func accountHubDidRequestClose(_ hub: AccountHubViewController) {
        leaveAccountHubIfNeeded(hub) { [weak self] in
            guard let self else { return }

            // Already on a real page (typical after dismissing overlay) — just stay there.
            if let selected = self.tabManager.selectedTab,
               !selected.isIncognito,
               !selected.isNewTabPage {
                self.showSelectedTab()
                return
            }

            let accountID = hub.previewAccountID
                ?? self.tabManager.selectedTab?.containerID
                ?? self.tabManager.defaultContainer.id
            let sameAccount = self.tabManager.tabs
                .filter {
                    !$0.isIncognito && !$0.isNewTabPage && $0.containerID == accountID
                }
                .sorted { $0.lastAccessed > $1.lastAccessed }
            let anyReal = self.tabManager.tabs
                .filter { !$0.isIncognito && !$0.isNewTabPage }
                .sorted { $0.lastAccessed > $1.lastAccessed }

            if let tab = sameAccount.first ?? anyReal.first {
                self.tabManager.selectTab(id: tab.id)
                self.showSelectedTab()
            } else {
                Toast.show(AppL10n.string(.hubCloseNoTabsHint), from: self)
            }
        }
    }

    func accountHubDidRequestSettings(_ hub: AccountHubViewController) {
        leaveAccountHubIfNeeded(hub) { [weak self] in
            self?.openSettings()
        }
    }

    func accountHubDidRequestManageAccounts(_ hub: AccountHubViewController) {
        presentAccountManager(from: hub)
    }

    func accountHub(_ hub: AccountHubViewController, didSelectTabID tabID: UUID, accountID: UUID) {
        // Close hub first (overlay), then open the chosen tab in the browser.
        leaveAccountHubIfNeeded(hub) { [weak self] in
            guard let self else { return }
            guard self.tabManager.tabs.contains(where: { $0.id == tabID }) else { return }
            // Avoid switchToAccount() — it picks the most-recent tab, not the tapped one.
            self.tabManager.selectTab(id: tabID)
            // selectTab notifies the delegate, but ensure UI commits even if already selected.
            self.showSelectedTab()
            self.refreshAccountChip()
        }
    }

    func accountHub(_ hub: AccountHubViewController, didRequestNewTabInAccount accountID: UUID) {
        leaveAccountHubIfNeeded(hub) { [weak self] in
            guard let self else { return }
            _ = self.tabManager.addTab(incognito: false, select: true, containerID: accountID)
            self.showSelectedTab()
            self.refreshAccountChip()
        }
    }

    func accountHub(_ hub: AccountHubViewController, didRequestOpenURL url: URL, accountID: UUID) {
        leaveAccountHubIfNeeded(hub) { [weak self] in
            guard let self else { return }
            self.openURLInNewTab(url, containerID: accountID)
            self.refreshAccountChip()
        }
    }

    func accountHub(_ hub: AccountHubViewController, didRequestMenuAction action: MenuAction) {
        leaveAccountHubIfNeeded(hub) { [weak self] in
            self?.performMenuAction(action)
        }
    }

    private func leaveAccountHubIfNeeded(_ hub: AccountHubViewController, then: @escaping () -> Void) {
        guard hub.isOverlay else {
            then()
            return
        }
        // Prefer dismissing from the hub itself so we always tear down the overlay page.
        if hub.presentingViewController != nil {
            hub.dismiss(animated: true, completion: then)
        } else if presentedViewController != nil {
            dismiss(animated: true, completion: then)
        } else {
            then()
        }
    }
}

extension BrowserViewController: NewTabViewControllerDelegate {
    func newTabDidRequestIncognito() {
        _ = tabManager.addTab(incognito: true, select: true)
        showSelectedTab()
    }

    func newTabDidOpenURL(_ url: URL) {
        navigate(to: url)
    }

    func newTabDidTapSeeMoreContinue() {
        openLibraryList(isBookmarks: false)
    }

    func newTabDidRequestEditShortcuts() {}

    func newTabDidRequestSettings() {
        openSettings()
    }

    func newTabDidRequestAccountSwitch() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "ntp_account_switch")
        presentAccountSwitcher()
    }

    func newTabDidRequestAddAccount() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "ntp_account_add")
        presentAddAccount()
    }
}

extension BrowserViewController: PrivateNewTabViewControllerDelegate {
    func privateNewTabDidRequestClosePrivate() {
        tabManager.closeAllIncognitoTabs()
        showSelectedTab()
    }
}

extension BrowserViewController: WebViewControllerDelegate {
    func webViewController(_ controller: WebViewController, didScroll deltaY: CGFloat, offsetY: CGFloat) {
        guard tabManager.selectedTab?.webController === controller else { return }
        guard tabManager.selectedTab?.isNewTabPage != true, !addressBar.isHidden else { return }
        // Ignore programmatic offset / layout changes from chrome show/hide.
        guard !isAdjustingChromeLayout else { return }

        // Allow drag + fling. Nested short-video pans also report through here.
        let scrollView = controller.webView?.scrollView
        let userScrolling = scrollView?.isDragging == true || scrollView?.isDecelerating == true
        // Nested pan path uses offsetY >= 21 even when the root scroller stays at 0.
        let nestedScrollHint = offsetY > 20 && scrollView?.isDragging != true && scrollView?.isDecelerating != true
        guard userScrolling || nestedScrollHint else { return }

        // Cleaner mode locks the capsule chrome; scrolling must not expand or end cleaner.
        let cleanerLocked = controller.isPageCleanerActive

        // Near the true top of the root scroller, scrolling back up restores full chrome.
        // Do not force-expand when nested short-video pages keep offset ≈ 0 while swiping.
        if offsetY <= 20, deltaY < 0 {
            scrollAccumulator = 0
            if !cleanerLocked {
                setChromeCollapsed(false, animated: true)
            }
            return
        }

        scrollAccumulator += deltaY
        if scrollAccumulator > chromeScrollThreshold {
            // Content moving up → shrink to bottom domain pill
            scrollAccumulator = 0
            setChromeCollapsed(true, animated: true)
        } else if scrollAccumulator < -chromeScrollThreshold {
            // Content moving down → restore full chrome (blocked while cleaner is active).
            scrollAccumulator = 0
            if !cleanerLocked {
                setChromeCollapsed(false, animated: true)
            }
        }
    }

    func webViewController(_ controller: WebViewController, didUpdateTitle title: String?) {
        guard let tab = tabManager.tabs.first(where: { $0.webController === controller }) else { return }
        tab.title = (title?.isEmpty == false) ? title! : (tab.url?.host ?? "Untitled")
        tabManager.persistSessionIfNeeded()
    }

    func webViewController(_ controller: WebViewController, didUpdateURL url: URL?) {
        guard let tab = tabManager.tabs.first(where: { $0.webController === controller }) else { return }
        // Ignore nil — provisional failures clear WKWebView.url and would wipe the address bar.
        guard let url else { return }
        let previousHost = tab.url?.host
        tab.url = url
        tab.isNewTabPage = false
        if previousHost != url.host {
            tab.clearSessionAvatar()
        }
        if tabManager.selectedTab?.id == tab.id {
            addressBar.setURLText(Self.addressBarDisplayText(for: url))
            addressBar.setBlockCount(0)
            addressBar.setFocusIndicator(active: AppSettings.hideShortsEnabled && YouTubeDarkMode.isYouTube(url))
            if isChromeCollapsed {
                applyCompactChromeLayout(true)
            }
            refreshToolbar()
        }
        if !tab.isIncognito, !url.absoluteString.hasPrefix("about:") {
            HistoryStore.shared.add(title: tab.title, url: url, containerID: tab.containerID)
        }
        tabManager.persistSessionIfNeeded()
    }

    func webViewController(_ controller: WebViewController, didUpdateProgress progress: Double, isLoading: Bool) {
        guard tabManager.selectedTab?.webController === controller else { return }
        applyLoadingProgress(progress, isLoading: isLoading)
    }

    func webViewController(_ controller: WebViewController, didUpdateBlockCount count: Int) {
        guard tabManager.selectedTab?.webController === controller else { return }
        addressBar.setBlockCount(count)
    }

    func webViewControllerDidReportYouTubeDegraded(_ controller: WebViewController) {
        guard tabManager.selectedTab?.webController === controller else { return }
        Toast.show("YouTube filter degraded — try updating filters in Settings", from: self)
    }

    func webViewController(_ controller: WebViewController, didUpdateNavigationState canGoBack: Bool, canGoForward: Bool) {
        guard tabManager.selectedTab?.webController === controller else { return }
        refreshToolbar()
    }

    func webViewController(_ controller: WebViewController, requestNewTabFor url: URL) {
        XSiteProbe.log("browser.requestNewTab", [
            "url": url.absoluteString,
            "from": controller.webView?.url?.absoluteString ?? "nil"
        ])
        let parent = tabManager.tabs.first(where: { $0.webController === controller })
            ?? tabManager.selectedTab
        openURLInNewTab(url, incognito: parent?.isIncognito ?? false, inheritContainerFrom: parent)
    }

    func webViewController(_ controller: WebViewController, didDetectSessionAvatar url: URL?) {
        guard let tab = tabManager.tabs.first(where: { $0.webController === controller }) else { return }
        guard !tab.isIncognito else { return }
        if let url {
            guard tab.sessionAvatarURL != url else { return }
            tab.sessionAvatarURL = url
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard tab.sessionAvatarURL == url else { return }
                    tab.sessionAvatar = image
                    self?.reloadPresentedTabSwitcherPreviews()
                }
            }.resume()
        } else if tab.sessionAvatarURL != nil || tab.sessionAvatar != nil {
            tab.clearSessionAvatar()
            reloadPresentedTabSwitcherPreviews()
        }
    }

    func webViewController(_ controller: WebViewController, suggestComputerUserAgentFor siteName: String) {
        guard tabManager.selectedTab?.webController === controller else { return }
        guard let tab = tabManager.selectedTab else { return }
        guard presentedViewController == nil else { return }
        let host = (tab.url?.host ?? siteName).lowercased()
        guard !tab.dismissedDesktopUAHintHosts.contains(host) else { return }
        guard !tab.userAgentSettings.looksLikeComputer else { return }

        let alert = UIAlertController(
            title: "Use Computer for \(siteName)?",
            message: "This site is easier to sign in with a Computer user agent. This only changes this tab.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Use Computer", style: .default) { [weak self] _ in
            self?.applyComputerUserAgent(to: tab)
        })
        alert.addAction(UIAlertAction(title: "Choose User Agent", style: .default) { [weak self] _ in
            tab.dismissedDesktopUAHintHosts.insert(host)
            self?.presentTabUserAgentPicker()
        })
        alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
            tab.dismissedDesktopUAHintHosts.insert(host)
        })
        present(alert, animated: true)
    }

    func webViewController(_ controller: WebViewController, autoApplyComputerUserAgentFor siteName: String) {
        // Prefer the tab that owns this web view (Split View panes are often not selectedTab).
        let tab = tabManager.tabs.first(where: { $0.webController === controller })
            ?? (tabManager.selectedTab?.webController === controller ? tabManager.selectedTab : nil)
        guard let tab else { return }
        let host = (controller.webView?.url?.host ?? tab.url?.host ?? "").lowercased()
        // Remember the apex too so www / web dismissals stay in sync.
        let apex = host.split(separator: ".").suffix(2).joined(separator: ".")
        if !host.isEmpty {
            guard !tab.dismissedDesktopUAHintHosts.contains(host),
                  !tab.dismissedDesktopUAHintHosts.contains(apex) else { return }
        }
        guard !tab.userAgentSettings.looksLikeComputer else { return }
        // WebViewController already set Computer UA on the request; only persist + toast here.
        applyComputerUserAgent(to: tab, reloadWebView: false)
    }

    func webViewController(_ controller: WebViewController, didOfferOfflineVideo candidate: PageMediaCandidate) {
        // Intentionally unused: offline media is user-triggered via Watch Later (no auto “save video” prompts).
        _ = controller
        _ = candidate
    }

    private func applyComputerUserAgent(to tab: BrowserTab, reloadWebView: Bool = true) {
        let settings = TabUserAgentSettings(userAgentMode: .desktop, customUserAgent: nil)
        tab.applyUserAgentSettings(settings)
        if let host = tab.url?.host?.lowercased() {
            tab.dismissedDesktopUAHintHosts.insert(host)
            let apex = host.split(separator: ".").suffix(2).joined(separator: ".")
            if !apex.isEmpty {
                tab.dismissedDesktopUAHintHosts.insert(apex)
            }
        }
        tab.webController?.applyTabUserAgentSettings(settings, reload: reloadWebView)
        tabManager.persistSessionIfNeeded()
        Toast.show("This tab looks like: Computer", from: self)
    }

    private func reloadPresentedTabSwitcherPreviews() {
        var explorer: UIViewController? = presentedViewController
        while let current = explorer {
            if let switcher = current as? TabSwitcherViewController {
                switcher.reloadPreviews()
                return
            }
            if let nav = current as? UINavigationController {
                explorer = nav.topViewController
            } else {
                explorer = current.presentedViewController
            }
        }
    }

    func webViewControllerDidFail(_ controller: WebViewController, error: Error) {}

    func webViewController(_ controller: WebViewController, present vc: UIViewController) {
        presentAfterClearingPresented(vc)
    }

    /// Ensures we are not already presenting (e.g. leftover alert) before showing another VC.
    private func presentAfterClearingPresented(_ vc: UIViewController) {
        if let presented = presentedViewController {
            ScreenshotPerf.mark(
                "ui.present.waitDismiss",
                extra: String(describing: type(of: presented))
            )
            presented.dismiss(animated: false) { [weak self] in
                self?.presentAfterClearingPresented(vc)
            }
            return
        }
        present(vc, animated: true)
        ScreenshotPerf.mark("ui.present.started", extra: String(describing: type(of: vc)))
    }

    func webViewController(_ controller: WebViewController, warnDangerous url: URL, proceed: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Dangerous site",
            message: "This site looks suspicious and may be used for phishing.\n\n" + (url.host ?? url.absoluteString),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Go Back", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .destructive, handler: { _ in proceed() }))
        present(alert, animated: true)
    }
}

extension BrowserViewController: TabSwitcherViewControllerDelegate {
    func tabSwitcherDidClose() {
        dismiss(animated: true) {
            self.showSelectedTab()
            if self.tabManager.selectedTab?.webController?.isPictureInPictureActive != true {
                MediaPlaybackSupport.resumeMediaIfNeeded(in: self.tabManager.selectedTab?.webController?.webView)
            }
        }
    }

    func tabSwitcherDidRequestNewTab(incognito: Bool, containerID: UUID?) {
        dismiss(animated: true) {
            _ = self.tabManager.addTab(incognito: incognito, select: true, containerID: containerID)
            self.showSelectedTab()
        }
    }

    func tabSwitcherDidRequestOpenURLInNewTab(_ url: URL, containerID: UUID?) {
        dismiss(animated: true) {
            self.openURLInNewTab(url, incognito: false, containerID: containerID)
        }
    }

    func tabSwitcherDidRequestAccountHub() {
        dismiss(animated: true) { [weak self] in
            self?.presentAccountHub()
        }
    }
}

extension BrowserViewController: MenuViewControllerDelegate {
    func menuDidSelect(_ action: MenuAction) {
        dismiss(animated: true) { [weak self] in
            self?.performMenuAction(action)
        }
    }

    func performMenuAction(_ action: MenuAction) {
        switch action {
        case .bookmarks:
            openLibraryList(isBookmarks: true)
        case .history:
            openLibraryList(isBookmarks: false)
        case .watchLater:
            openWatchLater()
        case .readingList:
            openReadingList()
        case .downloads:
            if tabManager.selectedTab?.isIncognito == true {
                Toast.show("Downloads are disabled in Private Browsing", from: self)
                return
            }
            openDownloads()
        case .settings:
            openSettings()
        case .accounts:
            presentAccountSwitcher()
        case .compareAccounts:
            presentDualAccountCompare()
        case .setDefaultBrowser:
            guard DefaultBrowserFeature.isEnabled else { return }
            openDefaultBrowserSettings()
        case .passwords:
            openPasswords()
        case .backgroundGallery:
            openAppearance(focus: .wallpaper)
        case .theme:
            openAppearance(focus: .theme)
        case .feedback:
            openFeedback()
        case .reload:
            tabManager.selectedTab?.webController?.reload()
            Toast.show("Reloaded", from: self)
        case .newTab:
            let containerID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            _ = tabManager.addTab(incognito: false, select: true, containerID: containerID)
            showSelectedTab()
        case .newIncognitoTab:
            _ = tabManager.addTab(incognito: true, select: true)
            showSelectedTab()
        case .addBookmark:
            guard let tab = tabManager.selectedTab else { return }
            if tab.isIncognito {
                Toast.show("Not available in Private Browsing", from: self)
                return
            }
            guard let url = tab.url else {
                Toast.show("No page to bookmark", from: self)
                return
            }
            if BookmarkStore.shared.add(title: tab.title, url: url, containerID: tab.containerID) {
                Toast.show("Bookmark added", from: self)
            } else {
                Toast.show("Already bookmarked", from: self)
            }
        case .addReadingList:
            addCurrentPageToWatchLater()
        case .readerMode:
            tabManager.selectedTab?.webController?.openReaderMode()
        case .findInPage:
            tabManager.selectedTab?.webController?.showFindInPage()
        case .pictureInPicture:
            PipProbe.log("menu.pip.tap", [
                "host": tabManager.selectedTab?.url?.host ?? "?",
                "url": tabManager.selectedTab?.url?.absoluteString ?? "",
                "settingOn": AppSettings.pictureInPictureEnabled,
                "hasWeb": tabManager.selectedTab?.webController != nil
            ])
            guard AppSettings.pictureInPictureEnabled else {
                Toast.show("Picture in Picture is off in Settings", from: self)
                return
            }
            guard let web = tabManager.selectedTab?.webController else {
                PipProbe.log("menu.pip.fail", ["why": "noWebController"])
                Toast.show("No playable video for PiP", from: self)
                return
            }
            web.enterPictureInPictureFromUserAction(showFailureToast: true) { [weak self] ok in
                guard let self else { return }
                PipProbe.log("menu.pip.completion", [
                    "ok": ok,
                    "detail": web.lastPipEnterDetail
                ])
                guard !ok else { return }
                let detail = web.lastPipEnterDetail
                if detail.contains("unsupported") {
                    Toast.show("PiP isn't available for this video", from: self)
                } else {
                    #if DEBUG
                    Toast.show("PiP failed: \(detail)", from: self)
                    #else
                    Toast.show("No playable video for PiP", from: self)
                    #endif
                }
            }
        case .share:
            guard let url = tabManager.selectedTab?.url else {
                Toast.show("No page to share", from: self)
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activity, animated: true)
        case .userAgent:
            presentTabUserAgentPicker()
        case .sharePDF:
            tabManager.selectedTab?.webController?.sharePDF()
        case .downloadFile:
            tabManager.selectedTab?.webController?.downloadCurrentIfFile()
        case .screenshot:
            tabManager.selectedTab?.webController?.screenshot()
        case .longScreenshot:
            tabManager.selectedTab?.webController?.longScreenshot()
        case .pageCleaner:
            enterWebCleanerMode()
        case .copyURL:
            guard let url = tabManager.selectedTab?.url else {
                Toast.show("No URL to copy", from: self)
                return
            }
            UIPasteboard.general.string = url.absoluteString
            Toast.show("URL copied", from: self)
        case .aboutSite:
            presentAboutSite()
        case .addToHomepage:
            guard let tab = tabManager.selectedTab else { return }
            if tab.isIncognito {
                Toast.show("Not available in Private Browsing", from: self)
                return
            }
            guard let url = tab.url else {
                Toast.show("No page to add", from: self)
                return
            }
            if NavigationStore.shared.containsFavorite(url: url, containerID: tab.containerID) {
                Toast.show("Already in Favorites", from: self)
            } else {
                let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let ok = NavigationStore.shared.addToHome(
                    title: title.isEmpty ? (url.host ?? "Site") : title,
                    url: url,
                    containerID: tab.containerID
                )
                Toast.show(ok ? "Added to Favorites" : "Already in Favorites", from: self)
                accountHubController?.reloadFromExternalChange()
            }
        case .printPage:
            tabManager.selectedTab?.webController?.printPage()
        case .translate:
            guard let url = tabManager.selectedTab?.url else {
                Toast.show("No page to translate", from: self)
                return
            }
            let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url.absoluteString
            guard let translateURL = URL(string: "https://translate.google.com/translate?sl=auto&tl=en&u=\(encoded)") else { return }
            navigate(to: translateURL)
        case .changeTextSize:
            presentTextSizePicker()
        case .adBlocker:
            AppSettings.trackerProtectionEnabled.toggle()
            let on = AppSettings.trackerProtectionEnabled
            Toast.show(on ? "Ad blocker on" : "Ad blocker off", from: self)
        case .placeholder(let name):
            Toast.show("\(name) coming soon", from: self)
        }
    }

    private func presentAboutSite() {
        guard let tab = tabManager.selectedTab, let url = tab.url else {
            Toast.show("No site info", from: self)
            return
        }
        let host = url.host ?? url.absoluteString
        let message = [
            "Title: \(tab.title.isEmpty ? "—" : tab.title)",
            "URL: \(url.absoluteString)"
        ].joined(separator: "\n")
        let alert = UIAlertController(title: host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Copy URL", style: .default) { _ in
            UIPasteboard.general.string = url.absoluteString
            Toast.show("URL copied", from: self)
        })
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.path = "/"
            components.query = nil
            components.fragment = nil
            if let home = components.url {
                alert.addAction(UIAlertAction(title: "Open Site Home", style: .default) { [weak self] _ in
                    self?.navigate(to: home)
                })
            }
        }
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    private func presentTextSizePicker() {
        guard let web = tabManager.selectedTab?.webController else {
            Toast.show("No page loaded", from: self)
            return
        }
        let alert = UIAlertController(title: "Change text size", message: nil, preferredStyle: .actionSheet)
        let options: [(String, CGFloat)] = [
            ("Smaller", 0.85),
            ("Default", 1.0),
            ("Larger", 1.25),
            ("Largest", 1.5)
        ]
        for (title, zoom) in options {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                web.setPageZoom(zoom)
                Toast.show(title, from: self)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = addressBar
            pop.sourceRect = addressBar.bounds
        }
        present(alert, animated: true)
    }

    private func openSettings() {
        let settings = SettingsViewController()
        settings.tabManager = tabManager
        settings.onRequestRebuildWebViews = { [weak self] in
            self?.scheduleFullWebViewRebuild()
        }
        settings.onAccountsChanged = { [weak self] in
            self?.refreshAccountChip()
        }
        let nav = UINavigationController(rootViewController: settings)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func openAppearance(focus: AppearanceSettingsViewController.FocusSection) {
        let appearance = AppearanceSettingsViewController(focus: focus)
        let nav = UINavigationController(rootViewController: appearance)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func openDefaultBrowserSettings() {
        // iOS 18.3+: open the system Default Apps panel (Browser App lives there).
        // Earlier iOS: Default Browser App is under this app’s Settings page.
        if #available(iOS 18.3, *) {
            if let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString) {
                UIApplication.shared.open(url, options: [:]) { [weak self] success in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if success {
                            Toast.show("Choose Browser App under Default Apps", from: self)
                        } else {
                            self.openAppSettingsForDefaultBrowser()
                        }
                    }
                }
                return
            }
        }
        openAppSettingsForDefaultBrowser()
    }

    private func openAppSettingsForDefaultBrowser() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        Toast.show("Set XBrowser as Default Browser App in Settings", from: self)
    }

    private func openFeedback() {
        let address = "feedback@mmbrowser.app"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "XBrowser Feedback")
        ]
        if let url = components.url, UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            UIPasteboard.general.string = address
            Toast.show("Feedback email copied", from: self)
        }
    }

    private func openReadingList() {
        let list = ReadingListViewController()
        list.onOpenURL = { [weak self] url in self?.navigate(to: url) }
        let nav = UINavigationController(rootViewController: list)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func openDownloads() {
        let list = DownloadsViewController()
        let nav = UINavigationController(rootViewController: list)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func openPasswords() {
        PasswordVaultGate.unlockIfNeeded(from: self) { [weak self] ok in
            guard let self, ok else { return }
            let list = PasswordsViewController()
            let nav = UINavigationController(rootViewController: list)
            nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
            BrowserTheme.applyNavigationBar(to: nav.navigationBar)
            self.present(nav, animated: true)
        }
    }

    private func presentTabUserAgentPicker() {
        guard let tab = tabManager.selectedTab else { return }
        let picker = TabUserAgentPickerViewController(
            settings: tab.userAgentSettings,
            isIncognito: tab.isIncognito
        )
        picker.delegate = self
        let nav = UINavigationController(rootViewController: picker)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        if #available(iOS 15.0, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }
}

extension BrowserViewController: TabUserAgentPickerDelegate {
    func tabUserAgentPicker(_ picker: TabUserAgentPickerViewController, didSelect settings: TabUserAgentSettings) {
        guard let tab = tabManager.selectedTab else { return }
        tab.applyUserAgentSettings(settings)
        tab.webController?.applyTabUserAgentSettings(settings)
        tabManager.persistSessionIfNeeded()
        picker.dismiss(animated: true) {
            Toast.show("This tab looks like: \(settings.userAgentMode.displayName)", from: self)
        }
    }
}

extension BrowserViewController: PageRichMenuViewControllerDelegate {
    func pageRichMenuDidSelect(_ action: MenuAction) {
        dismiss(animated: true) { [weak self] in
            self?.performMenuAction(action)
        }
    }
}

extension BrowserViewController: DualAccountCompareViewControllerDelegate {
    func dualAccountCompareDidClose(_ controller: DualAccountCompareViewController) {
        // No-op — browser state unchanged when fully closing Split View.
    }

    func dualAccountCompare(
        _ controller: DualAccountCompareViewController,
        didKeepAccount id: UUID,
        url: URL?
    ) {
        applySplitViewKeep(accountID: id, url: url)
    }

    func applySplitViewKeep(accountID: UUID, url: URL?) {
        _ = tabManager.switchToAccount(accountID)
        showSelectedTab()
        if let url {
            let current = tabManager.selectedTab?.url
            let alreadyShowing = current?.host == url.host && current?.path == url.path
            if !alreadyShowing {
                navigate(to: url)
            }
        }
        let name = tabManager.container(id: accountID)?.name ?? "Space"
        Toast.show("Continued in \(name)", from: self)
        refreshAccountChip()
    }
}

extension BrowserViewController: AccountSwitcherViewControllerDelegate {
    func accountSwitcher(_ controller: AccountSwitcherViewController, didSelectAccount id: UUID) {
        controller.dismiss(animated: true) { [weak self] in
            self?.switchToAccountWithFeedback(id)
        }
    }

    func accountSwitcherDidRequestManage(_ controller: AccountSwitcherViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.presentAccountManager()
        }
    }

    func accountSwitcherDidRequestAddCustom(_ controller: AccountSwitcherViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.presentAddAccount()
        }
    }

    func accountSwitcher(_ controller: AccountSwitcherViewController, didRequestAddTemplate template: ContainerTemplate) {
        let name = tabManager.uniqueAccountName(base: template.suggestedName)
        let draft = template.makeContainer(
            name: name,
            sortIndex: tabManager.containers.count,
            colorIndex: tabManager.containers.count % AccountColor.palette.count
        )
        guard let created = tabManager.addContainer(draft) else {
            Toast.show("Could not create space", from: controller)
            return
        }
        let homeURL = template.homeURL
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.switchToAccountWithFeedback(
                created.id,
                subtitle: homeURL == nil
                    ? "\(template.displayName) space ready"
                    : "Opening \(template.displayName) Web…"
            )
            if let homeURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.navigate(to: homeURL)
                }
            }
        }
    }

    func accountSwitcher(_ controller: AccountSwitcherViewController, didRequestCompare leftID: UUID, rightID: UUID) {
        controller.dismiss(animated: true) { [weak self] in
            self?.presentDualAccountCompare(leftID: leftID, rightID: rightID)
        }
    }
}

extension BrowserViewController: ContainerManageViewControllerDelegate {
    func containerManageDidChange() {
        refreshAccountChip()
        if let tab = tabManager.selectedTab, tab.isNewTabPage, !tab.isIncognito {
            showNewTab(for: tab)
        }
    }
}

extension BrowserViewController: ContainerEditViewControllerDelegate {
    func containerEditDidSave(_ container: BrowserContainer, isNew: Bool) {
        if isNew {
            guard let created = tabManager.addContainer(container) else {
                Toast.show("Could not save. Choose a unique non-empty name.", from: self)
                return
            }
            switchToAccountWithFeedback(created.id, subtitle: "Space created")
        } else {
            guard tabManager.updateContainer(container) else {
                Toast.show("Could not save. Choose a unique non-empty name.", from: self)
                return
            }
            refreshAccountChip()
        }
    }
}
