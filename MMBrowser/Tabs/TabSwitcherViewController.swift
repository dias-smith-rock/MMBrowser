import UIKit
import SnapKit

protocol TabSwitcherViewControllerDelegate: AnyObject {
    func tabSwitcherDidClose()
    /// `containerID` is the container for the new normal tab (selected tab / active filter).
    func tabSwitcherDidRequestNewTab(incognito: Bool, containerID: UUID?)
    func tabSwitcherDidRequestOpenURLInNewTab(_ url: URL, containerID: UUID?)
}

final class TabSwitcherViewController: UIViewController {
    weak var delegate: TabSwitcherViewControllerDelegate?

    private enum Surface: Int {
        case incognito = 0
        case allTabs = 1
        case accounts = 2
    }

    private let tabManager: TabManager
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: Constraint?
    private let topBar = UIView()
    private var modeControl = UISegmentedControl(items: ["", "", ""])
    private let doneButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let mainScroll = UIScrollView()
    private let contentStack = UIStackView()
    private let accountsStack = UIStackView()
    private let bookmarksSection = UIStackView()
    private let historySection = UIStackView()
    private let bookmarksTable = UITableView(frame: .zero, style: .plain)
    private let historyTable = UITableView(frame: .zero, style: .plain)
    private var bookmarksHeightConstraint: Constraint?
    private var historyHeightConstraint: Constraint?
    private weak var presentedAccountPopup: AccountTabsPopupViewController?
    private var bookmarkItems: [BookmarkItem] = []
    private var historyItems: [HistoryItem] = []
    private var bookmarksExpanded = false
    private var historyExpanded = false
    private weak var bookmarksHeaderButton: UIButton?
    private weak var historyHeaderButton: UIButton?
    private var searchQuery = ""
    private var surface: Surface

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        if tabManager.selectedTab?.isIncognito == true {
            self.surface = .incognito
        } else {
            self.surface = .accounts
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var showingIncognito: Bool { surface == .incognito }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsAccountOverview: Bool {
        surface == .accounts && !isSearching
    }

    private var poolTabs: [BrowserTab] {
        showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
    }

    private var displayedTabs: [BrowserTab] {
        if showsAccountOverview { return [] }
        let base = poolTabs
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            let name = tabManager.containerName(for: $0)
            return $0.title.lowercased().contains(q)
                || ($0.url?.absoluteString.lowercased().contains(q) ?? false)
                || name.lowercased().contains(q)
        }
    }

    /// Drag reorder on unfiltered All Tabs / Incognito grids only.
    private var canReorderTabs: Bool {
        !isSearching && (surface == .allTabs || surface == .incognito)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyChrome()
        setupTop()
        setupMainScroll()
        setupBottom()
        reload()
    }

    private func applyChrome() {
        view.backgroundColor = showingIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
        topBar.backgroundColor = .clear
        let accent = showingIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        addButton.backgroundColor = accent
        doneButton.setTitleColor(accent, for: .normal)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionHeight()
    }

    // MARK: - Top / detail chrome

