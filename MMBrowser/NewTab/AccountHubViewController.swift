import UIKit
import SnapKit
import ObjectiveC

protocol AccountHubViewControllerDelegate: AnyObject {
    func accountHubDidRequestClose(_ hub: AccountHubViewController)
    func accountHubDidRequestSettings(_ hub: AccountHubViewController)
    func accountHubDidRequestManageAccounts(_ hub: AccountHubViewController)
    func accountHub(_ hub: AccountHubViewController, didSelectTabID tabID: UUID, accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestNewTabInAccount accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestOpenURL url: URL, accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestMenuAction action: MenuAction)
}

/// Account home hub: replaces NTP and is also presented fullscreen from Tabs / Account.
final class AccountHubViewController: UIViewController, UITextFieldDelegate, UIGestureRecognizerDelegate {
    weak var delegate: AccountHubViewControllerDelegate?

    private(set) var isOverlay = false

    private weak var tabManager: TabManager?
    private(set) var previewAccountID: UUID?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let closeButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let searchField = UITextField()

    private let accountPillsScroll = UIScrollView()
    private let accountPillsStack = UIStackView()
    private let addAccountButton = UIButton(type: .system)

    private let mainPanel = UIView()
    private let mainPanelStack = UIStackView()

    private let shortcutsGrid = UIStackView()
    private let tabsHeader = UIView()
    private let tabsCloseAllButton = UIButton(type: .system)
    private let tabsScroll = HubHorizontalScrollView()
    private let tabsStack = UIStackView()

    private let historyHeader = HubSectionHeaderButton()
    private let historyBody = UIStackView()
    private let bookmarksHeader = HubSectionHeaderButton()
    private let bookmarksBody = UIStackView()

    private let toolsCard = UIView()
    private let toolsGrid = UIStackView()
    private let extrasCard = UIView()
    private let extrasGrid = UIStackView()

    private var historyExpanded = false
    private var bookmarksExpanded = false

    convenience init(tabManager: TabManager, previewAccountID: UUID?, isOverlay: Bool) {
        self.init(nibName: nil, bundle: nil)
        self.tabManager = tabManager
        self.previewAccountID = previewAccountID ?? tabManager.selectedTab?.containerID ?? tabManager.defaultContainer.id
        self.isOverlay = isOverlay
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        setupChrome()
        reloadAll()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(directoryChanged), name: .navigationDirectoryChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(homeSettingsChanged), name: .homeSettingsChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func updatePreviewAccount(_ id: UUID) {
        previewAccountID = id
        reloadAll()
    }

    func reloadFromExternalChange() {
        guard isViewLoaded else { return }
        reloadAll()
    }

    @objc private func themeChanged() {
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        reloadAll()
    }

    @objc private func directoryChanged() { reloadShortcuts() }
    @objc private func homeSettingsChanged() {
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        reloadAll()
    }

    // MARK: - Layout

    private func setupChrome() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.isDirectionalLockEnabled = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)

