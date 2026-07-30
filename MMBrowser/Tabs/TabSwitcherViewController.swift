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
    private let countBadge = UILabel()
    private let doneButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let mainScroll = UIScrollView()
    private let contentStack = UIStackView()
    private let bookmarksSection = UIStackView()
    private let readingSection = UIStackView()
    private var searchQuery = ""

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var displayedTabs: [BrowserTab] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = tabManager.tabs
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q)
                || ($0.url?.absoluteString.lowercased().contains(q) ?? false)
                || $0.groupName.lowercased().contains(q)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        setupTop()
        setupMainScroll()
        setupBottom()
        reload()
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

        countBadge.textAlignment = .center
        countBadge.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        countBadge.textColor = .black
        countBadge.backgroundColor = UIColor(white: 0.85, alpha: 1)
        countBadge.layer.cornerRadius = 14
        countBadge.clipsToBounds = true
        countBadge.adjustsFontSizeToFitWidth = true
        countBadge.baselineAdjustment = .alignCenters

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = BrowserTheme.textPrimary
        moreButton.accessibilityLabel = "More"
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()

        topBar.addSubview(search)
        topBar.addSubview(countBadge)
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
        countBadge.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.height.equalTo(28)
            make.width.equalTo(countBadge.snp.height).multipliedBy(1.35)
        }
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
        collectionView.register(TabGridCell.self, forCellWithReuseIdentifier: TabGridCell.reuseID)

        configureListSection(bookmarksSection, title: "Bookmarks")
        configureListSection(readingSection, title: "Reading list")

        contentStack.addArrangedSubview(collectionView)
        contentStack.addArrangedSubview(bookmarksSection)
        contentStack.addArrangedSubview(readingSection)

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

    private func configureListSection(_ section: UIStackView, title: String) {
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
        header.tag = 9001
        section.addArrangedSubview(header)
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
        let count = displayedTabs.count
        countBadge.text = "\(count)"
        let widthMultiplier: CGFloat = count >= 100 ? 2.0 : (count >= 10 ? 1.65 : 1.35)
        countBadge.snp.remakeConstraints { make in
            make.center.equalToSuperview()
            make.height.equalTo(28)
            make.width.equalTo(countBadge.snp.height).multipliedBy(widthMultiplier)
        }
        moreButton.menu = makeMoreMenu()
        collectionView.reloadData()
        updateCollectionHeight()
        rebuildLibrarySections()
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
        rebuildSection(
            bookmarksSection,
            items: BookmarkStore.shared.items.map { ($0.title, $0.urlString, $0.url) }
        )
        rebuildSection(
            readingSection,
            items: ReadingListStore.shared.items.map { ($0.title, $0.urlString, $0.url) }
        )
    }

    private func rebuildSection(_ section: UIStackView, items: [(String, String, URL?)]) {
        // Keep header (tag 9001), remove rows.
        section.arrangedSubviews.forEach { view in
            if view.tag != 9001 {
                section.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
        }

        let visible = items.filter { $0.2 != nil }
        section.isHidden = visible.isEmpty
        guard !visible.isEmpty else { return }

        for item in visible.prefix(12) {
            section.addArrangedSubview(makeLibraryRow(title: item.0, subtitle: item.1, url: item.2!))
        }
    }

    private func makeLibraryRow(title: String, subtitle: String, url: URL) -> UIView {
        let row = UIButton(type: .system)
        row.backgroundColor = BrowserTheme.card
        row.layer.cornerRadius = 12
        row.contentHorizontalAlignment = .left
        row.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 1

        let subtitleLabel = UILabel()
        subtitleLabel.text = URL(string: subtitle)?.host ?? subtitle
        subtitleLabel.textColor = BrowserTheme.textSecondary
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        row.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        }
        row.snp.makeConstraints { $0.height.greaterThanOrEqualTo(52) }

        row.addAction(UIAction { [weak self] _ in
            self?.delegate?.tabSwitcherDidRequestOpenURLInNewTab(url)
        }, for: .touchUpInside)

        return row
    }

    @objc private func addTapped() {
        let incognito = tabManager.selectedTab?.isIncognito ?? false
        delegate?.tabSwitcherDidRequestNewTab(incognito: incognito)
    }

    @objc private func doneTapped() {
        delegate?.tabSwitcherDidClose()
    }

    private func closeOtherTabs() {
        guard let selected = tabManager.selectedTab else { return }
        let others = tabManager.tabs.filter { $0.id != selected.id }
        for tab in others {
            tabManager.closeTab(id: tab.id)
        }
        reload()
    }

    private func closeAllTabs() {
        let ids = tabManager.tabs.map(\.id)
        for id in ids {
            tabManager.closeTab(id: id)
        }
        reload()
        if tabManager.tabs.isEmpty {
            delegate?.tabSwitcherDidClose()
        }
    }

    private func promptMoveGroup(for tab: BrowserTab) {
        let alert = UIAlertController(title: "Move to group", message: tab.title, preferredStyle: .actionSheet)
        for name in tabManager.groupNames {
            alert.addAction(UIAlertAction(title: name, style: .default, handler: { _ in
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

final class TabGridCell: UICollectionViewCell {
    static let reuseID = "TabGridCell"
    var onClose: (() -> Void)?
    var onMoveGroup: (() -> Void)?

    private let card = UIView()
    private let titleLabel = UILabel()
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
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = BrowserTheme.textSecondary
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        placeholder.text = "Page"
        placeholder.textColor = BrowserTheme.textSecondary
        placeholder.textAlignment = .center

        card.addSubview(titleLabel)
        card.addSubview(closeButton)
        card.addSubview(preview)
        card.addSubview(placeholder)

        card.snp.makeConstraints { $0.edges.equalToSuperview() }
        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(10)
            make.trailing.equalTo(closeButton.snp.leading).offset(-6)
        }
        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.trailing.equalToSuperview().offset(-6)
            make.size.equalTo(28)
        }
        preview.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(36)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholder.snp.makeConstraints { $0.center.equalTo(preview) }

        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        card.addGestureRecognizer(long)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: BrowserTab, selected: Bool) {
        titleLabel.text = tab.title
        preview.image = tab.snapshot
        placeholder.isHidden = tab.snapshot != nil
        card.layer.borderWidth = selected ? 2 : 0
        card.layer.borderColor = BrowserTheme.chromeBlue.cgColor
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { onMoveGroup?() }
    }
}