    private func setupTop() {
        view.addSubview(topBar)

        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.tintColor = BrowserTheme.textPrimary
        search.accessibilityLabel = "Search tabs"
        search.addTarget(self, action: #selector(searchPlaceholder), for: .touchUpInside)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        let privateIcon = UIImage(systemName: "eyeglasses", withConfiguration: symbolConfig)
        let groupsIcon = UIImage(systemName: "square.grid.2x2", withConfiguration: symbolConfig)
        let countIcon = Self.makeTabCountBadge(count: 0, symbolConfig: symbolConfig)
        modeControl = UISegmentedControl(items: [privateIcon as Any, countIcon as Any, groupsIcon as Any])
        modeControl.selectedSegmentTintColor = BrowserTheme.secondaryCard
        modeControl.setTitleTextAttributes([.foregroundColor: BrowserTheme.textPrimary], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: BrowserTheme.textPrimary], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.accessibilityLabel = "Tabs mode"

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = BrowserTheme.textPrimary
        moreButton.accessibilityLabel = "More"
        moreButton.showsMenuAsPrimaryAction = true

        topBar.addSubview(search)
        topBar.addSubview(modeControl)
        topBar.addSubview(moreButton)
        topBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(48)
        }
        search.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(36)
        }
        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.size.equalTo(36)
        }
        modeControl.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.height.equalTo(32)
            make.width.equalTo(200)
            make.leading.greaterThanOrEqualTo(search.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-8)
        }
    }

    // MARK: - Main content

    private func setupMainScroll() {
        mainScroll.alwaysBounceVertical = true
        mainScroll.showsVerticalScrollIndicator = false
        view.addSubview(mainScroll)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        mainScroll.addSubview(contentStack)

        accountsStack.axis = .vertical
        accountsStack.spacing = 12
        accountsStack.alignment = .fill
        accountsStack.isLayoutMarginsRelativeArrangement = true
        accountsStack.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 0, right: 16)

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 4, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.reorderingCadence = .immediate
        collectionView.register(TabGridCell.self, forCellWithReuseIdentifier: TabGridCell.reuseID)

        configureListSection(bookmarksSection, title: "Bookmarks", table: bookmarksTable, kind: .bookmarks)
        configureListSection(historySection, title: "History", table: historyTable, kind: .history)

        contentStack.addArrangedSubview(accountsStack)
        contentStack.addArrangedSubview(collectionView)
        contentStack.addArrangedSubview(bookmarksSection)
        contentStack.addArrangedSubview(historySection)

        mainScroll.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-72)
        }
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(mainScroll)
        }
        collectionView.snp.makeConstraints { make in
            collectionHeightConstraint = make.height.equalTo(200).constraint
        }
    }

    private enum LibraryKind: Int { case bookmarks = 1, history = 2 }

    private func configureListSection(_ section: UIStackView, title: String, table: UITableView, kind: LibraryKind) {
        section.axis = .vertical
        section.spacing = 8
        section.alignment = .fill
        section.isLayoutMarginsRelativeArrangement = true
        section.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        section.isHidden = true

        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.baseForegroundColor = BrowserTheme.textPrimary
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 16, weight: .semibold)
            return outgoing
        }
        let header = UIButton(configuration: config)
        header.contentHorizontalAlignment = .fill
        header.tag = kind.rawValue
        header.accessibilityLabel = title
        header.addTarget(self, action: #selector(libraryHeaderTapped(_:)), for: .touchUpInside)
        section.addArrangedSubview(header)
        if kind == .bookmarks {
            bookmarksHeaderButton = header
        } else {
            historyHeaderButton = header
        }

        table.tag = kind.rawValue
        table.backgroundColor = .clear
        table.isScrollEnabled = false
        table.separatorInset = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 0)
        table.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.18)
        table.layer.cornerRadius = 12
        table.clipsToBounds = true
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "libraryCell")
        table.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        table.setContentHuggingPriority(.required, for: .vertical)
        section.clipsToBounds = true
        section.addArrangedSubview(table)
        table.snp.makeConstraints { make in
            if kind == .bookmarks {
                bookmarksHeightConstraint = make.height.equalTo(0).constraint
            } else {
                historyHeightConstraint = make.height.equalTo(0).constraint
            }
        }
    }

    @objc private func libraryHeaderTapped(_ sender: UIButton) {
        guard let kind = LibraryKind(rawValue: sender.tag) else { return }
        switch kind {
        case .bookmarks: bookmarksExpanded.toggle()
        case .history: historyExpanded.toggle()
        }
        applyLibraryExpansion(animated: true)
    }

    private func updateLibraryHeader(_ button: UIButton?, title: String, expanded: Bool, count: Int) {
        guard var config = button?.configuration else { return }
        config.title = count > 0 ? "\(title) (\(count))" : title
        config.image = UIImage(
            systemName: expanded ? "chevron.down" : "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        button?.configuration = config
        button?.accessibilityHint = expanded ? "Collapse" : "Expand"
    }

    private func applyLibraryExpansion(animated: Bool) {
        let bookmarkHeight = (bookmarksExpanded && !bookmarkItems.isEmpty)
            ? CGFloat(bookmarkItems.count) * 56 : 0
        let historyHeight = (historyExpanded && !historyItems.isEmpty)
            ? CGFloat(historyItems.count) * 56 : 0

        updateLibraryHeader(bookmarksHeaderButton, title: "Bookmarks", expanded: bookmarksExpanded, count: bookmarkItems.count)
        updateLibraryHeader(historyHeaderButton, title: "History", expanded: historyExpanded, count: historyItems.count)

        let updates = {
            self.bookmarksHeightConstraint?.update(offset: bookmarkHeight)
            self.historyHeightConstraint?.update(offset: historyHeight)
            self.bookmarksTable.alpha = bookmarkHeight > 0 ? 1 : 0
            self.historyTable.alpha = historyHeight > 0 ? 1 : 0
            self.contentStack.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: updates)
        } else {
            updates()
        }
    }

    private func setupBottom() {
        addButton.backgroundColor = BrowserTheme.chromeBlue
        addButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addButton.tintColor = .white
        addButton.layer.cornerRadius = 28
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        view.addSubview(addButton)
        view.addSubview(doneButton)
        addButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-12)
            make.size.equalTo(56)
        }
        doneButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-24)
            make.centerY.equalTo(addButton)
        }
    }

    // MARK: - Reload / layout mode

    private func reload() {
        modeControl.selectedSegmentIndex = surface.rawValue
        let normalCount = tabManager.normalTabs.count
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        modeControl.setImage(
            Self.makeTabCountBadge(count: normalCount, symbolConfig: symbolConfig),
            forSegmentAt: Surface.allTabs.rawValue
        )
        moreButton.menu = makeMoreMenu()
        applyChrome()
        applySurfaceLayout()
        rebuildAccountCards()
        collectionView.reloadData()
        updateCollectionHeight()
        rebuildLibrarySections()
    }

    /// Refresh tab cards after async webpage snapshots finish.
    func reloadPreviews() {
        guard isViewLoaded else { return }
        collectionView.reloadData()
        rebuildAccountCards()
        presentedAccountPopup?.reloadPreviews()
    }

    /// Number badge framed to match `square.grid.2x2` segment icon size.
    private static func makeTabCountBadge(count: Int, symbolConfig: UIImage.SymbolConfiguration) -> UIImage {
        let reference = UIImage(systemName: "square.grid.2x2", withConfiguration: symbolConfig)
            ?? UIImage()
        let side = max(ceil(max(reference.size.width, reference.size.height)), 20)
        let size = CGSize(width: side, height: side)
        let text = count > 99 ? "99+" : "\(max(count, 0))"
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let inset: CGFloat = 1
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: max(2.5, side * 0.14))
            UIColor.black.setStroke()
            path.lineWidth = 1.5
            path.stroke()

            let fontSize: CGFloat = text.count >= 3 ? side * 0.42 : side * 0.58
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black
            ]
            let ns = text as NSString
            let textSize = ns.size(withAttributes: attrs)
            ns.draw(
                in: CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                ),
                withAttributes: attrs
            )
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    private func applySurfaceLayout() {
        accountsStack.isHidden = !showsAccountOverview
        collectionView.isHidden = showsAccountOverview
        doneButton.isHidden = false
        addButton.accessibilityLabel = showsAccountOverview ? "New Account" : "New Tab"
    }

    private func updateCollectionHeight() {
        guard !showsAccountOverview else {
            collectionHeightConstraint?.update(offset: 0)
            return
        }
        let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : view.bounds.width
        guard width > 0 else { return }
        let itemWidth = (width - 36) / 2
        let itemHeight = itemWidth * 1.25
        let count = max(displayedTabs.count, displayedTabs.isEmpty ? 0 : 1)
        let rows = max(displayedTabs.isEmpty ? 0 : 1, Int(ceil(Double(max(count, 1)) / 2.0)))
        let height: CGFloat
        if displayedTabs.isEmpty {
            height = 24
        } else {
            height = CGFloat(rows) * itemHeight + CGFloat(max(0, rows - 1)) * 12 + 16
        }
        collectionHeightConstraint?.update(offset: height)
    }

    private func rebuildAccountCards() {
        accountsStack.arrangedSubviews.forEach {
            accountsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard showsAccountOverview else { return }

        for container in tabManager.sortedContainers {
            let tabs = tabManager.normalTabs.filter { $0.containerID == container.id }
            let card = AccountGroupCardView()
            card.configure(
                name: container.name,
                color: tabManager.accountColor(forContainer: container.id),
                tabCount: tabs.count,
                previews: tabs.prefix(2).compactMap { AppSettings.showTabsPreviewImages ? $0.snapshot : nil }
            )
            card.addAction(UIAction { [weak self] _ in
                self?.presentAccountPopup(containerID: container.id)
            }, for: .touchUpInside)
            accountsStack.addArrangedSubview(card)
            card.snp.makeConstraints { $0.height.equalTo(88) }
        }
    }

    private func rebuildLibrarySections() {
        // Library only on Accounts overview (normal mode).
        guard showsAccountOverview else {
            bookmarkItems = []
            historyItems = []
            bookmarksSection.isHidden = true
            historySection.isHidden = true
            bookmarksTable.reloadData()
            historyTable.reloadData()
            applyLibraryExpansion(animated: false)
            return
        }

        let containerID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        bookmarkItems = Array(BookmarkStore.shared.items(containerID: containerID).filter { $0.url != nil }.prefix(12))
        historyItems = Array(HistoryStore.shared.items(containerID: containerID).filter { $0.url != nil }.prefix(12))

        bookmarksSection.isHidden = bookmarkItems.isEmpty
        historySection.isHidden = historyItems.isEmpty
        bookmarksTable.reloadData()
        historyTable.reloadData()
        applyLibraryExpansion(animated: false)
    }

    // MARK: - Menus

    private func makeMoreMenu() -> UIMenu {
        var children: [UIMenuElement] = []
        if surface != .allTabs {
            children.append(UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.promptRename()
            })
        }
        children.append(UIAction(title: "Manage Accounts", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
            self?.manageContainersTapped()
        })
        children.append(UIAction(
            title: "Close All",
            image: UIImage(systemName: "xmark.circle"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.closeAllTabs()
        })
        children.append(UIAction(
            title: "Delete Account",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.promptDeleteAccount()
        })
        return UIMenu(title: "", children: children)
    }

    @objc private func manageContainersTapped() {
        let vc = ContainerManageViewController(tabManager: tabManager)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func promptRename() {
        presentAccountPicker(title: "Rename Account") { [weak self] container in
            self?.presentRenameAlert(for: container)
        }
    }

    private func presentRenameAlert(for container: BrowserContainer) {
        let alert = UIAlertController(title: "Rename Account", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = container.name; $0.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?.first?.text ?? ""
            if self.tabManager.renameContainer(id: container.id, to: name) {
                self.reload()
            } else {
                let err = UIAlertController(title: "Accounts", message: "Couldn’t rename. Use a unique non-empty name.", preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(err, animated: true)
            }
        }))
        present(alert, animated: true)
    }

    private func promptDeleteAccount() {
        presentAccountPicker(title: "Delete Account") { [weak self] container in
            self?.confirmDelete(container)
        }
    }

    private func confirmDelete(_ container: BrowserContainer) {
        guard tabManager.containers.count > 1 else {
            let alert = UIAlertController(title: "Accounts", message: "Keep at least one account.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Delete Account?",
            message: "Tabs in “\(container.name)” will move to another account. Their login session for this account will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            _ = self.tabManager.deleteContainer(id: container.id)
            self.reload()
        }))
        present(alert, animated: true)
    }

    private func presentAccountPicker(title: String, onPick: @escaping (BrowserContainer) -> Void) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for container in tabManager.sortedContainers {
            sheet.addAction(UIAlertAction(title: container.name, style: .default, handler: { _ in
                onPick(container)
            }))
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: 80, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    // MARK: - Navigation

    private func presentAccountPopup(containerID: UUID) {
        _ = tabManager.switchToAccount(containerID)
        let popup = AccountTabsPopupViewController(tabManager: tabManager, containerID: containerID)
        popup.delegate = self
        popup.modalPresentationStyle = .pageSheet
        if let sheet = popup.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        presentedAccountPopup = popup
        present(popup, animated: true)
    }

    @objc private func modeChanged() {
        let next = Surface(rawValue: modeControl.selectedSegmentIndex) ?? .accounts
        surface = next
        searchQuery = ""
        if surface == .incognito {
            let pool = tabManager.incognitoTabs
            if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
                tabManager.selectTab(id: tab.id)
            }
        } else if let tab = tabManager.normalTabs.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
            tabManager.selectTab(id: tab.id)
        }
        reload()
    }

    private var preferredContainerIDForNewTab: UUID? {
        if showingIncognito { return nil }
        if let selected = tabManager.selectedTab, !selected.isIncognito {
            return selected.containerID
        }
        return tabManager.defaultContainer.id
    }

    @objc private func addTapped() {
        if showsAccountOverview {
            presentNewAccount()
            return
        }
        delegate?.tabSwitcherDidRequestNewTab(
            incognito: showingIncognito,
            containerID: preferredContainerIDForNewTab
        )
    }

    private func presentNewAccount() {
        let edit = ContainerEditViewController(
            container: nil,
            tabManager: tabManager,
            suggestedPresetIndex: tabManager.containers.count
        )
        edit.delegate = self
        let nav = UINavigationController(rootViewController: edit)
        present(nav, animated: true)
    }

    @objc private func doneTapped() {
        let selectedIsPrivate = tabManager.selectedTab?.isIncognito ?? false
        if selectedIsPrivate != showingIncognito {
            let pool = showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
            if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
                tabManager.selectTab(id: tab.id)
            } else if showingIncognito {
                _ = tabManager.addTab(incognito: true, select: true)
            }
        }
        delegate?.tabSwitcherDidClose()
    }

    private func closeAllTabs() {
        let ids: [UUID]
        if showingIncognito {
            ids = tabManager.incognitoTabs.map(\.id)
        } else {
            ids = tabManager.normalTabs.map(\.id)
        }
        for id in ids {
            tabManager.closeTab(id: id)
        }
        reload()
        if tabManager.tabs.isEmpty {
            delegate?.tabSwitcherDidClose()
        }
    }

    private func promptMoveGroup(for tab: BrowserTab) {
        let alert = UIAlertController(title: "Move to Account", message: tab.title, preferredStyle: .actionSheet)
        for container in tabManager.sortedContainers {
            let title = container.id == tab.containerID ? "\(container.name) ✓" : container.name
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.confirmMove(tab: tab, to: container)
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: 80, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func confirmMove(tab: BrowserTab, to container: BrowserContainer) {
        if tab.containerID == container.id { return }
        let alert = UIAlertController(
            title: "Move to “\(container.name)”?",
            message: "This tab will use that account’s cookies and login. It may look logged out of the previous account.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Move", style: .default, handler: { [weak self] _ in
            self?.tabManager.moveTab(tab.id, toContainer: container.id)
            self?.reload()
        }))
        present(alert, animated: true)
    }

    @objc private func searchPlaceholder() {
        let alert = UIAlertController(title: "Search tabs", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title, URL, or account"; $0.text = self.searchQuery }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Search", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.searchQuery = alert.textFields?.first?.text ?? ""
            if self.isSearching, self.surface == .accounts {
                // Show matching tabs across accounts instead of the card list.
                self.surface = .allTabs
            }
            self.reload()
        }))
        if !searchQuery.isEmpty {
            alert.addAction(UIAlertAction(title: "Clear", style: .destructive, handler: { [weak self] _ in
                self?.searchQuery = ""
                self?.reload()
            }))
        }
        present(alert, animated: true)
    }
}