        scrollView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-28)
            make.width.equalTo(scrollView).offset(-32)
        }

        configureTopSearchRow()
        configureAccountPills()
        configureSearchField()
        configureTabsHeader()
        configureMainPanel()
        configureToolsCards()

        contentStack.addArrangedSubview(makeTopSearchRow())
        contentStack.addArrangedSubview(makePillsRow())
        contentStack.addArrangedSubview(mainPanel)
        contentStack.addArrangedSubview(makeSectionTitle("Tools"))
        contentStack.addArrangedSubview(toolsCard)
        contentStack.addArrangedSubview(extrasCard)

        shortcutsGrid.axis = .vertical
        shortcutsGrid.spacing = 10
        shortcutsGrid.alignment = .fill

        tabsScroll.showsHorizontalScrollIndicator = false
        tabsScroll.alwaysBounceHorizontal = true
        tabsScroll.isDirectionalLockEnabled = true
        tabsScroll.delaysContentTouches = false
        tabsScroll.canCancelContentTouches = true
        tabsStack.axis = .horizontal
        tabsStack.spacing = 12
        tabsStack.alignment = .fill
        tabsScroll.addSubview(tabsStack)
        tabsStack.snp.makeConstraints { make in
            make.top.bottom.leading.trailing.equalTo(tabsScroll.contentLayoutGuide)
            make.height.equalTo(tabsScroll.frameLayoutGuide)
        }
        tabsScroll.snp.makeConstraints { $0.height.equalTo(176) }

        historyBody.axis = .vertical
        historyBody.spacing = 0
        bookmarksBody.axis = .vertical
        bookmarksBody.spacing = 0

        historyHeader.addTarget(self, action: #selector(toggleHistory), for: .touchUpInside)
        bookmarksHeader.addTarget(self, action: #selector(toggleBookmarks), for: .touchUpInside)
    }

    private func configureMainPanel() {
        mainPanel.backgroundColor = BrowserTheme.elevated
        mainPanel.layer.cornerRadius = 20
        mainPanel.clipsToBounds = true // keep inner content inside rounded theme panel

        mainPanelStack.axis = .vertical
        mainPanelStack.spacing = 16
        mainPanelStack.alignment = .fill
        mainPanel.addSubview(mainPanelStack)
        mainPanelStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12))
        }

        mainPanelStack.addArrangedSubview(shortcutsGrid)
        mainPanelStack.addArrangedSubview(tabsHeader)
        mainPanelStack.addArrangedSubview(tabsScroll)
        mainPanelStack.addArrangedSubview(historyHeader)
        mainPanelStack.addArrangedSubview(historyBody)
        mainPanelStack.addArrangedSubview(bookmarksHeader)
        mainPanelStack.addArrangedSubview(bookmarksBody)
    }

    private func configureTopSearchRow() {
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), for: .normal)
        closeButton.tintColor = .black
        closeButton.backgroundColor = BrowserTheme.chromeBlue
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.snp.makeConstraints { $0.size.equalTo(32) }

        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.tintColor = BrowserTheme.textPrimary
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        settingsButton.snp.makeConstraints { $0.size.equalTo(32) }
    }

    private func makeTopSearchRow() -> UIView {
        let row = UIStackView(arrangedSubviews: [closeButton, searchField, settingsButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
    }

    private func configureAccountPills() {
        accountPillsScroll.showsHorizontalScrollIndicator = false
        accountPillsScroll.alwaysBounceHorizontal = true
        accountPillsScroll.isDirectionalLockEnabled = true
        accountPillsStack.axis = .horizontal
        accountPillsStack.spacing = 20
        accountPillsStack.alignment = .center
        accountPillsScroll.addSubview(accountPillsStack)
        accountPillsStack.snp.makeConstraints { make in
            make.top.bottom.leading.trailing.equalTo(accountPillsScroll.contentLayoutGuide)
            make.height.equalTo(accountPillsScroll.frameLayoutGuide)
        }

        addAccountButton.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)), for: .normal)
        addAccountButton.tintColor = BrowserTheme.textPrimary
        addAccountButton.backgroundColor = BrowserTheme.elevated
        addAccountButton.layer.cornerRadius = 18
        addAccountButton.accessibilityLabel = "Manage accounts"
        addAccountButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.accountHubDidRequestManageAccounts(self)
        }, for: .touchUpInside)
        addAccountButton.snp.makeConstraints { $0.size.equalTo(36) }
    }

    private func makePillsRow() -> UIView {
        let row = UIView()
        row.snp.makeConstraints { $0.height.equalTo(36) }

        accountPillsScroll.clipsToBounds = true
        accountPillsScroll.showsHorizontalScrollIndicator = false

        addAccountButton.setContentHuggingPriority(.required, for: .horizontal)
        addAccountButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(accountPillsScroll)
        row.addSubview(addAccountButton)
        addAccountButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.size.equalTo(36)
        }
        accountPillsScroll.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(addAccountButton.snp.leading).offset(-10)
        }
        row.bringSubviewToFront(addAccountButton)
        return row
    }

    private func configureSearchField() {
        searchField.delegate = self
        searchField.returnKeyType = .go
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.keyboardType = .URL
        searchField.clearButtonMode = .whileEditing
        searchField.font = .systemFont(ofSize: 16)
        searchField.textColor = BrowserTheme.textPrimary
        searchField.backgroundColor = BrowserTheme.elevated
        searchField.layer.cornerRadius = 22
        searchField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        searchField.leftViewMode = .always
        searchField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 44))
        searchField.rightViewMode = .always
        searchField.snp.makeConstraints { $0.height.equalTo(44) }
        updateSearchPlaceholder()
    }

    private func configureTabsHeader() {
        let title = UILabel()
        title.text = "Tabs"
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = BrowserTheme.textPrimary

        tabsCloseAllButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        tabsCloseAllButton.tintColor = BrowserTheme.textSecondary
        tabsCloseAllButton.backgroundColor = BrowserTheme.card
        tabsCloseAllButton.layer.cornerRadius = 12
        tabsCloseAllButton.accessibilityLabel = "Close all tabs"
        tabsCloseAllButton.addTarget(self, action: #selector(closeAllPreviewTabs), for: .touchUpInside)

        tabsHeader.addSubview(title)
        tabsHeader.addSubview(tabsCloseAllButton)
        title.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
        }
        tabsCloseAllButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.size.equalTo(24)
            make.leading.greaterThanOrEqualTo(title.snp.trailing).offset(8)
        }
        tabsHeader.snp.makeConstraints { $0.height.equalTo(28) }
    }

    private func configureToolsCards() {
        styleCard(toolsCard)
        styleCard(extrasCard)

        toolsGrid.axis = .vertical
        toolsGrid.spacing = 14
        toolsCard.addSubview(toolsGrid)
        toolsGrid.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10))
        }

        extrasGrid.axis = .vertical
        extrasGrid.spacing = 14
        extrasCard.addSubview(extrasGrid)
        extrasGrid.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10))
        }

        fillActionGrid(
            toolsGrid,
            columns: 5,
            items: [
                ("Settings", "gearshape", .settings),
                ("Accounts", "person.2", .accounts),
                ("Split View", "rectangle.split.1x2", .compareAccounts),
                ("New tab", "plus.square", .newTab),
                ("Incognito tab", "theatermasks", .newIncognitoTab),
                ("Passwords", "key", .passwords),
                ("Downloads (Shared)", "arrow.down.circle", .downloads),
                ("Bookmarks (Isolated)", "bookmark", .bookmarks),
                ("History (Isolated)", "clock", .history),
                ("Reading list (Shared)", "text.book.closed", .readingList)
            ]
        )
        fillActionGrid(
            extrasGrid,
            columns: 5,
            items: [
                ("Background gallery", "photo.on.rectangle", .backgroundGallery),
                ("Theme", "paintpalette", .theme),
                ("Feedback", "bubble.left", .feedback)
            ]
        )
    }

    private func styleCard(_ card: UIView) {
        card.backgroundColor = BrowserTheme.elevated
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
    }

    private func updateSearchPlaceholder() {
        let name = SearchEngineManager.current.name
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search \(name) or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = BrowserTheme.textPrimary
        return label
    }

    // MARK: - Reload

    private func reloadAll() {
        updateSearchPlaceholder()
        reloadAccountPills()
        reloadShortcuts()
        reloadTabs()
        reloadHistory()
        reloadBookmarks()
        toolsCard.backgroundColor = BrowserTheme.elevated
        extrasCard.backgroundColor = BrowserTheme.elevated
        mainPanel.backgroundColor = BrowserTheme.elevated
        closeButton.backgroundColor = BrowserTheme.chromeBlue
        settingsButton.tintColor = BrowserTheme.textPrimary
        addAccountButton.backgroundColor = BrowserTheme.elevated
        addAccountButton.tintColor = BrowserTheme.textPrimary
        tabsCloseAllButton.backgroundColor = BrowserTheme.card
        tabsCloseAllButton.tintColor = BrowserTheme.textSecondary
        searchField.backgroundColor = BrowserTheme.elevated
        searchField.textColor = BrowserTheme.textPrimary
    }

    private func resolvedPreviewID() -> UUID {
        if let previewAccountID, tabManager?.container(id: previewAccountID) != nil {
            return previewAccountID
        }
        return tabManager?.selectedTab?.containerID
            ?? tabManager?.defaultContainer.id
            ?? UUID()
    }

    private func reloadAccountPills() {
        accountPillsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let tabManager else { return }
        let preview = resolvedPreviewID()
        for container in tabManager.sortedContainers {
            let selected = container.id == preview
            let wrap = UIView()
            let button = UIButton(type: .system)
            button.setTitle(container.name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: selected ? .semibold : .regular)
            button.setTitleColor(selected ? BrowserTheme.textPrimary : BrowserTheme.textSecondary, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 2, bottom: 8, right: 2)
            button.addAction(UIAction { [weak self] _ in
                self?.previewAccountID = container.id
                self?.reloadAll()
            }, for: .touchUpInside)

            let underline = UIView()
            underline.backgroundColor = BrowserTheme.textPrimary
            underline.isHidden = !selected
            underline.layer.cornerRadius = 1

            wrap.addSubview(button)
            wrap.addSubview(underline)
            button.snp.makeConstraints { $0.edges.equalToSuperview() }
            underline.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview()
                make.bottom.equalToSuperview()
                make.height.equalTo(2)
            }
            accountPillsStack.addArrangedSubview(wrap)
        }
        accountPillsStack.snp.remakeConstraints { make in
            make.top.bottom.leading.trailing.equalTo(accountPillsScroll.contentLayoutGuide)
            make.height.equalTo(accountPillsScroll.frameLayoutGuide)
        }
    }

    private func reloadShortcuts() {
        shortcutsGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let accountID = resolvedPreviewID()
        var sites: [NavigationSite] = []
        var seen = Set<String>()
        for category in NavigationStore.shared.categories(for: accountID) {
            for site in category.sites {
                let key = site.urlString.lowercased()
                guard seen.insert(key).inserted else { continue }
                sites.append(site)
            }
        }
        if sites.isEmpty {
            sites = NavigationDirectory.defaultHomeSites
        }

        let columns = 3
        var row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually

        for (index, site) in sites.enumerated() {
            if index > 0, index % columns == 0 {
                while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
                shortcutsGrid.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.spacing = 10
                row.distribution = .fillEqually
            }
            row.addArrangedSubview(makeShortcutCard(site))
        }
        while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
        if !row.arrangedSubviews.isEmpty {
            shortcutsGrid.addArrangedSubview(row)
        }
    }

    private func makeShortcutCard(_ site: NavigationSite) -> UIView {
        let card = UIView()
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 18
        card.clipsToBounds = true

        let iconWell = UIView()
        iconWell.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        iconWell.layer.cornerRadius = 14
        iconWell.clipsToBounds = true

        let icon = FaviconImageView()
        icon.setLogo(assetName: site.logoAssetName, urlString: site.urlString, fallbackTitle: site.title)

        let label = UILabel()
        label.text = site.title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = BrowserTheme.textPrimary
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail

        let button = UIButton(type: .system)
        button.accessibilityLabel = site.title
        button.addAction(UIAction { [weak self] _ in
            guard let self, let url = site.url else { return }
            self.delegate?.accountHub(self, didRequestOpenURL: url, accountID: self.resolvedPreviewID())
        }, for: .touchUpInside)

        card.addSubview(iconWell)
        iconWell.addSubview(icon)
        card.addSubview(label)
        card.addSubview(button)
        iconWell.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.centerX.equalToSuperview()
            make.size.equalTo(44)
        }
        icon.snp.makeConstraints { $0.edges.equalToSuperview().inset(6) }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().offset(-14)
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return card
    }

    private func reloadTabs() {
        tabsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let tabManager else {
            tabsHeader.isHidden = true
            tabsScroll.isHidden = true
            return
        }
        let accountID = resolvedPreviewID()
        let accountName = tabManager.container(id: accountID)?.name ?? "Account"
        let tabs = tabManager.tabs.filter {
            !$0.isIncognito && $0.containerID == accountID && !$0.isNewTabPage
        }
        let selectedID = tabManager.selectedTab?.id
        let hasTabs = !tabs.isEmpty
        tabsHeader.isHidden = !hasTabs
        tabsScroll.isHidden = !hasTabs
        guard hasTabs else { return }

        for tab in tabs {
            let title: String
            if let host = tab.url?.host, !host.isEmpty {
                title = host
            } else {
                title = tab.title.isEmpty ? "Page" : tab.title
            }
            tabsStack.addArrangedSubview(makeTabCard(
                title: title,
                accountName: accountName,
                snapshot: tab.snapshot,
                tabID: tab.id,
                accountID: accountID,
                isSelected: tab.id == selectedID,
                showsClose: true
            ))
        }
    }

    private func makeTabCard(
        title: String,
        accountName: String,
        snapshot: UIImage?,
        tabID: UUID?,
        accountID: UUID,
        isSelected: Bool,
        showsClose: Bool
    ) -> UIView {
        let glow = UIColor(red: 0.62, green: 0.42, blue: 1.0, alpha: 1)

        let card = UIView()
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.layer.borderWidth = isSelected ? 1.5 : 0
        card.layer.borderColor = isSelected ? glow.cgColor : nil
        card.clipsToBounds = true
        card.snp.makeConstraints { $0.width.equalTo(158) }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail

        let folder = UIImageView(image: UIImage(systemName: "folder.fill"))
        folder.tintColor = BrowserTheme.textSecondary
        folder.contentMode = .scaleAspectFit

        let accountLabel = UILabel()
        accountLabel.text = accountName
        accountLabel.font = .systemFont(ofSize: 11, weight: .medium)
        accountLabel.textColor = BrowserTheme.textSecondary

        let accountRow = UIStackView(arrangedSubviews: [folder, accountLabel])
        accountRow.axis = .horizontal
        accountRow.alignment = .center
        accountRow.spacing = 4
        folder.snp.makeConstraints { $0.size.equalTo(11) }

        let preview = UIImageView(image: snapshot)
        preview.contentMode = .scaleAspectFill
        preview.backgroundColor = BrowserTheme.card
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 10
        if snapshot == nil {
            let placeholder = UILabel()
            placeholder.text = "Page"
            placeholder.textColor = BrowserTheme.textSecondary
            placeholder.font = .systemFont(ofSize: 14, weight: .medium)
            placeholder.textAlignment = .center
            preview.addSubview(placeholder)
            placeholder.snp.makeConstraints { $0.center.equalToSuperview() }
        }

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = BrowserTheme.textSecondary
        close.isHidden = !showsClose || tabID == nil
        if showsClose, let tabID {
            close.addAction(UIAction { [weak self] _ in
                self?.tabManager?.closeTab(id: tabID)
                self?.reloadTabs()
            }, for: .touchUpInside)
        }

        card.addSubview(titleLabel)
        card.addSubview(accountRow)
        card.addSubview(preview)
        card.addSubview(close)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(10)
            make.trailing.lessThanOrEqualTo(close.snp.leading).offset(-4)
        }
        close.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(6)
            make.size.equalTo(24)
        }
        accountRow.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(3)
            make.leading.equalToSuperview().inset(10)
            make.trailing.lessThanOrEqualToSuperview().inset(10)
        }
        preview.snp.makeConstraints { make in
            make.top.equalTo(accountRow.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview().inset(8)
            make.height.equalTo(110)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(tabCardTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        tap.require(toFail: tabsScroll.panGestureRecognizer)
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true
        card.accessibilityTraits = .button
        objc_setAssociatedObject(
            card,
            &AssociatedKeys.tabCardPayload,
            TabCardPayload(tabID: tabID, accountID: accountID),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        return card
    }

    @objc private func tabCardTapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended,
              let card = gesture.view,
              let payload = objc_getAssociatedObject(card, &AssociatedKeys.tabCardPayload) as? TabCardPayload
        else { return }
        if let tabID = payload.tabID {
            delegate?.accountHub(self, didSelectTabID: tabID, accountID: payload.accountID)
        } else {
            delegate?.accountHub(self, didRequestNewTabInAccount: payload.accountID)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            view = current.superview
        }
        return true
    }

    private func reloadHistory() {
        let accountID = resolvedPreviewID()
        let all = HistoryStore.shared.items(containerID: accountID)
        let items = Array(all.prefix(8))
        let hasItems = !all.isEmpty
        historyHeader.isHidden = !hasItems
        historyHeader.configure(title: "History", count: all.count, expanded: historyExpanded)
        historyBody.arrangedSubviews.forEach { $0.removeFromSuperview() }
        historyBody.isHidden = !hasItems || !historyExpanded
        guard hasItems, historyExpanded else { return }
        historyBody.addArrangedSubview(makeListCard(items.map { ($0.title, $0.url) }))
    }

    private func reloadBookmarks() {
        let accountID = resolvedPreviewID()
        let all = BookmarkStore.shared.items(containerID: accountID)
        let items = Array(all.prefix(8))
        let hasItems = !all.isEmpty
        bookmarksHeader.isHidden = !hasItems
        bookmarksHeader.configure(title: "Bookmarks", count: all.count, expanded: bookmarksExpanded)
        bookmarksBody.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bookmarksBody.isHidden = !hasItems || !bookmarksExpanded
        guard hasItems, bookmarksExpanded else { return }
        bookmarksBody.addArrangedSubview(makeListCard(items.map { ($0.title, $0.url) }))
    }

    private func makeListCard(_ rows: [(String, URL?)]) -> UIView {
        let card = UIView()
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        card.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }

        if rows.isEmpty {
            let empty = UILabel()
            empty.text = "None yet"
            empty.textColor = BrowserTheme.textSecondary
            empty.font = .systemFont(ofSize: 14)
            empty.textAlignment = .center
            empty.snp.makeConstraints { $0.height.equalTo(44) }
            stack.addArrangedSubview(empty)
            return card
        }

        for (index, row) in rows.enumerated() {
            let button = UIButton(type: .system)
            button.contentHorizontalAlignment = .leading
            button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
            button.setTitle(row.0, for: .normal)
            button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            if let url = row.1 {
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.accountHub(self, didRequestOpenURL: url, accountID: self.resolvedPreviewID())
                }, for: .touchUpInside)
            }
            stack.addArrangedSubview(button)
            if index < rows.count - 1 {
                let line = UIView()
                line.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.12)
                line.snp.makeConstraints { $0.height.equalTo(1 / UIScreen.main.scale) }
                stack.addArrangedSubview(line)
            }
        }
        return card
    }

    private func fillActionGrid(
        _ grid: UIStackView,
        columns: Int,
        items: [(String, String, MenuAction)]
    ) {
        grid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 4

        for (index, item) in items.enumerated() {
            if index > 0, index % columns == 0 {
                while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
                grid.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.distribution = .fillEqually
                row.spacing = 4
            }
            row.addArrangedSubview(makeToolButton(title: item.0, systemName: item.1, action: item.2))
        }
        while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
        if !row.arrangedSubviews.isEmpty {
            grid.addArrangedSubview(row)
        }
    }

    private func makeToolButton(title: String, systemName: String, action: MenuAction) -> UIView {
        let wrap = UIView()

        let icon = UIImageView(image: UIImage(systemName: systemName))
        icon.tintColor = BrowserTheme.textPrimary
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = BrowserTheme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 2

        let button = UIButton(type: .system)
        button.accessibilityLabel = title
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if action == .accounts {
                self.delegate?.accountHubDidRequestManageAccounts(self)
            } else if action == .newTab {
                self.delegate?.accountHub(self, didRequestNewTabInAccount: self.resolvedPreviewID())
            } else {
                self.delegate?.accountHub(self, didRequestMenuAction: action)
            }
        }, for: .touchUpInside)

        wrap.addSubview(icon)
        wrap.addSubview(label)
        wrap.addSubview(button)
        icon.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.centerX.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(icon.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return wrap
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        delegate?.accountHubDidRequestClose(self)
    }

    @objc private func settingsTapped() {
        delegate?.accountHubDidRequestSettings(self)
    }

    @objc private func closeAllPreviewTabs() {
        guard let tabManager else { return }
        let accountID = resolvedPreviewID()
        let ids = tabManager.tabs
            .filter { !$0.isIncognito && $0.containerID == accountID }
            .map(\.id)
        for id in ids {
            tabManager.closeTab(id: id)
        }
        reloadTabs()
    }

    @objc private func toggleHistory() {
        historyExpanded.toggle()
        reloadHistory()
    }

    @objc private func toggleBookmarks() {
        bookmarksExpanded.toggle()
        reloadBookmarks()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let raw = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        textField.resignFirstResponder()
        guard !raw.isEmpty else { return false }
        let url = URLInputResolver.resolve(raw)
        delegate?.accountHub(self, didRequestOpenURL: url, accountID: resolvedPreviewID())
        return true
    }
}

