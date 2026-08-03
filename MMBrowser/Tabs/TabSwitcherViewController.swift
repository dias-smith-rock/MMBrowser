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

    private let tabManager: TabManager
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: Constraint?
    private let topBar = UIView()
    private let modeControl = UISegmentedControl(items: ["Tabs", "Incognito"])
    private let doneButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let mainScroll = UIScrollView()
    private let contentStack = UIStackView()
    private let bookmarksSection = UIStackView()
    private let historySection = UIStackView()
    private let bookmarksTable = UITableView(frame: .zero, style: .plain)
    private let historyTable = UITableView(frame: .zero, style: .plain)
    private var bookmarksHeightConstraint: Constraint?
    private var historyHeightConstraint: Constraint?
    private var bookmarkItems: [BookmarkItem] = []
    private var historyItems: [HistoryItem] = []
    /// Library lists start collapsed; tap the header to expand.
    private var bookmarksExpanded = false
    private var historyExpanded = false
    private weak var bookmarksHeaderButton: UIButton?
    private weak var historyHeaderButton: UIButton?
    private var searchQuery = ""
    private var showingIncognito = false
    /// `nil` means All containers.
    private var selectedContainerFilter: UUID?
    private let groupFilterBar = UIView()
    private let groupFilterStack = UIStackView()
    private var groupFilterHeightConstraint: Constraint?
    private var lastGroupFilterLayoutWidth: CGFloat = 0

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self.showingIncognito = tabManager.selectedTab?.isIncognito ?? false
        // Default filter: All containers.
        self.selectedContainerFilter = nil
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var poolTabs: [BrowserTab] {
        showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
    }

    private var displayedTabs: [BrowserTab] {
        var base = poolTabs
        if let containerID = selectedContainerFilter {
            base = base.filter { $0.containerID == containerID }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            let name = tabManager.containerName(for: $0)
            return $0.title.lowercased().contains(q)
                || ($0.url?.absoluteString.lowercased().contains(q) ?? false)
                || name.lowercased().contains(q)
        }
    }

    /// Drag reorder only when showing the unfiltered tab pool.
    private var canReorderTabs: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedContainerFilter == nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyChrome()
        setupTop()
        setupGroupFilterBar()
        setupMainScroll()
        setupBottom()
        reload()
    }

    private func applyChrome() {
        view.backgroundColor = showingIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
        topBar.backgroundColor = .clear
        addButton.backgroundColor = showingIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        doneButton.setTitleColor(showingIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue, for: .normal)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionHeight()
        let width = groupFilterBar.bounds.width
        if width > 0, abs(width - lastGroupFilterLayoutWidth) > 0.5 {
            lastGroupFilterLayoutWidth = width
            rebuildGroupFilterBar()
        }
    }

    private func setupTop() {
        view.addSubview(topBar)

        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.tintColor = BrowserTheme.textPrimary
        search.addTarget(self, action: #selector(searchPlaceholder), for: .touchUpInside)

        modeControl.selectedSegmentIndex = showingIncognito ? 1 : 0
        modeControl.selectedSegmentTintColor = BrowserTheme.secondaryCard
        modeControl.setTitleTextAttributes([.foregroundColor: BrowserTheme.textPrimary], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: BrowserTheme.textPrimary], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeControl.accessibilityLabel = "Tabs mode"

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = BrowserTheme.textPrimary
        moreButton.accessibilityLabel = "More"
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()

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
            make.width.equalTo(220)
            make.leading.greaterThanOrEqualTo(search.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-8)
        }
    }

    private func setupGroupFilterBar() {
        groupFilterStack.axis = .vertical
        groupFilterStack.spacing = 8
        groupFilterStack.alignment = .leading
        groupFilterBar.addSubview(groupFilterStack)
        view.addSubview(groupFilterBar)

        groupFilterBar.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            groupFilterHeightConstraint = make.height.equalTo(40).constraint
        }
        groupFilterStack.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(4)
            make.leading.trailing.equalToSuperview().inset(16)
        }
    }

    private func makeGroupFilterRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.distribution = .fill
        return row
    }

    private func makeContainerChipButton(title: String, id: String, selected: Bool, accent: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
        button.setTitleColor(selected ? .white : BrowserTheme.textPrimary, for: .normal)
        button.backgroundColor = selected ? accent : BrowserTheme.secondaryCard
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.accessibilityIdentifier = id
        button.addTarget(self, action: #selector(groupFilterTapped(_:)), for: .touchUpInside)
        return button
    }

    private func makeManageContainersButton(accent: UIColor) -> UIButton {
        let manage = UIButton(type: .system)
        let manageIcon = UIImage(
            systemName: "slider.horizontal.3",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        manage.setImage(manageIcon, for: .normal)
        manage.setTitle(nil, for: .normal)
        manage.tintColor = accent
        manage.backgroundColor = BrowserTheme.secondaryCard
        manage.layer.cornerRadius = 14
        manage.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        manage.accessibilityLabel = "Manage Accounts"
        manage.addTarget(self, action: #selector(manageContainersTapped), for: .touchUpInside)
        return manage
    }

    private func rebuildGroupFilterBar() {
        groupFilterStack.arrangedSubviews.forEach {
            groupFilterStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if let selected = selectedContainerFilter,
           tabManager.container(id: selected) == nil {
            selectedContainerFilter = nil
        }

        let accent = showingIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        var buttons: [UIButton] = []

        // Manage stays first so it remains reachable when there are many containers.
        buttons.append(makeManageContainersButton(accent: accent))

        let chips: [(title: String, id: String)] =
            [("All", "__all__")] + tabManager.sortedContainers.map { ($0.name, $0.id.uuidString) }

        for chip in chips {
            let count: Int = {
                if chip.id == "__all__" { return poolTabs.count }
                guard let uuid = UUID(uuidString: chip.id) else { return 0 }
                return poolTabs.filter { $0.containerID == uuid }.count
            }()
            let selected = (chip.id == "__all__" && selectedContainerFilter == nil)
                || (selectedContainerFilter?.uuidString == chip.id)
            let title = count > 0 ? "\(chip.title) (\(count))" : chip.title
            let button = makeContainerChipButton(title: title, id: chip.id, selected: selected, accent: accent)
            if chip.id != "__all__", let uuid = UUID(uuidString: chip.id) {
                let color = tabManager.accountColor(forContainer: uuid)
                if selected {
                    button.backgroundColor = color.withAlphaComponent(0.28)
                    button.setTitleColor(color, for: .normal)
                } else {
                    button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
                }
            }
            buttons.append(button)
        }

        let availableWidth = max(
            groupFilterBar.bounds.width - 32,
            view.bounds.width - 32,
            1
        )
        var row = makeGroupFilterRow()
        var used: CGFloat = 0
        for button in buttons {
            let width = ceil(
                button.systemLayoutSizeFitting(
                    CGSize(width: UIView.layoutFittingCompressedSize.width, height: 28),
                    withHorizontalFittingPriority: .fittingSizeLevel,
                    verticalFittingPriority: .required
                ).width
            )
            let gap: CGFloat = used > 0 ? 8 : 0
            if used > 0, used + gap + width > availableWidth {
                groupFilterStack.addArrangedSubview(row)
                row = makeGroupFilterRow()
                used = 0
            }
            row.addArrangedSubview(button)
            used += (used > 0 ? 8 : 0) + max(width, 1)
        }
        if !row.arrangedSubviews.isEmpty {
            groupFilterStack.addArrangedSubview(row)
        }

        let rows = max(groupFilterStack.arrangedSubviews.count, 1)
        let chipHeight: CGFloat = 28
        let height = 8 + CGFloat(rows) * chipHeight + CGFloat(max(0, rows - 1)) * 8
        groupFilterHeightConstraint?.update(offset: height)
        if groupFilterBar.bounds.width > 0 {
            lastGroupFilterLayoutWidth = groupFilterBar.bounds.width
        }
    }

    @objc private func groupFilterTapped(_ sender: UIButton) {
        let id = sender.accessibilityIdentifier
        if id == "__all__" || id == nil {
            selectedContainerFilter = nil
        } else {
            selectedContainerFilter = id.flatMap(UUID.init(uuidString:))
        }
        rebuildGroupFilterBar()
        collectionView.reloadData()
        updateCollectionHeight()
    }

    @objc private func manageContainersTapped() {
        let vc = ContainerManageViewController(tabManager: tabManager)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func makeMoreMenu() -> UIMenu {
        let closeOthers = UIAction(title: "Close Other Tabs", image: UIImage(systemName: "xmark.rectangle")) { [weak self] _ in
            self?.closeOtherTabs()
        }
        let closeAll = UIAction(title: "Close All Tabs", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
            self?.closeAllTabs()
        }
        return UIMenu(title: "", children: [closeOthers, closeAll])
    }

    private func setupMainScroll() {
        mainScroll.alwaysBounceVertical = true
        mainScroll.showsVerticalScrollIndicator = false
        view.addSubview(mainScroll)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.alignment = .fill
        mainScroll.addSubview(contentStack)

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

        contentStack.addArrangedSubview(collectionView)
        contentStack.addArrangedSubview(bookmarksSection)
        contentStack.addArrangedSubview(historySection)

        mainScroll.snp.makeConstraints { make in
            make.top.equalTo(groupFilterBar.snp.bottom)
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
        // Keep the table in the stack layout always; collapse via height == 0.
        // Toggling `isHidden` on arranged subviews skips layout and overlaps siblings.
        table.clipsToBounds = true
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
        case .bookmarks:
            bookmarksExpanded.toggle()
        case .history:
            historyExpanded.toggle()
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

        updateLibraryHeader(
            bookmarksHeaderButton,
            title: "Bookmarks",
            expanded: bookmarksExpanded,
            count: bookmarkItems.count
        )
        updateLibraryHeader(
            historyHeaderButton,
            title: "History",
            expanded: historyExpanded,
            count: historyItems.count
        )

        let updates = {
            self.bookmarksHeightConstraint?.update(offset: bookmarkHeight)
            self.historyHeightConstraint?.update(offset: historyHeight)
            self.bookmarksTable.alpha = bookmarkHeight > 0 ? 1 : 0
            self.historyTable.alpha = historyHeight > 0 ? 1 : 0
            self.bookmarksSection.layoutIfNeeded()
            self.historySection.layoutIfNeeded()
            self.contentStack.layoutIfNeeded()
            self.mainScroll.layoutIfNeeded()
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

    private func reload() {
        modeControl.selectedSegmentIndex = showingIncognito ? 1 : 0
        let normalCount = tabManager.normalTabs.count
        let privateCount = tabManager.incognitoTabs.count
        modeControl.setTitle(normalCount > 0 ? "Tabs (\(normalCount))" : "Tabs", forSegmentAt: 0)
        modeControl.setTitle(privateCount > 0 ? "Incognito (\(privateCount))" : "Incognito", forSegmentAt: 1)
        moreButton.menu = makeMoreMenu()
        applyChrome()
        rebuildGroupFilterBar()
        collectionView.reloadData()
        updateCollectionHeight()
        rebuildLibrarySections()
    }

    /// Refresh tab cards after async webpage snapshots finish.
    func reloadPreviews() {
        guard isViewLoaded else { return }
        collectionView.reloadData()
    }

    private func updateCollectionHeight() {
        let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : view.bounds.width
        guard width > 0 else { return }
        let itemWidth = (width - 36) / 2
        let itemHeight = itemWidth * 1.25
        let rows = max(1, Int(ceil(Double(max(displayedTabs.count, 1)) / 2.0)))
        let height = CGFloat(rows) * itemHeight + CGFloat(max(0, rows - 1)) * 12 + 16
        collectionHeightConstraint?.update(offset: height)
    }

    private func rebuildLibrarySections() {
        // Keep library shortcuts on the normal-tabs surface only.
        guard !showingIncognito else {
            bookmarkItems = []
            historyItems = []
            bookmarksSection.isHidden = true
            historySection.isHidden = true
            bookmarksTable.reloadData()
            historyTable.reloadData()
            applyLibraryExpansion(animated: false)
            return
        }

        bookmarkItems = Array(BookmarkStore.shared.items.filter { $0.url != nil }.prefix(12))
        historyItems = Array(HistoryStore.shared.items.filter { $0.url != nil }.prefix(12))

        bookmarksSection.isHidden = bookmarkItems.isEmpty
        historySection.isHidden = historyItems.isEmpty
        bookmarksTable.reloadData()
        historyTable.reloadData()
        applyLibraryExpansion(animated: false)
    }

    @objc private func modeChanged() {
        showingIncognito = modeControl.selectedSegmentIndex == 1
        searchQuery = ""
        selectedContainerFilter = nil
        let pool = showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
        if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
            tabManager.selectTab(id: tab.id)
        }
        reload()
    }

    /// Container for newly opened normal tabs: active filter, else currently selected tab.
    private var preferredContainerIDForNewTab: UUID? {
        if showingIncognito { return nil }
        if let selectedContainerFilter { return selectedContainerFilter }
        if let selected = tabManager.selectedTab, !selected.isIncognito {
            return selected.containerID
        }
        return tabManager.defaultContainer.id
    }

    @objc private func addTapped() {
        // Create a tab in the mode currently being viewed, in the active container context.
        delegate?.tabSwitcherDidRequestNewTab(
            incognito: showingIncognito,
            containerID: preferredContainerIDForNewTab
        )
    }

    @objc private func doneTapped() {
        // If current selection is in the other mode, jump to the viewed mode's tab.
        let selectedIsPrivate = tabManager.selectedTab?.isIncognito ?? false
        if selectedIsPrivate != showingIncognito {
            let pool = showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
            if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
                tabManager.selectTab(id: tab.id)
            } else if showingIncognito {
                // No private tab yet — create one so Done lands in Incognito.
                _ = tabManager.addTab(incognito: true, select: true)
            }
        }
        delegate?.tabSwitcherDidClose()
    }

    private func closeOtherTabs() {
        let visibleIDs = Set(displayedTabs.map(\.id))
        guard let selected = tabManager.selectedTab, visibleIDs.contains(selected.id) else { return }
        for tab in displayedTabs where tab.id != selected.id {
            tabManager.closeTab(id: tab.id)
        }
        reload()
    }

    private func closeAllTabs() {
        let ids = displayedTabs.map(\.id)
        for id in ids {
            tabManager.closeTab(id: id)
        }
        reload()
        if displayedTabs.isEmpty, showingIncognito {
            // Stay on Incognito surface with an empty grid; user can tap +.
            return
        }
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
        if tab.containerID == container.id {
            return
        }
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
        alert.addAction(UIAlertAction(title: "Search", style: .default, handler: { _ in
            self.searchQuery = alert.textFields?.first?.text ?? ""
            self.reload()
        }))
        present(alert, animated: true)
    }
}

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
            guard let self = self else { return }
            self.tabManager.closeTab(id: tab.id)
            self.reload()
            if self.tabManager.tabs.isEmpty {
                self.delegate?.tabSwitcherDidClose()
            }
        }
        // Grouping via tap — long-press is reserved for drag reorder.
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
                    guard let self else { return }
                    self.confirmMove(tab: tab, to: container)
                }
            }
            let moveMenu = UIMenu(title: "Move to Account", options: .displayInline, children: moveChildren)
            return UIMenu(title: "", children: [moveMenu])
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

    func collectionView(
        _ collectionView: UICollectionView,
        dragSessionWillBegin session: UIDragSession
    ) {
        mainScroll.isScrollEnabled = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        dragSessionDidEnd session: UIDragSession
    ) {
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
                let id = self.bookmarkItems[indexPath.row].id
                BookmarkStore.shared.remove(id: id)
            } else {
                let id = self.historyItems[indexPath.row].id
                HistoryStore.shared.remove(id: id)
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
        if let selected = selectedContainerFilter, tabManager.container(id: selected) == nil {
            selectedContainerFilter = nil
        }
        reload()
    }
}

final class TabGridCell: UICollectionViewCell {
    static let reuseID = "TabGridCell"
    var onClose: (() -> Void)?
    var onMoveGroup: (() -> Void)?

    private let card = UIView()
    private let colorBar = UIView()
    private let titleLabel = UILabel()
    private let avatarView = UIImageView()
    private let groupButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let preview = UIImageView()
    private let placeholder = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        contentView.addSubview(card)

        colorBar.backgroundColor = BrowserTheme.chromeBlue
        card.addSubview(colorBar)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail

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

        // Preview first so chrome controls stay above it and remain tappable.
        card.addSubview(preview)
        card.addSubview(placeholder)
        card.addSubview(titleLabel)
        card.addSubview(avatarView)
        card.addSubview(groupButton)
        card.addSubview(closeButton)

        card.snp.makeConstraints { $0.edges.equalToSuperview() }
        colorBar.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalTo(3)
        }
        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.trailing.equalToSuperview().offset(-6)
            make.size.equalTo(28)
        }
        avatarView.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalTo(closeButton.snp.leading).offset(-4)
            make.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalTo(avatarView.snp.leading).offset(-6)
        }
        groupButton.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(2)
            make.leading.equalToSuperview().offset(8)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-6)
            make.height.equalTo(28)
        }
        preview.snp.makeConstraints { make in
            make.top.equalTo(groupButton.snp.bottom).offset(4)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholder.snp.makeConstraints { $0.center.equalTo(preview) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: BrowserTab, containerName: String, accountColor: UIColor, selected: Bool) {
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
        } else {
            preview.image = nil
            placeholder.isHidden = false
        }
        card.layer.borderWidth = selected ? 2 : 0
        card.layer.borderColor = accountColor.cgColor
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func groupTapped() { onMoveGroup?() }
}