// MARK: - Collection

extension TabSwitcherViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        displayedTabs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabGridCell.reuseID, for: indexPath) as! TabGridCell
        let tab = displayedTabs[indexPath.item]
        let selected = tab.id == tabManager.selectedTab?.id
        cell.configure(
            tab: tab,
            containerName: tabManager.containerName(for: tab),
            accountColor: tabManager.accountColor(for: tab),
            selected: selected
        )
        cell.onClose = { [weak self] in
            guard let self else { return }
            self.tabManager.closeTab(id: tab.id)
            self.reload()
            if self.tabManager.tabs.isEmpty {
                self.delegate?.tabSwitcherDidClose()
            }
        }
        cell.onMoveGroup = { [weak self] in
            self?.promptMoveGroup(for: tab)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tab = displayedTabs[indexPath.item]
        tabManager.selectTab(id: tab.id)
        delegate?.tabSwitcherDidClose()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 36) / 2
        return CGSize(width: width, height: width * 1.25)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let tab = displayedTabs[indexPath.item]
        guard !tab.isIncognito else { return nil }
        return UIContextMenuConfiguration(identifier: tab.id.uuidString as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let moveChildren = self.tabManager.sortedContainers.map { container in
                let checked = container.id == tab.containerID
                return UIAction(
                    title: container.name,
                    image: UIImage(systemName: checked ? "checkmark.circle.fill" : "circle"),
                    state: checked ? .on : .off
                ) { [weak self] _ in
                    self?.confirmMove(tab: tab, to: container)
                }
            }
            return UIMenu(title: "", children: [
                UIMenu(title: "Move to Account", options: .displayInline, children: moveChildren)
            ])
        }
    }
}

