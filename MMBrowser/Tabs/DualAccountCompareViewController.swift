import UIKit
import SnapKit
import WebKit

protocol DualAccountCompareViewControllerDelegate: AnyObject {
    func dualAccountCompareDidClose(_ controller: DualAccountCompareViewController)
    /// Exit Split View and continue browsing with one pane's account + URL.
    func dualAccountCompare(
        _ controller: DualAccountCompareViewController,
        didKeepAccount id: UUID,
        url: URL?
    )
}

/// Top/bottom browsing in two accounts (split view).
final class DualAccountCompareViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: DualAccountCompareViewControllerDelegate?

    private let tabManager: TabManager
    private let startURL: URL

    private let splitContainer = UIView()
    private let divider = UIView()
    private let dividerGrip = UIView()
    private var topHeightConstraint: Constraint?
    /// Share of space above the divider (0...1), excluding divider thickness.
    private var splitFraction: CGFloat = 0.5
    private let dividerThickness: CGFloat = 22
    private let minPaneHeight: CGFloat = 110
    private var dragStartFraction: CGFloat = 0.5
    private var isDraggingDivider = false

    private var topState: PaneState
    private var bottomState: PaneState
    private var didClose = false

    private enum Side { case top, bottom }

    private final class PaneState {
        var container: BrowserContainer
        var web: WebViewController?
        var wrap: UIView?
        var chrome: UIView?
        var accountButton: UIButton?
        var addressField: UITextField?
        var closePaneButton: UIButton?
        /// When set, `web` belongs to this tab and must not be destroyed on close.
        var borrowedTabID: UUID?

        init(container: BrowserContainer) {
            self.container = container
        }
    }

    init(tabManager: TabManager, leftContainer: BrowserContainer, rightContainer: BrowserContainer, url: URL) {
        self.tabManager = tabManager
        self.startURL = url
        self.topState = PaneState(container: leftContainer)
        self.bottomState = PaneState(container: rightContainer)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        title = "Split View"
        setupSplit()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupSplit() {
        splitContainer.backgroundColor = BrowserTheme.background
        view.addSubview(splitContainer)
        splitContainer.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        let topPane = makePane(side: .top)
        let bottomPane = makePane(side: .bottom)

        divider.backgroundColor = BrowserTheme.background
        divider.isUserInteractionEnabled = true
        divider.accessibilityLabel = "Resize Split View"
        divider.accessibilityTraits = .adjustable
        dividerGrip.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.45)
        dividerGrip.layer.cornerRadius = 2.5
        divider.addSubview(dividerGrip)
        dividerGrip.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(40)
            make.height.equalTo(5)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dividerPanned(_:)))
        divider.addGestureRecognizer(pan)

        splitContainer.addSubview(topPane)
        splitContainer.addSubview(divider)
        splitContainer.addSubview(bottomPane)

        topPane.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            topHeightConstraint = make.height.equalTo(200).constraint
        }
        divider.snp.makeConstraints { make in
            make.top.equalTo(topPane.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(dividerThickness)
        }
        bottomPane.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isDraggingDivider else { return }
        applySplitFraction(animated: false)
    }

    private func usableSplitHeight() -> CGFloat {
        max(0, splitContainer.bounds.height - dividerThickness)
    }

    private func applySplitFraction(animated: Bool) {
        let usable = usableSplitHeight()
        guard usable > minPaneHeight * 2 else { return }
        let minFraction = minPaneHeight / usable
        let clamped = min(max(splitFraction, minFraction), 1 - minFraction)
        splitFraction = clamped
        let topHeight = usable * clamped
        let updates = {
            self.topHeightConstraint?.update(offset: topHeight)
            self.splitContainer.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseOut, animations: updates)
        } else {
            updates()
        }
    }

    @objc private func dividerPanned(_ gesture: UIPanGestureRecognizer) {
        let usable = usableSplitHeight()
        guard usable > minPaneHeight * 2 else { return }

        switch gesture.state {
        case .began:
            isDraggingDivider = true
            dragStartFraction = splitFraction
            view.endEditing(true)
            UIView.animate(withDuration: 0.12) {
                self.dividerGrip.backgroundColor = BrowserTheme.chromeBlue
                self.dividerGrip.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }
        case .changed:
            let translation = gesture.translation(in: splitContainer).y
            splitFraction = dragStartFraction + translation / usable
            applySplitFraction(animated: false)
        case .ended, .cancelled, .failed:
            isDraggingDivider = false
            UIView.animate(withDuration: 0.15) {
                self.dividerGrip.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.45)
                self.dividerGrip.transform = .identity
            }
            applySplitFraction(animated: true)
        default:
            break
        }
    }

    private func state(for side: Side) -> PaneState {
        side == .top ? topState : bottomState
    }

    private func makePane(side: Side) -> UIView {
        let pane = state(for: side)
        let wrap = UIView()
        wrap.backgroundColor = BrowserTheme.secondaryCard
        pane.wrap = wrap

        let chrome = UIStackView()
        chrome.axis = .vertical
        chrome.spacing = 6
        chrome.isLayoutMarginsRelativeArrangement = true
        chrome.layoutMargins = UIEdgeInsets(top: 6, left: 8, bottom: 4, right: 8)
        wrap.addSubview(chrome)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        let accountButton = UIButton(type: .system)
        accountButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        accountButton.titleLabel?.lineBreakMode = .byTruncatingTail
        accountButton.contentHorizontalAlignment = .leading
        accountButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)), for: .normal)
        accountButton.semanticContentAttribute = .forceRightToLeft
        accountButton.tag = side == .top ? 0 : 1
        accountButton.addTarget(self, action: #selector(accountTapped(_:)), for: .touchUpInside)
        accountButton.accessibilityLabel = "Change account"
        pane.accountButton = accountButton
        refreshAccountButton(side: side)

        let closePaneButton = UIButton(type: .system)
        let xConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        closePaneButton.setImage(UIImage(systemName: "xmark", withConfiguration: xConfig), for: .normal)
        closePaneButton.tintColor = BrowserTheme.textSecondary
        closePaneButton.tag = side == .top ? 0 : 1
        closePaneButton.addTarget(self, action: #selector(closePaneTapped(_:)), for: .touchUpInside)
        closePaneButton.accessibilityLabel = "Close this view and keep the other"
        closePaneButton.setContentHuggingPriority(.required, for: .horizontal)
        closePaneButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 4)
        pane.closePaneButton = closePaneButton

        row.addArrangedSubview(accountButton)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(closePaneButton)

        let address = UITextField()
        address.placeholder = "Search or enter address"
        address.text = startURL.absoluteString
        address.font = .systemFont(ofSize: 14)
        address.textColor = BrowserTheme.textPrimary
        address.backgroundColor = BrowserTheme.card
        address.layer.cornerRadius = 10
        address.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        address.leftViewMode = .always
        address.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        address.rightViewMode = .always
        address.returnKeyType = .go
        address.keyboardType = .URL
        address.autocapitalizationType = .none
        address.autocorrectionType = .no
        address.clearButtonMode = .whileEditing
        address.delegate = self
        address.tag = side == .top ? 0 : 1
        address.snp.makeConstraints { $0.height.equalTo(34) }
        pane.addressField = address

        chrome.addArrangedSubview(row)
        chrome.addArrangedSubview(address)
        chrome.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        pane.chrome = chrome

        installWeb(in: pane, url: startURL)
        return wrap
    }

    private func refreshAccountButton(side: Side) {
        let pane = state(for: side)
        let color = AccountColor.color(for: pane.container)
        pane.accountButton?.setTitle(" \(pane.container.name) ", for: .normal)
        pane.accountButton?.setTitleColor(color, for: .normal)
        pane.accountButton?.tintColor = color
    }

    private func installWeb(in pane: PaneState, url: URL) {
        restoreBorrowedWeb(from: pane)
        if pane.borrowedTabID == nil {
            pane.web?.cleanup()
        }
        pane.web?.willMove(toParent: nil)
        pane.web?.view.removeFromSuperview()
        pane.web?.removeFromParent()
        pane.web = nil

        guard let wrap = pane.wrap, let chrome = pane.chrome else { return }
        let container = pane.container
        let liveTab = tabToBorrow(for: container)
        evictOtherWebViews(in: container.id, keeping: liveTab?.id)

        let web: WebViewController
        if let liveTab, let borrowed = borrowLiveWeb(from: liveTab) {
            web = borrowed
            pane.borrowedTabID = liveTab.id
        } else {
            pane.borrowedTabID = nil
            web = WebViewController(
                isIncognito: false,
                websiteDataStore: TabSessionStore.dataStore(for: container.sessionID),
                geoConfiguration: .from(container: container),
                identityProfile: container.identity,
                tabUserAgentSettings: tabManager.userAgentSettings(forContainer: container.id),
                containerID: container.id
            )
        }

        addChild(web)
        wrap.addSubview(web.view)
        web.view.snp.remakeConstraints { make in
            make.top.equalTo(chrome.snp.bottom).offset(2)
            make.leading.trailing.bottom.equalToSuperview()
        }
        web.didMove(toParent: self)
        pane.web = web

        let currentHost = web.webView?.url?.host
        let targetHost = url.host
        if pane.borrowedTabID != nil, currentHost != nil, currentHost == targetHost {
            pane.addressField?.text = web.webView?.url?.absoluteString ?? url.absoluteString
        } else {
            web.load(url: url)
            pane.addressField?.text = url.absoluteString
        }
    }

    private func tabToBorrow(for container: BrowserContainer) -> BrowserTab? {
        let candidates = tabManager.tabs.filter {
            !$0.isIncognito && $0.containerID == container.id && $0.webController != nil
        }
        return candidates.first(where: { $0.id == tabManager.selectedTab?.id })
            ?? candidates.max(by: { $0.lastAccessed < $1.lastAccessed })
    }

    private func borrowLiveWeb(from tab: BrowserTab) -> WebViewController? {
        guard let web = tab.webController else { return nil }
        findBrowserViewController()?.detachEmbeddedIfNeeded(web)
        web.willMove(toParent: nil)
        web.view.removeFromSuperview()
        web.removeFromParent()
        tab.webController = web
        return web
    }

    private func restoreBorrowedWeb(from pane: PaneState) {
        guard let tabID = pane.borrowedTabID, let web = pane.web else { return }
        pane.borrowedTabID = nil
        pane.web = nil
        web.willMove(toParent: nil)
        web.view.removeFromSuperview()
        web.removeFromParent()
        if let tab = tabManager.tabs.first(where: { $0.id == tabID }) {
            tab.webController = web
        }
    }

    /// WhatsApp Web (and similar) keep one IndexedDB session per store — a second WKWebView logs everyone out.
    private func evictOtherWebViews(in containerID: UUID, keeping keepID: UUID?) {
        for tab in tabManager.tabs where tab.containerID == containerID && tab.id != keepID {
            guard tab.webController != nil else { continue }
            findBrowserViewController()?.detachEmbeddedIfNeeded(tab.webController!)
            tab.webController?.cleanup()
            tab.webController = nil
        }
    }

    private func availableAccounts(excluding otherID: UUID?) -> [BrowserContainer] {
        tabManager.sortedContainers.filter {
            $0.id != otherID
        }
    }

    @objc private func accountTapped(_ sender: UIButton) {
        let side: Side = sender.tag == 0 ? .top : .bottom
        let pane = state(for: side)
        let other = state(for: side == .top ? .bottom : .top).container.id
        let options = availableAccounts(excluding: nil)
        guard !options.isEmpty else { return }

        let sheet = UIAlertController(
            title: "Account",
            message: "Choose which account this pane uses.",
            preferredStyle: .actionSheet
        )
        for container in options {
            let title = container.id == pane.container.id
                ? "\(container.name) ✓"
                : container.name
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.switchAccount(side: side, to: container, avoiding: other)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sender
            pop.sourceRect = sender.bounds
        }
        present(sheet, animated: true)
    }

    private func switchAccount(side: Side, to container: BrowserContainer, avoiding otherID: UUID) {
        let pane = state(for: side)
        guard container.id != pane.container.id else { return }
        // If picking the other pane's account, swap the two panes' accounts.
        let otherSide: Side = side == .top ? .bottom : .top
        let otherPane = state(for: otherSide)
        let currentURL = pane.web?.webView?.url ?? URL(string: pane.addressField?.text ?? "") ?? startURL
        let otherURL = otherPane.web?.webView?.url ?? URL(string: otherPane.addressField?.text ?? "") ?? startURL

        if container.id == otherID {
            let previous = pane.container
            pane.container = container
            otherPane.container = previous
            refreshAccountButton(side: side)
            refreshAccountButton(side: otherSide)
            installWeb(in: pane, url: currentURL)
            installWeb(in: otherPane, url: otherURL)
            return
        }

        pane.container = container
        refreshAccountButton(side: side)
        installWeb(in: pane, url: currentURL)
    }

    @objc private func closePaneTapped(_ sender: UIButton) {
        // Close this pane; keep the other account + URL and exit Split View.
        let closing: Side = sender.tag == 0 ? .top : .bottom
        let keeping = state(for: closing == .top ? .bottom : .top)
        let url = keeping.web?.webView?.url
            ?? keeping.addressField?.text.flatMap { URLInputResolver.resolve($0) }
        finish(keeping: keeping.container.id, url: url)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        let side: Side = textField.tag == 0 ? .top : .bottom
        let raw = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return false }
        let url = URLInputResolver.resolve(raw)
        textField.text = url.absoluteString
        state(for: side).web?.load(url: url)
        return true
    }

    @objc private func keyboardWillChange(_ note: Notification) {
        // Keep address fields usable; no extra inset needed for equal split panes.
        _ = note
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        _ = note
    }

    private func finish(keeping accountID: UUID?, url: URL?) {
        guard !didClose else { return }
        didClose = true
        view.endEditing(true)
        restoreBorrowedWeb(from: topState)
        restoreBorrowedWeb(from: bottomState)
        topState.web?.cleanup()
        bottomState.web?.cleanup()
        topState.web = nil
        bottomState.web = nil

        let browser = findBrowserViewController()
        let complete: () -> Void = { [weak self] in
            guard let self else { return }
            if let accountID {
                if let delegate = self.delegate {
                    delegate.dualAccountCompare(self, didKeepAccount: accountID, url: url)
                } else {
                    browser?.applySplitViewKeep(accountID: accountID, url: url)
                }
            } else {
                self.delegate?.dualAccountCompareDidClose(self)
            }
        }

        // Dismiss the whole modal chain from the browser so we never land back on
        // Account Manager / Wow sheets underneath Split View.
        if let browser, browser.presentedViewController != nil {
            browser.dismiss(animated: true, completion: complete)
        } else {
            dismiss(animated: true, completion: complete)
        }
    }

    private func findBrowserViewController() -> BrowserViewController? {
        var current: UIViewController? = presentingViewController
        while let vc = current {
            if let browser = vc as? BrowserViewController { return browser }
            if let nav = vc as? UINavigationController,
               let browser = nav.viewControllers.compactMap({ $0 as? BrowserViewController }).first {
                return browser
            }
            current = vc.presentingViewController
        }
        return view.window?.rootViewController.flatMap { root in
            if let browser = root as? BrowserViewController { return browser }
            if let nav = root as? UINavigationController {
                return nav.viewControllers.compactMap({ $0 as? BrowserViewController }).first
            }
            return root.children.compactMap({ $0 as? BrowserViewController }).first
        }
    }
}