// MARK: - Horizontal tabs scroller

/// Prefers horizontal pans so Tabs can scroll inside the vertical hub page.
private final class HubHorizontalScrollView: UIScrollView, UIGestureRecognizerDelegate {
    override init(frame: CGRect) {
        super.init(frame: frame)
        panGestureRecognizer.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = panGestureRecognizer.velocity(in: self)
        // Claim horizontal swipes; let the parent vertical scroll handle vertical ones.
        return abs(velocity.x) >= abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === panGestureRecognizer
            && otherGestureRecognizer is UIPanGestureRecognizer
    }
}

// MARK: - Tab card payload

private final class TabCardPayload: NSObject {
    let tabID: UUID?
    let accountID: UUID

    init(tabID: UUID?, accountID: UUID) {
        self.tabID = tabID
        self.accountID = accountID
    }
}

private enum AssociatedKeys {
    static var tabCardPayload: UInt8 = 0
}

// MARK: - Section header

private final class HubSectionHeaderButton: UIButton {
    private let title = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = BrowserTheme.textPrimary
        chevron.tintColor = BrowserTheme.textSecondary
        chevron.contentMode = .scaleAspectFit
        addSubview(title)
        addSubview(chevron)
        title.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        chevron.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(16)
            make.leading.greaterThanOrEqualTo(title.snp.trailing).offset(8)
        }
        snp.makeConstraints { $0.height.equalTo(28) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title text: String, count: Int, expanded: Bool) {
        title.text = "\(text)(\(count))"
        chevron.image = UIImage(systemName: expanded ? "chevron.up" : "chevron.down")
        title.textColor = BrowserTheme.textPrimary
        chevron.tintColor = BrowserTheme.textSecondary
    }
}
