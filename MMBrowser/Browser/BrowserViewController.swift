import UIKit
import SnapKit

final class BrowserViewController: UIViewController {
    let tabManager = TabManager()

    private let statusBarFill = UIView()
    private let contentContainer = UIView()
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
    private var isChromeCollapsed = false
    private var scrollAccumulator: CGFloat = 0
    private let chromeScrollThreshold: CGFloat = 10
    private var isPageLoading = false
    private var pageLoadProgress: Double = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        tabManager.delegate = self
        setupChrome()
        showSelectedTab()
        if !AppSettings.didShowOnboarding {
            DispatchQueue.main.async { self.presentOnboarding() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(trackerChanged), name: .trackerProtectionChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(noImagesChanged), name: .noImagesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .shortsFocusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .youtubeAdShieldChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .mediaPlaybackSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .filterManifestUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildWebViews), name: .locationPrivacyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClearOptionSessionCleanup), name: .clearOptionSessionCleanup, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleClearOptionSettingsChanged), name: .clearOptionSettingsChanged, object: nil)
    }

    @objc private func handleClearOptionSessionCleanup() {
        guard AppSettings.closeAllTabsOnExit else { return }
        // Dismiss overlays so we can reset to a fresh New Tab cleanly.
        presentedViewController?.dismiss(animated: false)
        tabManager.closeAllTabsAndReset()
        showSelectedTab()
        refreshToolbar()
    }

    @objc private func handleClearOptionSettingsChanged() {
        if !AppSettings.showTabsPreviewImages {
            tabManager.clearAllSnapshots()
        }
    }

    @objc private func trackerChanged() {
        tabManager.invalidateAllWebViews()
        showSelectedTab()
    }

    @objc private func noImagesChanged() {
        tabManager.invalidateAllWebViews()
        showSelectedTab()
    }

    @objc private func rebuildWebViews() {
        tabManager.invalidateAllWebViews()
        showSelectedTab()
    }

    private func presentOnboarding() {
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .fullScreen
        onboarding.onFinished = { [weak self, weak onboarding] in
            onboarding?.dismiss(animated: true)
            self?.newTabController?.applyHomeSettings()
        }
        present(onboarding, animated: true)
    }

    private func setupChrome() {
        contentContainer.backgroundColor = BrowserTheme.background
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
        view.addSubview(contentContainer)
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
        contentContainer.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(chromeHost.snp.top)
        }
        collapsedProgressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(2)
        }
    }

    /// Hides / shows the bottom address bar + toolbar while scrolling a web page.
    private func setChromeCollapsed(_ collapsed: Bool, animated: Bool) {
        if collapsed {
            guard tabManager.selectedTab?.isNewTabPage != true else { return }
            guard !addressBar.isHidden else { return }
        }
        guard collapsed != isChromeCollapsed else { return }
        isChromeCollapsed = collapsed

        let chromeHeight = BrowserTheme.addressBarHeight + BrowserTheme.toolbarHeight
        let bottomInset = view.safeAreaInsets.bottom
        let offset = collapsed ? (chromeHeight + bottomInset) : 0
        chromeBottomConstraint?.update(offset: offset)

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
        applyPrivateChrome(tab.isIncognito)
        resetChromeForCurrentTab()
        if tab.isNewTabPage {
            addressBar.isHidden = true
            if tab.isIncognito {
                showPrivateNewTab()
            } else {
                showNewTab(for: tab)
            }
        } else {
            addressBar.isHidden = false
            showWeb(for: tab)
        }
        refreshToolbar()
    }

    private func applyPrivateChrome(_ isPrivate: Bool) {
        let bg = isPrivate ? BrowserTheme.privateBackground : BrowserTheme.background
        view.backgroundColor = bg
        statusBarFill.backgroundColor = bg
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

    private func showWeb(for tab: BrowserTab) {
        let web: WebViewController
        if let existing = tab.webController {
            web = existing
            configureWebController(web)
        } else {
            web = WebViewController(isIncognito: tab.isIncognito)
            configureWebController(web)
            tab.webController = web
            if let url = tab.url {
                // load after embed
                DispatchQueue.main.async {
                    web.load(url: url)
                }
            }
        }
        embed(web)
        addressBar.setURLText(tab.url?.host ?? tab.url?.absoluteString ?? "")
        refreshToolbar()
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

        let web: WebViewController
        if let existing = tab.webController {
            web = existing
            configureWebController(web)
        } else {
            web = WebViewController(isIncognito: tab.isIncognito)
            configureWebController(web)
            tab.webController = web
        }
        embed(web)
        web.load(url: url)
        refreshToolbar()
        newTabController?.reloadContinue(from: tabManager.recentBrowsedTabs(limit: 1))
    }

    private func openURLInNewTab(_ url: URL, incognito: Bool = false) {
        let tab = tabManager.addTab(incognito: incognito, select: true)
        navigate(to: url, in: tab)
    }

    func refreshToolbar() {
        let wv = tabManager.selectedTab?.webController?.webView
        let isPrivate = tabManager.selectedTab?.isIncognito ?? false
        let tabCount = isPrivate ? tabManager.incognitoTabs.count : tabManager.normalTabs.count
        toolbar.update(
            canGoBack: wv?.canGoBack ?? false,
            canGoForward: wv?.canGoForward ?? false,
            tabCount: max(tabCount, 1),
            isPrivate: isPrivate
        )
        addressBar.setPageCleanerActive(tabManager.selectedTab?.webController?.isPageCleanerActive == true)
    }

    private func configureWebController(_ web: WebViewController) {
        web.delegate = self
        web.onPageCleanerActiveChanged = { [weak self, weak web] active in
            guard let self = self, let web = web else { return }
            guard self.tabManager.selectedTab?.webController === web else { return }
            self.addressBar.setPageCleanerActive(active)
        }
    }

    private func presentTabSwitcher() {
        setChromeCollapsed(false, animated: false)
        captureCurrentSnapshotIfNeeded()
        let switcher = TabSwitcherViewController(tabManager: tabManager)
        switcher.delegate = self
        switcher.modalPresentationStyle = .fullScreen
        present(switcher, animated: true)
    }

    private func presentMenu() {
        setChromeCollapsed(false, animated: true)
        let menu = MenuViewController(isIncognito: tabManager.selectedTab?.isIncognito ?? false)
        menu.delegate = self
        if #available(iOS 15.0, *) {
            if let sheet = menu.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(menu, animated: true)
    }

    private func captureCurrentSnapshotIfNeeded() {
        guard AppSettings.showTabsPreviewImages else { return }
        guard let tab = tabManager.selectedTab else { return }
        if tab.isNewTabPage {
            tab.snapshot = nil
            return
        }
        tab.webController?.captureSnapshot { image in
            guard AppSettings.showTabsPreviewImages else { return }
            tab.snapshot = image
        }
    }

    private func openLibraryList(isBookmarks: Bool) {
        let root: UIViewController
        if isBookmarks {
            let list = BookmarksViewController()
            list.onSelectURL = { [weak self] url in
                self?.dismiss(animated: true) {
                    self?.navigate(to: url)
                }
            }
            root = list
        } else {
            let list = HistoryViewController()
            list.onSelectURL = { [weak self] url in
                self?.dismiss(animated: true) {
                    self?.navigate(to: url)
                }
            }
            root = list
        }
        let nav = UINavigationController(rootViewController: root)
        nav.overrideUserInterfaceStyle = .dark
        BrowserTheme.applyDarkNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }
}