extension TabSwitcherViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        itemsForBeginning session: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard canReorderTabs else { return [] }
        let tab = displayedTabs[indexPath.item]
        let provider = NSItemProvider(object: tab.id.uuidString as NSString)
        let item = UIDragItem(itemProvider: provider)
        item.localObject = tab.id
        return [item]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        mainScroll.isScrollEnabled = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        mainScroll.isScrollEnabled = true
    }

    func collectionView(
        _ collectionView: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard canReorderTabs, session.localDragSession != nil else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
        guard canReorderTabs,
              let item = coordinator.items.first,
              let id = item.dragItem.localObject as? UUID,
              let sourcePath = item.sourceIndexPath else { return }

        let destinationIndex = coordinator.destinationIndexPath?.item
            ?? displayedTabs.count - 1
        let destPath = IndexPath(
            item: max(0, min(destinationIndex, max(displayedTabs.count - 1, 0))),
            section: 0
        )
        guard sourcePath.item != destPath.item else {
            coordinator.drop(item.dragItem, toItemAt: destPath)
            return
        }

        collectionView.performBatchUpdates {
            self.tabManager.reorderTab(
                id: id,
                toDisplayIndex: destPath.item,
                incognito: self.showingIncognito
            )
            collectionView.moveItem(at: sourcePath, to: destPath)
        } completion: { [weak self] _ in
            self?.updateCollectionHeight()
        }
        coordinator.drop(item.dragItem, toItemAt: destPath)
    }
}

