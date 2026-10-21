import UIKit
import SnapKit

protocol TabSwitcherViewControllerDelegate: AnyObject {
    func tabSwitcherDidClose()
    /// `containerID` is the container for the new normal tab (selected tab / active filter).
    func tabSwitcherDidRequestNewTab(incognito: Bool, containerID: UUID?)
    func tabSwitcherDidRequestOpenURLInNewTab(_ url: URL, containerID: UUID?)
    /// Bottom + opens Space Hub (home / account entry).
    func tabSwitcherDidRequestAccountHub()
}

final class TabSwitcherViewController: UIViewController {
    weak var delegate: TabSwitcherViewControllerDelegate?

    private enum Surface {
        case spaces
        case incognito
    }

    private let tabManager: TabManager
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: Constraint?
    private let topBar = UIView()
    private let spacesScroll = UIScrollView()
    private let spacesStack = UIStackView()
    private let addSpaceButton = UIButton(type: .system)
    private let bottomBar = UIView()
    private let privateButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let mainScroll = UIScrollView()
    private let contentStack = UIStackView()
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
    private var surface: Surface
    /// Space whose tabs are shown in the grid (normal mode).
    private var focusedSpaceID: UUID

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        let activeID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        self.focusedSpaceID = activeID
        if tabManager.selectedTab?.isIncognito == true {
            self.surface = .incognito
        } else {
            self.surface = .spaces
        }
        super.init(nibName: nil, bundle: nil)
    }

    private var currentAccountID: UUID {
        focusedSpaceID
    }

    required init?(coder: NSCoder) { fatalError() }

    private var showingIncognito: Bool { surface == .incognito }

    private var poolTabs: [BrowserTab] {
        showingIncognito ? tabManager.incognitoTabs : tabManager.normalTabs
    }

    /// Real pages in the current surface (excludes blank New Tab pages).
    private var displayedTabs: [BrowserTab] {
        if showingIncognito {
            return poolTabs.filter { !$0.isNewTabPage }
        }
        return poolTabs.filter { $0.containerID == focusedSpaceID && !$0.isNewTabPage }
    }

    /// Empty space / private pool shows a synthetic New Tab card.
    private var showsNewTabPlaceholder: Bool {
        displayedTabs.isEmpty
    }

    private var gridItemCount: Int {
        showsNewTabPlaceholder ? 1 : displayedTabs.count
    }

    /// Drag reorder when the grid has real tabs.
    private var canReorderTabs: Bool {
        !showsNewTabPlaceholder && !displayedTabs.isEmpty
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyChrome()
        setupTop()
        setupBottom()
        // mainScroll pins to topBar/bottomBar — both must already be in the hierarchy
        setupMainScroll()
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshMediaPlayingIndicators()
    }

    /// Probe live WebViews so speaker badges match current playback (incl. `<audio>` / PiP).
    private func refreshMediaPlayingIndicators() {
        let targets = displayedTabs.compactMap(\.webController)
        guard !targets.isEmpty else { return }
        let group = DispatchGroup()
        for web in targets {
            group.enter()
            web.refreshPlayingMediaState { _ in group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.isViewLoaded else { return }
            self.collectionView.reloadData()
            self.presentedAccountPopup?.reloadPreviews()
        }
    }

    private func applyChrome() {
        let spaceColor = showingIncognito ? nil : tabManager.accountColor(forContainer: focusedSpaceID)
        view.backgroundColor = showingIncognito
            ? BrowserTheme.privateBackground
            : BrowserTheme.spaceSurfaceColor(spaceColor: spaceColor)
        mainScroll.backgroundColor = .clear
        topBar.backgroundColor = .clear
        bottomBar.backgroundColor = .clear
        let accent = showingIncognito
            ? BrowserTheme.privateAccent
            : (spaceColor ?? BrowserTheme.chromeBlue)
        addButton.tintColor = accent
        doneButton.setTitleColor(accent, for: .normal)
        privateButton.tintColor = showingIncognito ? accent : BrowserTheme.textPrimary
        privateButton.setTitleColor(showingIncognito ? accent : BrowserTheme.textPrimary, for: .normal)
        topBar.isHidden = showingIncognito
        addSpaceButton.tintColor = BrowserTheme.textPrimary
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionHeight()
    }

    // MARK: - Top / space pills

    private func setupTop() {
        view.addSubview(topBar)

        spacesScroll.showsHorizontalScrollIndicator = false
        spacesScroll.alwaysBounceHorizontal = true
        topBar.addSubview(spacesScroll)

        spacesStack.axis = .horizontal
        spacesStack.spacing = 8
        spacesStack.alignment = .center
        spacesScroll.addSubview(spacesStack)

        addSpaceButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
            for: .normal
        )
        addSpaceButton.backgroundColor = BrowserTheme.secondaryCard
        addSpaceButton.tintColor = BrowserTheme.textPrimary
        addSpaceButton.layer.cornerRadius = 16
        addSpaceButton.accessibilityLabel = "Add Space"
        addSpaceButton.addTarget(self, action: #selector(addSpaceTapped), for: .touchUpInside)
        topBar.addSubview(addSpaceButton)

        topBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(52)
        }
        addSpaceButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        spacesScroll.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.trailing.equalTo(addSpaceButton.snp.leading).offset(-8)
            make.top.bottom.equalToSuperview()
        }
        spacesStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.trailing.equalToSuperview().offset(-4)
            make.centerY.equalToSuperview()
            make.height.equalTo(36)
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
            make.top.equalTo(topBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottomBar.snp.top)
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
        view.addSubview(bottomBar)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        privateButton.setImage(UIImage(systemName: "eyeglasses", withConfiguration: symbolConfig), for: .normal)
        privateButton.setTitle(" Private", for: .normal)
        privateButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        privateButton.contentHorizontalAlignment = .leading
        privateButton.accessibilityLabel = "Private"
        privateButton.addTarget(self, action: #selector(privateTapped), for: .touchUpInside)

        addButton.setImage(
            UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)),
            for: .normal
        )
        addButton.accessibilityLabel = "New Tab"
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        bottomBar.addSubview(privateButton)
        bottomBar.addSubview(addButton)
        bottomBar.addSubview(doneButton)

        bottomBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(56)
        }
        privateButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.height.equalTo(44)
        }
        addButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(44)
        }
        doneButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-20)
            make.centerY.equalToSuperview()
            make.height.equalTo(44)
        }
    }

    // MARK: - Reload / layout mode

    private func reload() {
        if !showingIncognito {
            if tabManager.container(id: focusedSpaceID) == nil {
                focusedSpaceID = tabManager.resolvedLastActiveContainerID
            }
        }
        applyChrome()
        applySurfaceLayout()
        rebuildSpacePills()
        collectionView.dragInteractionEnabled = canReorderTabs
        collectionView.reloadData()
        updateCollectionHeight()
        rebuildLibrarySections()
    }

    /// Refresh tab cards after async webpage snapshots finish.
    func reloadPreviews() {
        guard isViewLoaded else { return }
        collectionView.reloadData()
        presentedAccountPopup?.reloadPreviews()
    }

    private func applySurfaceLayout() {
        collectionView.isHidden = false
        let topHeight: CGFloat = showingIncognito ? 0 : 52
        topBar.snp.updateConstraints { $0.height.equalTo(topHeight) }
        topBar.isHidden = showingIncognito
        privateButton.accessibilityValue = showingIncognito ? "On" : "Off"
    }

    private func updateCollectionHeight() {
        let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : view.bounds.width
        guard width > 0 else { return }
        let metrics = TabGridMetrics.layout(forContainerWidth: width)
        let count = max(gridItemCount, 0)
        let height: CGFloat
        if count == 0 {
            height = 24
        } else {
            let rows = Int(ceil(Double(count) / Double(metrics.columns)))
            height = CGFloat(rows) * metrics.itemSize.height
                + CGFloat(max(0, rows - 1)) * TabGridMetrics.spacing
                + TabGridMetrics.sectionInset.top + TabGridMetrics.sectionInset.bottom
        }
        collectionHeightConstraint?.update(offset: height)
        if let flow = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            let inset = TabGridMetrics.sectionInset
            if flow.sectionInset != inset {
                flow.sectionInset = inset
                flow.minimumInteritemSpacing = TabGridMetrics.spacing
                flow.minimumLineSpacing = TabGridMetrics.spacing
            }
        }
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func rebuildSpacePills() {
        spacesStack.arrangedSubviews.forEach {
            spacesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard !showingIncognito else { return }

        for container in tabManager.sortedContainers {
            let selected = container.id == focusedSpaceID
            let color = tabManager.accountColor(forContainer: container.id)
            let pill = makeSpacePill(
                title: container.name,
                color: color,
                selected: selected,
                tag: tabManager.sortedContainers.firstIndex(where: { $0.id == container.id }) ?? 0,
                containerID: container.id
            )
            pill.accessibilityIdentifier = container.id.uuidString
            spacesStack.addArrangedSubview(pill)
        }
    }

    private func makeSpacePill(
        title: String,
        color: UIColor,
        selected: Bool,
        tag: Int,
        containerID: UUID
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.addTarget(self, action: #selector(spacePillTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = title
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 14)
        // Long-press menu; tap still switches Space.
        button.menu = makeSpacePillMenu(for: containerID)
        button.showsMenuAsPrimaryAction = false

        button.setImage(Self.spaceDotImage(color: color), for: .normal)
        button.setTitle("  \(title)", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.tintColor = selected ? BrowserTheme.textPrimary : BrowserTheme.textSecondary
        button.setTitleColor(selected ? BrowserTheme.textPrimary : BrowserTheme.textSecondary, for: .normal)
        button.backgroundColor = selected
            ? BrowserTheme.secondaryCard
            : BrowserTheme.card.withAlphaComponent(0.55)
        if selected {
            button.layer.borderWidth = 1.5
            button.layer.borderColor = color.withAlphaComponent(0.85).cgColor
        } else {
            button.layer.borderWidth = 0
            button.layer.borderColor = UIColor.clear.cgColor
        }
        button.snp.makeConstraints { $0.height.equalTo(36) }
        return button
    }

    private func makeSpacePillMenu(for containerID: UUID) -> UIMenu {
        let edit = UIAction(
            title: "Edit Space",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            guard let self, let container = self.tabManager.container(id: containerID) else { return }
            self.presentEditSpace(container)
        }
        let delete = UIAction(
            title: "Delete Space and Its Tabs",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let container = self.tabManager.container(id: containerID) else { return }
            self.confirmDeleteSpaceAndTabs(container)
        }
        return UIMenu(children: [edit, delete])
    }

    private func rebuildLibrarySections() {
        // Library under the tab grid in Spaces mode only.
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

        let containerID = focusedSpaceID
        bookmarkItems = Array(BookmarkStore.shared.items(containerID: containerID).filter { $0.url != nil }.prefix(12))
        historyItems = Array(HistoryStore.shared.items(containerID: containerID).filter { $0.url != nil }.prefix(12))

        bookmarksSection.isHidden = bookmarkItems.isEmpty
        historySection.isHidden = historyItems.isEmpty
        bookmarksTable.reloadData()
        historyTable.reloadData()
        applyLibraryExpansion(animated: false)
    }

    private static func spaceDotImage(color: UIColor, diameter: CGFloat = 10) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }.withRenderingMode(.alwaysOriginal)
    }

    @objc private func manageContainersTapped() {
        let vc = ContainerManageViewController(tabManager: tabManager)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func promptRename() {
        presentAccountPicker(title: "Rename Space") { [weak self] container in
            self?.presentRenameAlert(for: container)
        }
    }

    private func presentRenameAlert(for container: BrowserContainer) {
        let alert = UIAlertController(title: "Rename Space", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = container.name; $0.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?.first?.text ?? ""
            if self.tabManager.renameContainer(id: container.id, to: name) {
                self.reload()
            } else {
                let err = UIAlertController(title: "Spaces", message: "Couldn’t rename. Use a unique non-empty name.", preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(err, animated: true)
            }
        }))
        present(alert, animated: true)
    }

    private func promptDeleteAccount() {
        presentAccountPicker(title: "Delete Space") { [weak self] container in
            self?.confirmDelete(container)
        }
    }

    private func confirmDelete(_ container: BrowserContainer) {
        confirmDeleteSpaceAndTabs(container)
    }

    private func confirmDeleteSpaceAndTabs(_ container: BrowserContainer) {
        guard tabManager.containers.count > 1 else {
            let alert = UIAlertController(title: "Spaces", message: "Keep at least one space.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Delete Space?",
            message: "“\(container.name)” and all of its tabs will be deleted. The login session for this space will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            let tabIDs = self.tabManager.normalTabs
                .filter { $0.containerID == container.id }
                .map(\.id)
            for id in tabIDs {
                self.tabManager.closeTab(id: id)
            }
            let deletedFocused = self.focusedSpaceID == container.id
            _ = self.tabManager.deleteContainer(id: container.id)
            if deletedFocused {
                self.focusedSpaceID = self.tabManager.resolvedLastActiveContainerID
                _ = self.tabManager.switchToAccount(self.focusedSpaceID)
            }
            self.reload()
        }))
        present(alert, animated: true)
    }

    private func presentEditSpace(_ container: BrowserContainer) {
        let edit = ContainerEditViewController(container: container, tabManager: tabManager)
        edit.delegate = self
        let nav = UINavigationController(rootViewController: edit)
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        present(nav, animated: true)
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

    @objc private func privateTapped() {
        if showingIncognito {
            surface = .spaces
            _ = tabManager.switchToAccount(focusedSpaceID)
        } else {
            if let selected = tabManager.selectedTab, !selected.isIncognito {
                focusedSpaceID = selected.containerID
            }
            surface = .incognito
            let pool = tabManager.incognitoTabs
            if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
                tabManager.selectTab(id: tab.id)
            } else {
                _ = tabManager.addTab(incognito: true, select: true)
            }
        }
        reload()
    }

    @objc private func spacePillTapped(_ sender: UIButton) {
        let containers = tabManager.sortedContainers
        guard containers.indices.contains(sender.tag) else { return }
        let container = containers[sender.tag]
        focusedSpaceID = container.id
        _ = tabManager.switchToAccount(container.id)
        reload()
    }

    @objc private func addSpaceTapped() {
        presentNewAccount()
    }

    private var preferredContainerIDForNewTab: UUID? {
        if showingIncognito { return nil }
        return focusedSpaceID
    }

    @objc private func addTapped() {
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
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        present(nav, animated: true)
    }

    @objc private func doneTapped() {
        let selectedIsPrivate = tabManager.selectedTab?.isIncognito ?? false
        if selectedIsPrivate != showingIncognito {
            if showingIncognito {
                let pool = tabManager.incognitoTabs
                if let tab = pool.sorted(by: { $0.lastAccessed > $1.lastAccessed }).first {
                    tabManager.selectTab(id: tab.id)
                } else {
                    _ = tabManager.addTab(incognito: true, select: true)
                }
            } else {
                _ = tabManager.switchToAccount(focusedSpaceID)
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
        let alert = UIAlertController(title: "Move to Space", message: tab.title, preferredStyle: .actionSheet)
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
            message: "This tab will use that space’s cookies and login. It may look logged out of the previous space.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Move", style: .default, handler: { [weak self] _ in
            self?.tabManager.moveTab(tab.id, toContainer: container.id)
            self?.reload()
        }))
        present(alert, animated: true)
    }

}

