import UIKit
import SnapKit

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
    private let chromeStack = UIStackView()
    /// Shown only while loading AND bottom chrome is collapsed.
    private let collapsedProgressView = UIProgressView(progressViewStyle: .bar)

    private var newTabController: NewTabViewController?
    private var privateNewTabController: PrivateNewTabViewController?
    private var currentContent: UIViewController?

    private var chromeBottomConstraint: Constraint?
    private var contentTopConstraint: Constraint?
    private var isChromeCollapsed = false
    private var scrollAccumulator: CGFloat = 0
    private let chromeScrollThreshold: CGFloat = 10
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

    @objc private func downloadDidFinish(_ note: Notification) {
        guard UIApplication.shared.applicationState == .active else { return }
        guard let item = note.userInfo?["item"] as? DownloadItem else { return }
        switch item.status {
        case .completed:
            Toast.show("Downloaded \(item.fileName)", from: self)
        case .failed:
            let detail = (item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown error"
            Toast.show("Download failed · \(detail)", from: self)
        default:
            break
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

        MediaPlaybackSupport.configureAudioSessionIfNeeded()
        for tab in tabManager.tabs where tab.webController?.needsBackgroundMediaKeepAlive == true {
            MediaPlaybackSupport.keepBackgroundMediaAlive(in: tab.webController?.webView)
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
        newTabController?.applyHomeSettings()
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
        }
        #endif
    }

    /// Called when entering background so tab/container state is on disk before cleanup.
    func persistSessionForBackground() {
        tabManager.persistSessionIfNeeded()
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
            }
            self?.newTabController?.applyHomeSettings()
        }
        present(onboarding, animated: true)
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
        chromeStack.spacing = 0
        chromeStack.addArrangedSubview(addressBar)
        chromeStack.addArrangedSubview(toolbar)

        chromeHost.clipsToBounds = false
        chromeHost.addSubview(chromeStack)

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
            chromeBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).constraint
        }
        chromeStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentClipView.snp.makeConstraints { make in
            contentTopConstraint = make.top.equalTo(view.safeAreaLayoutGuide.snp.top).constraint
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(chromeHost.snp.top)
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

    /// Hides / shows the bottom address bar + toolbar while scrolling a web page.
    /// Only the bottom chrome moves — content top stays on the safe area. Extending under
    /// the status bar / Dynamic Island breaks sticky mobile players (e.g. Bilibili) on device.
    private func setChromeCollapsed(_ collapsed: Bool, animated: Bool) {
        if collapsed {
            guard tabManager.selectedTab?.isNewTabPage != true else { return }
            guard !addressBar.isHidden else { return }
            // Don't hide chrome while the keyboard is up — address field would stay covered.
            guard keyboardOverlap < 1 else { return }
        }
        guard collapsed != isChromeCollapsed else { return }
        isChromeCollapsed = collapsed

        updateChromeBottomOffset(animated: false)

        let animations = {
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                animations: animations
            )
        } else {
            animations()
        }
        // Keep only one progress UI: address bar when expanded, bottom bar when collapsed.
        addressBar.setProgress(pageLoadProgress, isLoading: isPageLoading && !collapsed)
        updateCollapsedProgressVisibility()
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Places chrome above the home indicator, or above the keyboard when it overlaps.
    private func updateChromeBottomOffset(animated: Bool) {
        let safeBottom = view.safeAreaInsets.bottom
        let liftAboveSafeArea = max(0, keyboardOverlap - safeBottom)
        let offset: CGFloat
        if isChromeCollapsed && liftAboveSafeArea < 1 {
            let chromeHeight = BrowserTheme.addressBarHeight + BrowserTheme.toolbarHeight
            offset = chromeHeight + safeBottom
        } else {
            offset = -liftAboveSafeArea
        }
        chromeBottomConstraint?.update(offset: offset)
        // Keep collapsed progress just above the lifted chrome / home indicator.
        collapsedProgressView.snp.remakeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(2)
            if liftAboveSafeArea > 0 {
                make.bottom.equalTo(chromeHost.snp.top)
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
        updateChromeBottomOffset(animated: false)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
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
        applyPrivateChrome(tab.isIncognito)
        resetChromeForCurrentTab()
        addressBar.isHidden = false
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
    }

    private func refreshAccountChip() {
        guard let tab = tabManager.selectedTab else {
            toolbar.setAccount(name: "", color: .clear, visible: false)
            return
        }
        if tab.isIncognito {
            toolbar.setAccount(name: "", color: .clear, visible: false)
            return
        }
        let container = tabManager.container(id: tab.containerID) ?? tabManager.defaultContainer
        toolbar.setAccount(
            name: container.name,
            color: AccountColor.color(for: container),
            visible: true
        )
    }

    private func presentAccountSwitcher() {
        let switcher = AccountSwitcherViewController(tabManager: tabManager)
        switcher.delegate = self
        let nav = UINavigationController(rootViewController: switcher)
        nav.modalPresentationStyle = .pageSheet
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func presentAccountManager() {
        let vc = ContainerManageViewController(tabManager: tabManager)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func presentAddAccount() {
        let edit = ContainerEditViewController(
            container: nil,
            suggestedPresetIndex: tabManager.containers.count
        )
        edit.delegate = self
        let nav = UINavigationController(rootViewController: edit)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func applyPrivateChrome(_ isPrivate: Bool) {
        let bg = isPrivate ? BrowserTheme.privateBackground : BrowserTheme.background
        view.backgroundColor = bg
        statusBarFill.backgroundColor = bg
        contentClipView.backgroundColor = bg
        contentContainer.backgroundColor = bg
        addressBar.setPrivateMode(isPrivate)
        toolbar.setPrivateMode(isPrivate)
        collapsedProgressView.progressTintColor = isPrivate ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
    }

    private func showNewTab(for tab: BrowserTab) {
        let ntp: NewTabViewController
        if let existing = newTabController {
            ntp = existing
        } else {
            ntp = NewTabViewController()
            ntp.delegate = self
            newTabController = ntp
        }
        ntp.reloadContinue(from: tabManager.recentBrowsedTabs(limit: 1))
        ntp.reloadShortcuts()
        embed(ntp)
        addressBar.setURLText("")
        addressBar.setProgress(0, isLoading: false)
    }

    private func showPrivateNewTab() {
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
            return WebViewController(isIncognito: true, geoConfiguration: .fromAppSettings())
        }
        let geo: GeolocationSpoof.Configuration = {
            if let container = tabManager.container(id: tab.containerID) {
                return .from(container: container)
            }
            return .fromAppSettings()
        }()
        return WebViewController(
            isIncognito: false,
            websiteDataStore: TabSessionStore.dataStore(for: tabManager.sessionID(for: tab)),
            geoConfiguration: geo
        )
    }

    private func embed(_ child: UIViewController) {
        if currentContent === child { return }
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

    private func navigate(to url: URL, in tab: BrowserTab? = nil) {
        guard let tab = tab ?? tabManager.selectedTab else { return }
        tab.isNewTabPage = false
        tab.url = url
        tab.title = url.host ?? "Untitled"
        tab.lastAccessed = Date()
        addressBar.isHidden = false
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
        newTabController?.reloadContinue(from: tabManager.recentBrowsedTabs(limit: 1))
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
        let tab = tabManager.addTab(incognito: incognito, select: true, containerID: resolvedContainerID)
        XSiteProbe.log("browser.openURLInNewTab", [
            "url": url.absoluteString,
            "incognito": incognito,
            "tabID": tab.id.uuidString
        ])
        navigate(to: url, in: tab)
    }

    func refreshToolbar() {
        let web = tabManager.selectedTab?.webController
        let isPrivate = tabManager.selectedTab?.isIncognito ?? false
        toolbar.update(
            canGoBack: web?.canGoBack ?? false,
            canGoForward: web?.canGoForward ?? false,
            tabCount: tabManager.toolbarTabCount(incognito: isPrivate),
            isPrivate: isPrivate,
            hidesNavigationButtons: tabManager.selectedTab?.isNewTabPage == true
        )
        addressBar.setPageCleanerActive(tabManager.selectedTab?.webController?.isPageCleanerActive == true)
        maybeShowAddressBarSwipeTip()
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
        setChromeCollapsed(false, animated: true)
        let menu = MenuViewController(isIncognito: tabManager.selectedTab?.isIncognito ?? false)
        menu.delegate = self
        if #available(iOS 15.0, *) {
            if let sheet = menu.sheetPresentationController {
                sheet.prefersGrabberVisible = true
                if #available(iOS 16.0, *) {
                    let fitted = UISheetPresentationController.Detent.custom(identifier: .init("menuFitted")) { context in
                        // Taller than .medium so the extras row (Theme / Feedback) stays fully visible.
                        min(context.maximumDetentValue * 0.78, context.maximumDetentValue)
                    }
                    sheet.detents = [fitted, .large()]
                    sheet.selectedDetentIdentifier = fitted.identifier
                } else {
                    sheet.detents = [.large()]
                    sheet.selectedDetentIdentifier = .large
                }
            }
        }
        present(menu, animated: true) { [weak self] in
            guard self?.tabManager.selectedTab?.webController?.isPictureInPictureActive != true else { return }
            MediaPlaybackSupport.resumeMediaIfNeeded(in: self?.tabManager.selectedTab?.webController?.webView)
        }
    }

    private func presentPageRichMenu() {
        setChromeCollapsed(false, animated: true)
        let tab = tabManager.selectedTab
        let context = PageRichMenuContext(
            url: tab?.url,
            title: tab?.title ?? "",
            isIncognito: tab?.isIncognito ?? false,
            preferDesktop: tab?.preferDesktop ?? false,
            adBlockerEnabled: AppSettings.trackerProtectionEnabled,
            hasLoadablePage: tab?.isNewTabPage != true && tab?.url != nil
        )
        let menu = PageRichMenuViewController(context: context)
        menu.delegate = self
        if #available(iOS 15.0, *) {
            if let sheet = menu.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(menu, animated: true) { [weak self] in
            guard self?.tabManager.selectedTab?.webController?.isPictureInPictureActive != true else { return }
            MediaPlaybackSupport.resumeMediaIfNeeded(in: self?.tabManager.selectedTab?.webController?.webView)
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
        let sheet = LibrarySheetViewController(initialMode: isBookmarks ? .bookmarks : .history)
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
        setChromeCollapsed(false, animated: true)
        tabManager.selectedTab?.webController?.enterPageCleaner(urlOnly: urlOnly)
        addressBar.setPageCleanerActive(tabManager.selectedTab?.webController?.isPageCleanerActive == true)
    }

    func addressBarDidExitPageCleaner() {
        setChromeCollapsed(false, animated: true)
        tabManager.selectedTab?.webController?.exitPageCleaner()
        addressBar.setPageCleanerActive(false)
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
        presentAccountSwitcher()
    }
    func toolbarDidTapBack() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_back")
        tabManager.selectedTab?.webController?.goBack()
    }
    func toolbarDidTapForward() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_forward")
        tabManager.selectedTab?.webController?.goForward()
    }
    func toolbarDidTapNewTab() {
        AdLifecycleCoordinator.shared.recordFirstInteraction(source: "toolbar_new_tab")
        // Always open a normal tab; private browsing is opt-in only.
        // Inherit the currently selected tab's container (Firefox Container semantics).
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

        // Sticky players reflow when WKWebView height oscillates (Bilibili / YouTube on device).
        if WebViewController.isViewportFragileHost(controller.webView?.url) {
            scrollAccumulator = 0
            if isChromeCollapsed {
                setChromeCollapsed(false, animated: false)
            }
            return
        }

        // Rubber-band / deceleration at maxOffset flips chrome hide↔show in a loop.
        guard controller.webView?.scrollView.isDragging == true else { return }

        // Always reveal chrome near the top of the page.
        if offsetY <= 20 {
            scrollAccumulator = 0
            setChromeCollapsed(false, animated: true)
            return
        }

        scrollAccumulator += deltaY
        if scrollAccumulator > chromeScrollThreshold {
            // Content moving up → hide chrome
            scrollAccumulator = 0
            setChromeCollapsed(true, animated: true)
        } else if scrollAccumulator < -chromeScrollThreshold {
            // Content moving down → show chrome
            scrollAccumulator = 0
            setChromeCollapsed(false, animated: true)
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
            if WebViewController.isViewportFragileHost(url), isChromeCollapsed {
                setChromeCollapsed(false, animated: false)
            }
            refreshToolbar()
        }
        if !tab.isIncognito, !url.absoluteString.hasPrefix("about:") {
            HistoryStore.shared.add(title: tab.title, url: url)
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

    func webViewController(_ controller: WebViewController, didTriggerGestureAction action: GestureBrowserAction) {
        guard tabManager.selectedTab?.webController === controller else { return }
        switch action {
        case .goBack:
            controller.goBack()
        case .goForward:
            controller.goForward()
        case .pageUp:
            controller.pageUp()
        case .pageDown:
            controller.pageDown()
        case .none:
            break
        default:
            guard let menuAction = action.menuAction else { return }
            performMenuAction(menuAction)
        }
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
        case .setDefaultBrowser:
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
            if BookmarkStore.shared.add(title: tab.title, url: url) {
                Toast.show("Bookmark added", from: self)
            } else {
                Toast.show("Already bookmarked", from: self)
            }
        case .addReadingList:
            if tabManager.selectedTab?.isIncognito == true {
                Toast.show("Not available in Private Browsing", from: self)
                return
            }
            tabManager.selectedTab?.webController?.saveReadingList()
        case .readerMode:
            tabManager.selectedTab?.webController?.openReaderMode()
        case .findInPage:
            tabManager.selectedTab?.webController?.showFindInPage()
        case .pictureInPicture:
            guard AppSettings.pictureInPictureEnabled else {
                Toast.show("Picture in Picture is off in Settings", from: self)
                return
            }
            AppSettings.stickyPictureInPicture = true
            MediaPlaybackSupport.enterPictureInPicture(in: tabManager.selectedTab?.webController?.webView) { [weak self] ok in
                guard let self else { return }
                if !ok {
                    AppSettings.stickyPictureInPicture = false
                    Toast.show("No playable video for PiP", from: self)
                }
            }
        case .share:
            guard let url = tabManager.selectedTab?.url else {
                Toast.show("No page to share", from: self)
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activity, animated: true)
        case .desktopSite:
            guard let tab = tabManager.selectedTab else { return }
            tab.preferDesktop.toggle()
            tab.webController?.setPreferDesktop(tab.preferDesktop)
            Toast.show(tab.preferDesktop ? "Desktop site" : "Mobile site", from: self)
        case .sharePDF:
            tabManager.selectedTab?.webController?.sharePDF()
        case .downloadFile:
            tabManager.selectedTab?.webController?.downloadCurrentIfFile()
        case .screenshot:
            tabManager.selectedTab?.webController?.screenshot()
        case .longScreenshot:
            tabManager.selectedTab?.webController?.longScreenshot()
        case .pageCleaner:
            addressBar.presentCleanerMenu()
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
            if NavigationStore.shared.containsOnHome(url: url) {
                Toast.show("Already on Home", from: self)
            } else {
                let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let ok = NavigationStore.shared.addToHome(
                    title: title.isEmpty ? (url.host ?? "Site") : title,
                    url: url
                )
                Toast.show(ok ? "Added to Home" : "Already on Home", from: self)
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
        // Open the app’s Settings page; user can set Default Browser App there.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
            Toast.show("Set MMBrowser as Default Browser App in Settings", from: self)
        }
    }

    private func openFeedback() {
        let address = "feedback@mmbrowser.app"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "MMBrowser Feedback")
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
}

extension BrowserViewController: PageRichMenuViewControllerDelegate {
    func pageRichMenuDidSelect(_ action: MenuAction) {
        dismiss(animated: true) { [weak self] in
            self?.performMenuAction(action)
        }
    }
}

extension BrowserViewController: AccountSwitcherViewControllerDelegate {
    func accountSwitcher(_ controller: AccountSwitcherViewController, didSelectAccount id: UUID) {
        let name = tabManager.container(id: id)?.name ?? "Account"
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            _ = self.tabManager.switchToAccount(id)
            self.showSelectedTab()
            Toast.show("Switched to \(name)", from: self)
            AppAnalytics.logAccountSwitch(accountName: name)
        }
    }

    func accountSwitcherDidRequestManage(_ controller: AccountSwitcherViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.presentAccountManager()
        }
    }

    func accountSwitcherDidRequestAdd(_ controller: AccountSwitcherViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.presentAddAccount()
        }
    }
}

extension BrowserViewController: ContainerManageViewControllerDelegate {
    func containerManageDidChange() {
        refreshAccountChip()
    }
}

extension BrowserViewController: ContainerEditViewControllerDelegate {
    func containerEditDidSave(_ container: BrowserContainer, isNew: Bool) {
        if isNew {
            guard let created = tabManager.addContainer(container) else {
                Toast.show("Could not save. Choose a unique non-empty name.", from: self)
                return
            }
            _ = tabManager.switchToAccount(created.id)
            showSelectedTab()
            Toast.show("Opened \(created.name)", from: self)
        } else {
            guard tabManager.updateContainer(container) else {
                Toast.show("Could not save. Choose a unique non-empty name.", from: self)
                return
            }
            refreshAccountChip()
        }
    }
}