// MARK: - Library tables

extension TabSwitcherViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableView === bookmarksTable ? bookmarkItems.count : historyItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "libraryCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "libraryCell")
        cell.backgroundColor = BrowserTheme.card
        cell.selectionStyle = .default
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)

        if tableView === bookmarksTable {
            let item = bookmarkItems[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = item.url?.host ?? item.urlString
        } else {
            let item = historyItems[indexPath.row]
            cell.textLabel?.text = item.title
            cell.detailTextLabel?.text = item.url?.host ?? item.urlString
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 56 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url: URL?
        if tableView === bookmarksTable {
            url = bookmarkItems[indexPath.row].url
        } else {
            url = historyItems[indexPath.row].url
        }
        guard let url else { return }
        delegate?.tabSwitcherDidRequestOpenURLInNewTab(url, containerID: preferredContainerIDForNewTab)
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            if tableView === self.bookmarksTable {
                BookmarkStore.shared.remove(id: self.bookmarkItems[indexPath.row].id)
            } else {
                HistoryStore.shared.remove(id: self.historyItems[indexPath.row].id)
            }
            self.rebuildLibrarySections()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
}

extension TabSwitcherViewController: ContainerManageViewControllerDelegate {
    func containerManageDidChange() {
        reload()
    }
}

extension TabSwitcherViewController: ContainerEditViewControllerDelegate {
    func containerEditDidSave(_ container: BrowserContainer, isNew: Bool) {
        if isNew {
            _ = tabManager.addContainer(container)
        } else {
            _ = tabManager.updateContainer(container)
        }
        dismiss(animated: true)
        reload()
    }
}

extension TabSwitcherViewController: AccountTabsPopupDelegate {
    func accountTabsPopupDidRequestClose() {
        dismiss(animated: true) { [weak self] in
            self?.presentedAccountPopup = nil
            self?.reload()
        }
    }

    func accountTabsPopupDidSelectTab() {
        dismiss(animated: true) { [weak self] in
            self?.presentedAccountPopup = nil
            self?.delegate?.tabSwitcherDidClose()
        }
    }

    func accountTabsPopupDidRequestNewTab(containerID: UUID) {
        dismiss(animated: true) { [weak self] in
            self?.presentedAccountPopup = nil
            self?.delegate?.tabSwitcherDidRequestNewTab(incognito: false, containerID: containerID)
        }
    }

    func accountTabsPopupDidChangeAccounts() {
        reload()
    }
}

// MARK: - Account card

private final class AccountGroupCardView: UIControl {
    private let previewWell = UIView()
    private let previewA = UIImageView()
    private let previewB = UIImageView()
    private let placeholderIcon = UIImageView()
    private let dot = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BrowserTheme.card
        layer.cornerRadius = 18
        clipsToBounds = true

        previewWell.backgroundColor = BrowserTheme.secondaryCard
        previewWell.layer.cornerRadius = 12
        previewWell.clipsToBounds = true
        previewWell.isUserInteractionEnabled = false

        previewA.contentMode = .scaleAspectFill
        previewA.clipsToBounds = true
        previewB.contentMode = .scaleAspectFill
        previewB.clipsToBounds = true
        previewB.isHidden = true

        placeholderIcon.image = UIImage(systemName: "globe")
        placeholderIcon.tintColor = BrowserTheme.textSecondary
        placeholderIcon.contentMode = .scaleAspectFit

        dot.layer.cornerRadius = 5
        dot.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = BrowserTheme.textSecondary

        addSubview(previewWell)
        previewWell.addSubview(previewA)
        previewWell.addSubview(previewB)
        previewWell.addSubview(placeholderIcon)
        addSubview(dot)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        previewWell.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(64)
        }
        previewA.snp.makeConstraints { $0.edges.equalToSuperview() }
        previewB.snp.makeConstraints { make in
            make.trailing.bottom.equalToSuperview()
            make.width.height.equalToSuperview().multipliedBy(0.55)
        }
        placeholderIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(28)
        }
        dot.snp.makeConstraints { make in
            make.leading.equalTo(previewWell.snp.trailing).offset(14)
            make.top.equalToSuperview().offset(28)
            make.size.equalTo(10)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(dot.snp.trailing).offset(8)
            make.centerY.equalTo(dot)
            make.trailing.equalToSuperview().offset(-16)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(dot)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.trailing.equalToSuperview().offset(-16)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, color: UIColor, tabCount: Int, previews: [UIImage]) {
        titleLabel.text = name
        subtitleLabel.text = tabCount == 1 ? "1 tab" : "\(tabCount) tabs"
        dot.backgroundColor = color

        let images = Array(previews.prefix(2))
        if images.isEmpty {
            previewA.image = nil
            previewB.isHidden = true
            placeholderIcon.isHidden = false
        } else {
            placeholderIcon.isHidden = true
            previewA.image = images[0]
            if images.count > 1 {
                previewB.image = images[1]
                previewB.isHidden = false
                previewB.layer.cornerRadius = 8
                previewB.layer.borderWidth = 2
                previewB.layer.borderColor = BrowserTheme.secondaryCard.cgColor
            } else {
                previewB.isHidden = true
            }
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.85 : 1 }
    }
}

