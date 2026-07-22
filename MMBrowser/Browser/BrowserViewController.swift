import UIKit
import SnapKit

final class BrowserViewController: UIViewController {
    let tabManager = TabManager()

    private let contentContainer = UIView()
    private let addressBar = AddressBarView()
    private let toolbar = BottomToolbarView()
    private let chromeStack = UIStackView()

    private var newTabController: NewTabViewController?
    private var currentContent: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        tabManager.delegate = self
        setupChrome()
        showSelectedTab()
    }

    private func setupChrome() {
        contentContainer.backgroundColor = BrowserTheme.background
        addressBar.delegate = self
        toolbar.delegate = self

        chromeStack.axis = .vertical
        chromeStack.spacing = 0
        chromeStack.addArrangedSubview(addressBar)
        chromeStack.addArrangedSubview(toolbar)

        view.addSubview(contentContainer)
        view.addSubview(chromeStack)

        addressBar.snp.makeConstraints { make in
            make.height.equalTo(BrowserTheme.addressBarHeight)
        }
        toolbar.snp.makeConstraints { make in
            make.height.equalTo(BrowserTheme.toolbarHeight)
        }
        chromeStack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        contentContainer.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(chromeStack.snp.top)
        }
    }

    private func showSelectedTab() {
        guard let tab = tabManager.selectedTab else { return }
        if tab.isNewTabPage {
            addressBar.isHidden = true
            showNewTab(for: tab)
        } else {
            addressBar.isHidden = false
            showWeb(for: tab)
        }
        refreshToolbar()
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
        toolbar.update(
            canGoBack: wv?.canGoBack ?? false,
            canGoForward: wv?.canGoForward ?? false,
            tabCount: tabManager.tabs.count
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
        let menu = MenuViewController()
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
        nav.navigationBar.barStyle = .black
        nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
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

    func addressBarDidTapLens() {
        Toast.show("Coming soon", from: self)
    }
}

extension BrowserViewController: BottomToolbarViewDelegate {
    func toolbarDidTapBack() { tabManager.selectedTab?.webController?.goBack() }
    func toolbarDidTapForward() { tabManager.selectedTab?.webController?.goForward() }
    func toolbarDidTapNewTab() {
        _ = tabManager.addTab(incognito: false, select: true)
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
        toolbar.update(canGoBack: canGoBack, canGoForward: canGoForward, tabCount: tabManager.tabs.count)
    }

    func webViewController(_ controller: WebViewController, requestNewTabFor url: URL) {
        openURLInNewTab(url, incognito: tabManager.selectedTab?.isIncognito ?? false)
    }

    func webViewControllerDidFail(_ controller: WebViewController, error: Error) {}
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
            case .reload:
                self.tabManager.selectedTab?.webController?.reload()
            case .newTab:
                _ = self.tabManager.addTab(incognito: false, select: true)
                self.showSelectedTab()
            case .newIncognitoTab:
                _ = self.tabManager.addTab(incognito: true, select: true)
                self.showSelectedTab()
            case .addBookmark:
                guard let tab = self.tabManager.selectedTab, let url = tab.url else {
                    Toast.show("No page to bookmark", from: self)
                    return
                }
                BookmarkStore.shared.add(title: tab.title, url: url)
                Toast.show("Bookmark added", from: self)
            case .placeholder(let name):
                Toast.show("\(name) coming soon", from: self)
            }
        }
    }
}