extension BrowserViewController: TabManagerDelegate {
    func tabManagerDidUpdate(_ manager: TabManager) {
        refreshToolbar()
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

    func addressBarDidRequestManualScreenshot() {
        setChromeCollapsed(false, animated: true)
        tabManager.selectedTab?.webController?.screenshot()
    }

    func addressBarDidRequestLongScreenshot() {
        setChromeCollapsed(false, animated: true)
        tabManager.selectedTab?.webController?.longScreenshot()
    }

    func addressBarDidTapShield(blockCount: Int) {
        let tpOn = AppSettings.trackerProtectionEnabled
        let shortsOn = AppSettings.hideShortsEnabled
        let ytOn = AppSettings.youtubeAdShieldEnabled

        var lines: [String] = []
        if blockCount > 0 {
            lines.append("Blocked \(blockCount) ads & trackers on this page.")
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
    func toolbarDidTapBack() { tabManager.selectedTab?.webController?.goBack() }
    func toolbarDidTapForward() { tabManager.selectedTab?.webController?.goForward() }
    func toolbarDidTapNewTab() {
        let privateMode = tabManager.selectedTab?.isIncognito ?? false
        _ = tabManager.addTab(incognito: privateMode, select: true)
        showSelectedTab()
    }
    func toolbarDidTapTabs() { presentTabSwitcher() }
    func toolbarDidTapMenu() { presentMenu() }
}

extension BrowserViewController: NewTabViewControllerDelegate {
    func newTabDidSubmit(_ text: String) {
        navigate(to: URLInputResolver.resolve(text))
    }

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
    func privateNewTabDidSubmit(_ text: String) {
        navigate(to: URLInputResolver.resolve(text))
    }

    func privateNewTabDidRequestClosePrivate() {
        tabManager.closeAllIncognitoTabs()
        showSelectedTab()
    }
}

extension BrowserViewController: WebViewControllerDelegate {
    func webViewController(_ controller: WebViewController, didScroll deltaY: CGFloat, offsetY: CGFloat) {
        guard tabManager.selectedTab?.webController === controller else { return }
        guard tabManager.selectedTab?.isNewTabPage != true, !addressBar.isHidden else { return }

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
    }

    func webViewController(_ controller: WebViewController, didUpdateURL url: URL?) {
        guard let tab = tabManager.tabs.first(where: { $0.webController === controller }) else { return }
        tab.url = url
        tab.isNewTabPage = false
        if tabManager.selectedTab?.id == tab.id {
            addressBar.setURLText(url?.host ?? url?.absoluteString ?? "")
            addressBar.setBlockCount(0)
            addressBar.setFocusIndicator(active: AppSettings.hideShortsEnabled && YouTubeDarkMode.isYouTube(url))
        }
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
        guard let menuAction = action.menuAction else { return }
        performMenuAction(menuAction)
    }

    func webViewController(_ controller: WebViewController, didUpdateNavigationState canGoBack: Bool, canGoForward: Bool) {
        guard tabManager.selectedTab?.webController === controller else { return }
        refreshToolbar()
    }

    func webViewController(_ controller: WebViewController, requestNewTabFor url: URL) {
        openURLInNewTab(url, incognito: tabManager.selectedTab?.isIncognito ?? false)
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
        }
    }

    func tabSwitcherDidRequestNewTab(incognito: Bool) {
        dismiss(animated: true) {
            _ = self.tabManager.addTab(incognito: incognito, select: true)
            self.showSelectedTab()
        }
    }

    func tabSwitcherDidRequestOpenURLInNewTab(_ url: URL) {
        dismiss(animated: true) {
            self.openURLInNewTab(url, incognito: false)
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
        case .reload:
            tabManager.selectedTab?.webController?.reload()
            Toast.show("Reloaded", from: self)
        case .newTab:
            _ = tabManager.addTab(incognito: false, select: true)
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
            BookmarkStore.shared.add(title: tab.title, url: url)
            Toast.show("Bookmark added", from: self)
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
        case .screenshot:
            tabManager.selectedTab?.webController?.screenshot()
        case .longScreenshot:
            tabManager.selectedTab?.webController?.longScreenshot()
        case .placeholder(let name):
            Toast.show("\(name) coming soon", from: self)
        }
    }

    private func openSettings() {
        let settings = SettingsViewController()
        settings.onRequestRebuildWebViews = { [weak self] in
            self?.tabManager.invalidateAllWebViews()
            self?.showSelectedTab()
        }
        let nav = UINavigationController(rootViewController: settings)
        nav.overrideUserInterfaceStyle = .dark
        BrowserTheme.applyDarkNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func openReadingList() {
        let list = ReadingListViewController()
        list.onOpenURL = { [weak self] url in self?.navigate(to: url) }
        let nav = UINavigationController(rootViewController: list)
        nav.overrideUserInterfaceStyle = .dark
        BrowserTheme.applyDarkNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func openDownloads() {
        let list = DownloadsViewController()
        let nav = UINavigationController(rootViewController: list)
        nav.overrideUserInterfaceStyle = .dark
        BrowserTheme.applyDarkNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }
}