// MARK: - Tab grid cell

final class TabGridCell: UICollectionViewCell {
    static let reuseID = "TabGridCell"
    var onClose: (() -> Void)?
    var onMoveGroup: (() -> Void)?

    private let card = UIView()
    private let colorBar = UIView()
    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let avatarView = UIImageView()
    private let groupButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let preview = UIImageView()
    private let placeholder = UILabel()
    private var configuredTabID: UUID?

    private static let headerHeight: CGFloat = 52

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        contentView.addSubview(card)

        colorBar.backgroundColor = BrowserTheme.chromeBlue
        headerBar.backgroundColor = BrowserTheme.card
        headerBar.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 11
        avatarView.backgroundColor = BrowserTheme.secondaryCard
        avatarView.isHidden = true

        groupButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        groupButton.titleLabel?.lineBreakMode = .byTruncatingTail
        groupButton.contentHorizontalAlignment = .leading
        groupButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        groupButton.tintColor = BrowserTheme.chromeBlue
        groupButton.setImage(
            UIImage(systemName: "folder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)),
            for: .normal
        )
        groupButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2, bottom: 0, right: 2)
        groupButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: -2)
        groupButton.accessibilityLabel = "Move to Account"
        groupButton.accessibilityHint = "Choose an account for this tab"
        groupButton.addTarget(self, action: #selector(groupTapped), for: .touchUpInside)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = BrowserTheme.textSecondary
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.isUserInteractionEnabled = false
        placeholder.text = "Page"
        placeholder.textColor = BrowserTheme.textSecondary
        placeholder.textAlignment = .center
        placeholder.isUserInteractionEnabled = false

        card.addSubview(preview)
        card.addSubview(placeholder)
        card.addSubview(headerBar)
        card.addSubview(colorBar)
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(avatarView)
        headerBar.addSubview(groupButton)
        headerBar.addSubview(closeButton)

        card.snp.makeConstraints { $0.edges.equalToSuperview() }
        colorBar.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(3)
        }
        headerBar.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Self.headerHeight)
        }
        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.trailing.equalToSuperview().offset(-6)
            make.size.equalTo(28)
        }
        avatarView.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalTo(closeButton.snp.leading).offset(-4)
            make.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalTo(avatarView.snp.leading).offset(-6)
            make.height.equalTo(18)
        }
        groupButton.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(2)
            make.leading.equalToSuperview().offset(8)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-6)
            make.height.equalTo(22)
            make.bottom.lessThanOrEqualToSuperview().offset(-4)
        }
        preview.snp.makeConstraints { make in
            make.top.equalTo(headerBar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholder.snp.makeConstraints { $0.center.equalTo(preview) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: BrowserTab, containerName: String, accountColor: UIColor, selected: Bool) {
        configuredTabID = tab.id
        titleLabel.text = tab.title
        let name = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        groupButton.setTitle(name.isEmpty ? "Account" : name, for: .normal)
        groupButton.setTitleColor(accountColor, for: .normal)
        groupButton.tintColor = accountColor
        colorBar.backgroundColor = accountColor
        if let avatar = tab.sessionAvatar {
            avatarView.image = avatar
            avatarView.isHidden = false
        } else {
            avatarView.image = nil
            avatarView.isHidden = true
        }
        if AppSettings.showTabsPreviewImages, let snapshot = tab.snapshot {
            preview.image = snapshot
            placeholder.isHidden = true
            upgradePreviewToStandard(for: tab.id)
        } else {
            preview.image = nil
            placeholder.isHidden = false
        }
        card.layer.borderWidth = selected ? 2 : 0
        card.layer.borderColor = accountColor.cgColor
    }

    private func upgradePreviewToStandard(for tabID: UUID) {
        TabSnapshotStore.loadStandardAsync(for: tabID) { [weak self] image in
            guard let self, self.configuredTabID == tabID, let image else { return }
            self.preview.image = image
        }
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func groupTapped() { onMoveGroup?() }
}
