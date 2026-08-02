import UIKit
import SnapKit

protocol TabSwitcherViewControllerDelegate: AnyObject {
    func tabSwitcherDidClose()
    func tabSwitcherDidRequestNewTab(incognito: Bool)
    func tabSwitcherDidRequestOpenURLInNewTab(_ url: URL)
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
    private let readingSection = UIStackView()
    private let bookmarksTable = UITableView(frame: .zero, style: .plain)
    private let readingTable = UITableView(frame: .zero, style: .plain)
    private var bookmarksHeightConstraint: Constraint?
    private var readingHeightConstraint: Constraint?
    private var bookmarkItems: [BookmarkItem] = []
    private var readingItems: [ReadingListItem] = []
    private var searchQuery = ""
    private var showingIncognito = false
    /// `nil` means All groups.
    private var selectedGroupFilter: String?
    private let groupFilterBar = UIScrollView()
    private let groupFilterStack = UIStackView()

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        self.showingIncognito = tabManager.selectedTab?.isIncognito ?? false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var poolTabs: [BrowserTab] {
        showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
    }

    private var displayedTabs: [BrowserTab] {
        var base = poolTabs
        if let group = selectedGroupFilter {
            base = base.filter { $0.groupName == group }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q)
                || ($0.url?.absoluteString.lowercased().contains(q) ?? false)
                || $0.groupName.lowercased().contains(q)
        }
    }

    /// Drag reorder only when showing the unfiltered tab pool.
    private var canReorderTabs: Bool {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedGroupFilter == nil
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
        groupFilterBar.showsHorizontalScrollIndicator = false
        groupFilterBar.alwaysBounceHorizontal = true
        groupFilterStack.axis = .horizontal
        groupFilterStack.spacing = 8
        groupFilterStack.alignment = .center
        groupFilterBar.addSubview(groupFilterStack)
        view.addSubview(groupFilterBar)

        groupFilterBar.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(40)
        }
        groupFilterStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
            make.height.equalToSuperview().offset(-8)
        }
    }

    private func rebuildGroupFilterBar() {
        groupFilterStack.arrangedSubviews.forEach {
            groupFilterStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // Keep filter valid if the group disappeared.
        if let selected = selectedGroupFilter,
           !tabManager.groupNames.contains(selected) {
            selectedGroupFilter = nil
        }

        let accent = showingIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        let chips: [(title: String, group: String?)] =
            [("All", nil)] + tabManager.groupNames.map { ($0, $0) }

        for chip in chips {
            let count: Int = {
                guard let group = chip.group else { return poolTabs.count }
                return poolTabs.filter { $0.groupName == group }.count
            }()
            let selected = selectedGroupFilter == chip.group
            let button = UIButton(type: .system)
            button.setTitle(count > 0 ? "\(chip.title) (\(count))" : chip.title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
            button.setTitleColor(selected ? .white : BrowserTheme.textPrimary, for: .normal)
            button.backgroundColor = selected ? accent : BrowserTheme.secondaryCard
            button.layer.cornerRadius = 14
            button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            button.tag = chip.group == nil ? -1 : (tabManager.groupNames.firstIndex(of: chip.group!) ?? 0)
            button.accessibilityIdentifier = chip.group ?? "__all__"
            button.addTarget(self, action: #selector(groupFilterTapped(_:)), for: .touchUpInside)
            groupFilterStack.addArrangedSubview(button)
        }
    }

    @objc private func groupFilterTapped(_ sender: UIButton) {
        let id = sender.accessibilityIdentifier
        if id == "__all__" || id == nil {
            selectedGroupFilter = nil
        } else {
            selectedGroupFilter = id
        }
        rebuildGroupFilterBar()
        collectionView.reloadData()
        updateCollectionHeight()
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
        configureListSection(readingSection, title: "Reading list", table: readingTable, kind: .reading)

        contentStack.addArrangedSubview(collectionView)
        contentStack.addArrangedSubview(bookmarksSection)
        contentStack.addArrangedSubview(readingSection)

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

    private enum LibraryKind: Int { case bookmarks = 1, reading = 2 }

    private func configureListSection(_ section: UIStackView, title: String, table: UITableView, kind: LibraryKind) {
        section.axis = .vertical
        section.spacing = 8
        section.alignment = .fill
        section.isLayoutMarginsRelativeArrangement = true
        section.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        section.isHidden = true

        let header = UILabel()
        header.text = title
        header.font = .systemFont(ofSize: 16, weight: .semibold)
        header.textColor = BrowserTheme.textPrimary
        section.addArrangedSubview(header)

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
        section.addArrangedSubview(table)
        table.snp.makeConstraints { make in
            if kind == .bookmarks {
                bookmarksHeightConstraint = make.height.equalTo(0).constraint
            } else {
                readingHeightConstraint = make.height.equalTo(0).constraint
            }
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
            readingItems = []
            bookmarksSection.isHidden = true
            readingSection.isHidden = true
            bookmarksHeightConstraint?.update(offset: 0)
            readingHeightConstraint?.update(offset: 0)
            bookmarksTable.reloadData()
            readingTable.reloadData()
            return
        }

        bookmarkItems = Array(BookmarkStore.shared.items.filter { $0.url != nil }.prefix(12))
        readingItems = Array(ReadingListStore.shared.items.filter { $0.url != nil }.prefix(12))

        bookmarksSection.isHidden = bookmarkItems.isEmpty
        readingSection.isHidden = readingItems.isEmpty
        bookmarksHeightConstraint?.update(offset: CGFloat(bookmarkItems.count) * 56)
        readingHeightConstraint?.update(offset: CGFloat(readingItems.count) * 56)
        bookmarksTable.reloadData()
        readingTable.reloadData()
    }

    @objc private func modeChanged() {
        showingIncognito = modeControl.selectedSegmentIndex == 1
        searchQuery = ""
        selectedGroupFilter = nil
        let pool = showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
        if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
            tabManager.selectTab(id: tab.id)
        }
        reload()
    }

    @objc private func addTapped() {
        // Create a tab in the mode currently being viewed.
        delegate?.tabSwitcherDidRequestNewTab(incognito: showingIncognito)
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
        let alert = UIAlertController(title: "Move to Group", message: tab.title, preferredStyle: .actionSheet)
        for name in tabManager.groupNames {
            let title = name == tab.groupName ? "\(name) ✓" : name
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                self.tabManager.moveTab(tab.id, toGroup: name)
                self.reload()
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: 80, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    @objc private func searchPlaceholder() {
        let alert = UIAlertController(title: "Search tabs", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title, URL, or group"; $0.text = self.searchQuery }
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
        cell.configure(tab: tab, selected: selected)
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
        tableView === bookmarksTable ? bookmarkItems.count : readingItems.count
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
            let item = readingItems[indexPath.row]
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
            url = readingItems[indexPath.row].url
        }
        guard let url else { return }
        delegate?.tabSwitcherDidRequestOpenURLInNewTab(url)
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
                let id = self.readingItems[indexPath.row].id
                ReadingListStore.shared.remove(id: id)
            }
            self.rebuildLibrarySections()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
}

final class TabGridCell: UICollectionViewCell {
    static let reuseID = "TabGridCell"
    var onClose: (() -> Void)?
    var onMoveGroup: (() -> Void)?

    private let card = UIView()
    private let titleLabel = UILabel()
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

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail

        groupButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        groupButton.titleLabel?.lineBreakMode = .byTruncatingTail
        groupButton.contentHorizontalAlignment = .leading
        groupButton.setTitleColor(BrowserTheme.textSecondary, for: .normal)
        groupButton.tintColor = BrowserTheme.textSecondary
        groupButton.setImage(
            UIImage(systemName: "folder", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)),
            for: .normal
        )
        groupButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2, bottom: 0, right: 2)
        groupButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: -2)
        groupButton.accessibilityLabel = "Move to Group"
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

        card.addSubview(titleLabel)
        card.addSubview(groupButton)
        card.addSubview(closeButton)
        card.addSubview(preview)
        card.addSubview(placeholder)

        card.snp.makeConstraints { $0.edges.equalToSuperview() }
        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(10)
            make.trailing.equalTo(closeButton.snp.leading).offset(-6)
        }
        groupButton.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(0)
            make.leading.equalToSuperview().offset(8)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-6)
            make.height.equalTo(24)
        }
        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.trailing.equalToSuperview().offset(-6)
            make.size.equalTo(28)
        }
        preview.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(48)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholder.snp.makeConstraints { $0.center.equalTo(preview) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: BrowserTab, selected: Bool) {
        titleLabel.text = tab.title
        let group = tab.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        groupButton.setTitle(group.isEmpty ? "Default" : group, for: .normal)
        if AppSettings.showTabsPreviewImages, let snapshot = tab.snapshot {
            preview.image = snapshot
            placeholder.isHidden = true
        } else {
            preview.image = nil
            placeholder.isHidden = false
        }
        card.layer.borderWidth = selected ? 2 : 0
        card.layer.borderColor = BrowserTheme.chromeBlue.cgColor
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func groupTapped() { onMoveGroup?() }
}