// MARK: - Collection

extension TabSwitcherViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        gridItemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabGridCell.reuseID, for: indexPath) as! TabGridCell
        if showsNewTabPlaceholder {
            let color: UIColor = {
                if showingIncognito { return BrowserTheme.privateAccent }
                return tabManager.accountColor(forContainer: focusedSpaceID)
            }()
            cell.configureAsNewTabPlaceholder(accent: color, selected: true)
            cell.onClose = nil
            cell.onMoveGroup = nil
            return cell
        }

        let tab = displayedTabs[indexPath.item]
        let selected = tab.id == tabManager.selectedTab?.id
        cell.configure(
            tab: tab,
            containerName: tabManager.containerName(for: tab),
            accountColor: tabManager.accountColor(for: tab),
            selected: selected,
            isMediaPlaying: tab.webController?.indicatesPlayingMedia == true
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
        if showsNewTabPlaceholder {
            delegate?.tabSwitcherDidRequestNewTab(
                incognito: showingIncognito,
                containerID: preferredContainerIDForNewTab
            )
            return
        }
        let tab = displayedTabs[indexPath.item]
        tabManager.selectTab(id: tab.id)
        delegate?.tabSwitcherDidClose()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        TabGridMetrics.layout(forContainerWidth: collectionView.bounds.width).itemSize
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !showsNewTabPlaceholder else { return nil }
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
                UIMenu(title: "Move to Space", options: .displayInline, children: moveChildren)
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
            focusedSpaceID = container.id
            surface = .spaces
            _ = tabManager.switchToAccount(container.id)
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

// MARK: - Account section (expandable)

private final class AccountSectionView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onToggleExpanded: ((UUID) -> Void)?
    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onMoveGroup: ((BrowserTab) -> Void)?
    var onOpenAccountSheet: ((UUID) -> Void)?

    private let card = UIView()
    private let headerButton = UIButton(type: .custom)
    private let previewWell = UIView()
    private let previewA = UIImageView()
    private let previewB = UIImageView()
    private let placeholderIcon = UIImageView()
    private let dot = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView()
    private var collectionView: UICollectionView!
    private var collectionHeightConstraint: Constraint?

    private var containerID: UUID = UUID()
    private var tabs: [BrowserTab] = []
    private var selectedTabID: UUID?
    private var containerNameProvider: ((BrowserTab) -> String)?
    private var accountColorProvider: ((BrowserTab) -> UIColor)?
    private var accountColor: UIColor = BrowserTheme.chromeBlue
    private var isExpanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        addSubview(card)
        card.snp.makeConstraints { $0.edges.equalToSuperview() }

        headerButton.accessibilityLabel = "Space"
        headerButton.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(headerLongPressed(_:)))
        headerButton.addGestureRecognizer(longPress)

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
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = BrowserTheme.textSecondary

        chevron.contentMode = .scaleAspectFit
        chevron.tintColor = BrowserTheme.textSecondary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = TabGridMetrics.spacing
        layout.minimumInteritemSpacing = TabGridMetrics.spacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 12, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabGridCell.self, forCellWithReuseIdentifier: TabGridCell.reuseID)

        card.addSubview(headerButton)
        headerButton.addSubview(previewWell)
        previewWell.addSubview(previewA)
        previewWell.addSubview(previewB)
        previewWell.addSubview(placeholderIcon)
        headerButton.addSubview(dot)
        headerButton.addSubview(titleLabel)
        headerButton.addSubview(subtitleLabel)
        headerButton.addSubview(chevron)
        card.addSubview(collectionView)

        headerButton.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(88)
        }
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
        chevron.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 14, height: 20))
        }
        dot.snp.makeConstraints { make in
            make.leading.equalTo(previewWell.snp.trailing).offset(14)
            make.top.equalToSuperview().offset(28)
            make.size.equalTo(10)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(dot.snp.trailing).offset(8)
            make.centerY.equalTo(dot)
            make.trailing.lessThanOrEqualTo(chevron.snp.leading).offset(-10)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(dot)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.trailing.lessThanOrEqualTo(chevron.snp.leading).offset(-10)
        }
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(headerButton.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
            collectionHeightConstraint = make.height.equalTo(0).constraint
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        containerID: UUID,
        name: String,
        color: UIColor,
        tabs: [BrowserTab],
        selectedTabID: UUID?,
        isCurrentAccount: Bool,
        isExpanded: Bool,
        contentWidth: CGFloat,
        containerNameProvider: @escaping (BrowserTab) -> String,
        accountColorProvider: @escaping (BrowserTab) -> UIColor
    ) {
        self.containerID = containerID
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.accountColor = color
        self.isExpanded = isExpanded
        self.containerNameProvider = containerNameProvider
        self.accountColorProvider = accountColorProvider

        titleLabel.text = name
        subtitleLabel.text = tabs.count == 1 ? "1 tab" : "\(tabs.count) tabs"
        dot.backgroundColor = color
        headerButton.accessibilityLabel = name
        headerButton.accessibilityHint = isExpanded ? "Collapse tabs" : "Expand tabs"

        chevron.image = UIImage(
            systemName: isExpanded ? "chevron.down" : "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )

        card.layer.borderWidth = isCurrentAccount ? 2 : 0
        card.layer.borderColor = color.cgColor
        if isCurrentAccount {
            card.backgroundColor = color.withAlphaComponent(0.12)
        } else {
            card.backgroundColor = BrowserTheme.card
        }

        let previews = tabs.prefix(2).compactMap { AppSettings.showTabsPreviewImages ? $0.snapshot : nil }
        applyHeaderPreviews(Array(previews))

        let gridHeight: CGFloat
        if isExpanded, !tabs.isEmpty {
            let metrics = TabGridMetrics.layout(forContainerWidth: contentWidth)
            let rows = Int(ceil(Double(tabs.count) / Double(metrics.columns)))
            let inset = UIEdgeInsets(top: 0, left: 12, bottom: 12, right: 12)
            gridHeight = CGFloat(rows) * metrics.itemSize.height
                + CGFloat(max(0, rows - 1)) * TabGridMetrics.spacing
                + inset.top + inset.bottom
            collectionView.isHidden = false
            collectionView.alpha = 1
        } else if isExpanded {
            gridHeight = 8
            collectionView.isHidden = true
            collectionView.alpha = 0
        } else {
            gridHeight = 0
            collectionView.isHidden = true
            collectionView.alpha = 0
        }
        collectionHeightConstraint?.update(offset: gridHeight)
        collectionView.reloadData()
    }

    private func applyHeaderPreviews(_ images: [UIImage]) {
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

    @objc private func headerTapped() {
        onToggleExpanded?(containerID)
    }

    @objc private func headerLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        onOpenAccountSheet?(containerID)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        isExpanded ? tabs.count : 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabGridCell.reuseID, for: indexPath) as! TabGridCell
        let tab = tabs[indexPath.item]
        cell.configure(
            tab: tab,
            containerName: containerNameProvider?(tab) ?? "",
            accountColor: accountColorProvider?(tab) ?? accountColor,
            selected: tab.id == selectedTabID,
            isMediaPlaying: tab.webController?.indicatesPlayingMedia == true
        )
        cell.onClose = { [weak self] in
            self?.onCloseTab?(tab.id)
        }
        cell.onMoveGroup = { [weak self] in
            self?.onMoveGroup?(tab)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelectTab?(tabs[indexPath.item].id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        TabGridMetrics.layout(forContainerWidth: collectionView.bounds.width > 0
            ? collectionView.bounds.width
            : bounds.width).itemSize
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let tab = tabs[indexPath.item]
        return UIContextMenuConfiguration(identifier: tab.id.uuidString as NSString, previewProvider: nil) { [weak self] _ in
            UIMenu(title: "", children: [
                UIAction(title: "Move to Space", image: UIImage(systemName: "folder")) { [weak self] _ in
                    self?.onMoveGroup?(tab)
                },
                UIAction(title: "Close Tab", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in
                    self?.onCloseTab?(tab.id)
                }
            ])
        }
    }
}

// MARK: - Tab grid metrics

enum TabGridMetrics {
    static let spacing: CGFloat = 12
    static let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 4, right: 12)
    /// Keep cards phone-sized even on wide iPad landscape.
    private static let idealMaxItemWidth: CGFloat = 220

    struct Layout {
        let columns: Int
        let itemSize: CGSize
    }

    static func layout(forContainerWidth width: CGFloat) -> Layout {
        let usable = max(width, 1)
        let horizontalInsets = sectionInset.left + sectionInset.right
        let available = max(usable - horizontalInsets, 1)
        let columns = max(
            2,
            min(6, Int(floor((available + spacing) / (idealMaxItemWidth + spacing))))
        )
        let itemWidth = floor((available - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        return Layout(columns: columns, itemSize: CGSize(width: itemWidth, height: itemWidth * 1.25))
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
    private let speakingIndicator = UIImageView()
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
        groupButton.accessibilityLabel = "Move to Space"
        groupButton.accessibilityHint = "Choose a space for this tab"
        groupButton.addTarget(self, action: #selector(groupTapped), for: .touchUpInside)

        speakingIndicator.contentMode = .scaleAspectFit
        speakingIndicator.image = UIImage(
            systemName: "speaker.wave.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        )
        speakingIndicator.tintColor = BrowserTheme.chromeBlue
        speakingIndicator.isHidden = true
        speakingIndicator.accessibilityLabel = "Playing media"
        speakingIndicator.isAccessibilityElement = true

        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)),
            for: .normal
        )
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
        headerBar.addSubview(speakingIndicator)
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
            make.top.equalToSuperview().offset(6)
            make.trailing.equalToSuperview().offset(-8)
            make.size.equalTo(22)
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
        speakingIndicator.snp.makeConstraints { make in
            make.centerY.equalTo(groupButton)
            make.trailing.equalToSuperview().offset(-10)
            make.size.equalTo(16)
        }
        groupButton.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(2)
            make.leading.equalToSuperview().offset(8)
            make.trailing.lessThanOrEqualTo(speakingIndicator.snp.leading).offset(-6)
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

    func configure(
        tab: BrowserTab,
        containerName: String,
        accountColor: UIColor,
        selected: Bool,
        isMediaPlaying: Bool = false
    ) {
        configuredTabID = tab.id
        titleLabel.text = tab.title
        groupButton.isHidden = false
        closeButton.isHidden = false
        colorBar.isHidden = false
        let name = containerName.trimmingCharacters(in: .whitespacesAndNewlines)
        groupButton.setTitle(name.isEmpty ? "Space" : name, for: .normal)
        groupButton.setTitleColor(accountColor, for: .normal)
        groupButton.tintColor = accountColor
        colorBar.backgroundColor = accountColor
        speakingIndicator.isHidden = !isMediaPlaying
        speakingIndicator.tintColor = accountColor
        speakingIndicator.snp.updateConstraints { make in
            make.size.equalTo(isMediaPlaying ? 16 : 0)
        }
        if let avatar = tab.sessionAvatar {
            avatarView.image = avatar
            avatarView.isHidden = false
        } else {
            avatarView.image = nil
            avatarView.isHidden = true
        }
        preview.contentMode = .scaleAspectFill
        preview.tintColor = nil
        if AppSettings.showTabsPreviewImages, let snapshot = tab.snapshot {
            preview.image = snapshot
            placeholder.isHidden = true
            upgradePreviewToStandard(for: tab.id)
        } else {
            preview.image = nil
            placeholder.isHidden = false
            placeholder.text = "Page"
            placeholder.font = .systemFont(ofSize: 15)
            placeholder.textColor = BrowserTheme.textSecondary
        }
        // Always outline cards; selected uses a stronger stroke.
        card.layer.borderWidth = selected ? 2.5 : 1.5
        card.layer.borderColor = (selected ? accountColor : accountColor.withAlphaComponent(0.55)).cgColor
    }

    /// Empty-space placeholder matching the reference “New Tab” card.
    func configureAsNewTabPlaceholder(accent: UIColor, selected: Bool) {
        configuredTabID = nil
        titleLabel.text = "New Tab"
        groupButton.isHidden = true
        closeButton.isHidden = true
        colorBar.isHidden = true
        avatarView.isHidden = true
        speakingIndicator.isHidden = true
        placeholder.isHidden = true
        preview.contentMode = .center
        preview.tintColor = accent
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .medium)
        preview.image = UIImage(systemName: "sparkle", withConfiguration: config)
        card.layer.borderWidth = selected ? 2.5 : 1.5
        card.layer.borderColor = accent.cgColor
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
