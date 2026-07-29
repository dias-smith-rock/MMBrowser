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

    private var newTabController: NewTabViewController?
    private var privateNewTabController: PrivateNewTabViewController?
    private var currentContent: UIViewController?

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
    }

    @objc private func trackerChanged() {
        tabManager.invalidateAllWebViews()
        showSelectedTab()
    }

    @objc private func noImagesChanged() {
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
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        chromeStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        contentContainer.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(chromeHost.snp.top)
        }
    }

    private func showSelectedTab() {
        guard let tab = tabManager.selectedTab else { return }
        applyPrivateChrome(tab.isIncognito)
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
        } else {
            web = WebViewController(isIncognito: tab.isIncognito)
            web.delegate = self
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
        } else {
            web = WebViewController(isIncognito: tab.isIncognito)
            web.delegate = self
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
    }

    private func presentTabSwitcher() {
        captureCurrentSnapshotIfNeeded()
        let switcher = TabSwitcherViewController(tabManager: tabManager)
        switcher.delegate = self
        switcher.modalPresentationStyle = .fullScreen
        present(switcher, animated: true)
    }

    private func presentMenu() {
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
        guard let tab = tabManager.selectedTab else { return }
        if tab.isNewTabPage {
            tab.snapshot = nil
            return
        }
        tab.webController?.captureSnapshot { image in
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
        navigate(to: URLInputResolver.resolve(text))
    }

    func addressBarDidTapShare() {
        guard let url = tabManager.selectedTab?.url else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activity, animated: true)
    }

    func addressBarDidRequestManualScreenshot() {
        tabManager.selectedTab?.webController?.screenshot()
    }

    func addressBarDidRequestLongScreenshot() {
        tabManager.selectedTab?.webController?.longScreenshot()
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
        }
    }

    func webViewController(_ controller: WebViewController, didUpdateProgress progress: Double, isLoading: Bool) {
        guard tabManager.selectedTab?.webController === controller else { return }
        addressBar.setProgress(progress, isLoading: isLoading)
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
}

extension BrowserViewController: MenuViewControllerDelegate {
    func menuDidSelect(_ action: MenuAction) {
        dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            switch action {
            case .bookmarks:
                self.openLibraryList(isBookmarks: true)
            case .history:
                self.openLibraryList(isBookmarks: false)
            case .readingList:
                self.openReadingList()
            case .downloads:
                if self.tabManager.selectedTab?.isIncognito == true {
                    Toast.show("Downloads are disabled in Private Browsing", from: self)
                    return
                }
                self.openDownloads()
            case .settings:
                self.openSettings()
            case .reload:
                self.tabManager.selectedTab?.webController?.reload()
            case .newTab:
                _ = self.tabManager.addTab(incognito: false, select: true)
                self.showSelectedTab()
            case .newIncognitoTab:
                _ = self.tabManager.addTab(incognito: true, select: true)
                self.showSelectedTab()
            case .addBookmark:
                guard let tab = self.tabManager.selectedTab else { return }
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
                if self.tabManager.selectedTab?.isIncognito == true {
                    Toast.show("Not available in Private Browsing", from: self)
                    return
                }
                self.tabManager.selectedTab?.webController?.saveReadingList()
            case .readerMode:
                self.tabManager.selectedTab?.webController?.openReaderMode()
            case .findInPage:
                self.tabManager.selectedTab?.webController?.showFindInPage()
            case .desktopSite:
                guard let tab = self.tabManager.selectedTab else { return }
                tab.preferDesktop.toggle()
                tab.webController?.setPreferDesktop(tab.preferDesktop)
                Toast.show(tab.preferDesktop ? "Desktop site" : "Mobile site", from: self)
            case .sharePDF:
                self.tabManager.selectedTab?.webController?.sharePDF()
            case .screenshot:
                self.tabManager.selectedTab?.webController?.screenshot()
            case .longScreenshot:
                self.tabManager.selectedTab?.webController?.longScreenshot()
            case .placeholder(let name):
                Toast.show("\(name) coming soon", from: self)
            }
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
