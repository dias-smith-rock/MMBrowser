import UIKit
import SnapKit

/// Shared Bookmarks / History sheet (domain grouping).
/// Menu keeps separate Bookmarks and History entries; each opens this sheet on the matching tab.
final class LibrarySheetViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    enum Mode: Int {
        case bookmarks = 0
        case history = 1
    }

    var onSelectURL: ((URL) -> Void)?
    var currentPageTitle: String?
    var currentPageURL: URL?

    private var mode: Mode
    private let containerID: UUID
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let segment = UISegmentedControl(items: [
        UIImage(systemName: "bookmark") ?? "B",
        UIImage(systemName: "clock") ?? "H"
    ])
    private let searchController = UISearchController(searchResultsController: nil)
    private var query = ""

    private var bookmarkGroups: [(host: String, items: [BookmarkItem])] = []
    private var historyDays: [(day: Date, groups: [(host: String, items: [HistoryItem])])] = []
    /// Expanded keys: bookmarks `"b|host"` / history `"h|dayInterval|host"`.
    private var expanded = Set<String>()

    private lazy var dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    init(initialMode: Mode = .history, containerID: UUID) {
        self.mode = initialMode
        self.containerID = ContainerScope.resolveContainerID(containerID)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(clearAll)),
            UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(toggleSearch))
        ]
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        segment.selectedSegmentIndex = mode.rawValue
        segment.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        segment.selectedSegmentTintColor = BrowserTheme.secondaryCard
        // Title only — mode switcher sits below nav so Bookmarks/History remain distinct entries.
        title = mode == .bookmarks ? "Bookmarks" : "History"
        tableView.tableHeaderView = makeSegmentHeader()

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"
        searchController.searchBar.searchTextField.textColor = BrowserTheme.textPrimary
        definesPresentationContext = true

        tableView.backgroundColor = BrowserTheme.background
        tableView.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.18)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.keyboardDismissMode = .onDrag
        tableView.register(LibraryDomainCell.self, forCellReuseIdentifier: LibraryDomainCell.reuseID)
        tableView.register(LibraryPageCell.self, forCellReuseIdentifier: LibraryPageCell.reuseID)
        tableView.tableFooterView = UIView()
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        reloadData()
        updateChrome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
        tableView.reloadData()
        updateChrome()
    }

    // MARK: - Chrome

    private func makeSegmentHeader() -> UIView {
        let wrap = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        wrap.backgroundColor = BrowserTheme.background
        wrap.addSubview(segment)
        segment.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.height.equalTo(36)
        }
        return wrap
    }

    private func updateChrome() {
        title = mode == .bookmarks ? "Bookmarks" : "History"
        segment.selectedSegmentIndex = mode.rawValue
        let hasData = mode == .bookmarks ? !bookmarkGroups.isEmpty : !historyDays.isEmpty
        navigationItem.rightBarButtonItems?.first?.isEnabled = hasData
    }

    // MARK: - Data

    private func reloadData() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mode == .bookmarks {
            let groups = BookmarkStore.shared.groupsByHost(containerID: containerID)
            if q.isEmpty {
                bookmarkGroups = groups
            } else {
                bookmarkGroups = groups.compactMap { pair -> (host: String, items: [BookmarkItem])? in
                    let filtered = pair.items.filter {
                        $0.title.lowercased().contains(q)
                            || $0.urlString.lowercased().contains(q)
                            || pair.host.contains(q)
                    }
                    guard !filtered.isEmpty else { return nil }
                    return (host: pair.host, items: filtered)
                }
            }
        } else {
            let days = HistoryStore.shared.sectionsByDayThenHost(containerID: containerID)
            if q.isEmpty {
                historyDays = days
            } else {
                historyDays = days.compactMap { dayPair -> (day: Date, groups: [(host: String, items: [HistoryItem])])? in
                    let filteredGroups: [(host: String, items: [HistoryItem])] = dayPair.groups.compactMap { group in
                        let filtered = group.items.filter {
                            $0.title.lowercased().contains(q)
                                || $0.urlString.lowercased().contains(q)
                                || group.host.contains(q)
                        }
                        guard !filtered.isEmpty else { return nil }
                        return (host: group.host, items: filtered)
                    }
                    guard !filteredGroups.isEmpty else { return nil }
                    return (day: dayPair.day, groups: filteredGroups)
                }
            }
        }
    }

    private func expandKey(day: Date?, host: String) -> String {
        if let day {
            return "h|\(day.timeIntervalSince1970)|\(host)"
        }
        return "b|\(host)"
    }

    // MARK: - Rows

    private enum Row {
        case domain(host: String, count: Int, expanded: Bool, day: Date?)
        case bookmark(BookmarkItem)
        case history(HistoryItem)
    }

    private func rows(in section: Int) -> [Row] {
        if mode == .bookmarks {
            guard section == 0 else { return [] }
            var result: [Row] = []
            for group in bookmarkGroups {
                let key = expandKey(day: nil, host: group.host)
                let isExpanded = expanded.contains(key)
                result.append(.domain(host: group.host, count: group.items.count, expanded: isExpanded, day: nil))
                if isExpanded {
                    result.append(contentsOf: group.items.map { .bookmark($0) })
                }
            }
            return result
        } else {
            guard historyDays.indices.contains(section) else { return [] }
            let day = historyDays[section]
            var result: [Row] = []
            for group in day.groups {
                let key = expandKey(day: day.day, host: group.host)
                let isExpanded = expanded.contains(key)
                result.append(.domain(host: group.host, count: group.items.count, expanded: isExpanded, day: day.day))
                if isExpanded {
                    result.append(contentsOf: group.items.map { .history($0) })
                }
            }
            return result
        }
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int {
        if mode == .bookmarks {
            return bookmarkGroups.isEmpty ? 0 : 1
        }
        return historyDays.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows(in: section).count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard mode == .history, historyDays.indices.contains(section) else { return nil }
        return dayFormatter.string(from: historyDays[section].day)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
        if let header = view as? UITableViewHeaderFooterView {
            header.textLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows(in: indexPath.section)[indexPath.row]
        switch row {
        case let .domain(host, count, isExpanded, day):
            let cell = tableView.dequeueReusableCell(withIdentifier: LibraryDomainCell.reuseID, for: indexPath) as! LibraryDomainCell
            cell.configure(host: host, count: count, expanded: isExpanded)
            cell.onDelete = { [weak self] in
                self?.deleteDomain(host: host, day: day)
            }
            return cell
        case let .bookmark(item):
            let cell = tableView.dequeueReusableCell(withIdentifier: LibraryPageCell.reuseID, for: indexPath) as! LibraryPageCell
            cell.configure(
                title: item.title,
                urlString: item.urlString,
                timeText: nil,
                host: BookmarkStore.hostKey(forURLString: item.urlString),
                indented: true
            )
            cell.onDelete = { [weak self] in
                BookmarkStore.shared.remove(id: item.id)
                self?.reloadAfterMutation()
            }
            return cell
        case let .history(item):
            let cell = tableView.dequeueReusableCell(withIdentifier: LibraryPageCell.reuseID, for: indexPath) as! LibraryPageCell
            cell.configure(
                title: item.title,
                urlString: item.urlString,
                timeText: timeFormatter.string(from: item.date),
                host: HistoryStore.hostKey(for: item.urlString),
                indented: true
            )
            cell.onDelete = { [weak self] in
                HistoryStore.shared.remove(id: item.id)
                self?.reloadAfterMutation()
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = rows(in: indexPath.section)[indexPath.row]
        switch row {
        case let .domain(host, _, _, day):
            let key = expandKey(day: day, host: host)
            if expanded.contains(key) {
                expanded.remove(key)
            } else {
                expanded.insert(key)
            }
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
        case let .bookmark(item):
            if let url = item.url { onSelectURL?(url) }
        case let .history(item):
            if let url = item.url { onSelectURL?(url) }
        }
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard mode == .bookmarks else { return nil }
        let row = rows(in: indexPath.section)[indexPath.row]
        guard case let .bookmark(item) = row else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let open = UIAction(title: "Open", image: UIImage(systemName: "safari")) { _ in
                if let url = item.url {
                    self?.onSelectURL?(url)
                }
            }
            let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                self?.presentEditBookmark(item)
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                BookmarkStore.shared.remove(id: item.id)
                self?.reloadAfterMutation()
            }
            return UIMenu(children: [open, edit, delete])
        }
    }

    // MARK: - Actions

    private func presentEditBookmark(_ item: BookmarkItem) {
        let alert = UIAlertController(title: "Edit Bookmark", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = item.title
            field.placeholder = "Title"
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .words
        }
        alert.addTextField { field in
            field.text = item.urlString
            field.placeholder = "URL"
            field.clearButtonMode = .whileEditing
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?[0].text ?? ""
            let urlString = alert.textFields?[1].text ?? ""
            if BookmarkStore.shared.update(id: item.id, title: title, urlString: urlString) {
                self.reloadAfterMutation()
                Toast.show("Bookmark updated", from: self)
            } else {
                Toast.show("Couldn’t save — check the URL or duplicate", from: self)
            }
        })
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func segmentChanged() {
        mode = Mode(rawValue: segment.selectedSegmentIndex) ?? .history
        query = ""
        searchController.isActive = false
        navigationItem.searchController = nil
        expanded.removeAll()
        reloadData()
        tableView.reloadData()
        updateChrome()
    }

    @objc private func toggleSearch() {
        if navigationItem.searchController == nil {
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
            searchController.isActive = true
        } else {
            searchController.isActive = false
            navigationItem.searchController = nil
            query = ""
            reloadData()
            tableView.reloadData()
            updateChrome()
        }
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reloadData()
        tableView.reloadData()
        updateChrome()
    }

    @objc private func clearAll() {
        if mode == .bookmarks {
            let alert = UIAlertController(
                title: "Clear All Bookmarks?",
                message: "Every bookmark will be removed.",
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
                BookmarkStore.shared.clear(containerID: self?.containerID ?? ContainerScope.resolveContainerID(nil))
                self?.expanded.removeAll()
                self?.reloadAfterMutation()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        } else {
            let alert = UIAlertController(
                title: "Clear All History?",
                message: "Every browsing history entry will be removed.",
                preferredStyle: .actionSheet
            )
            alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
                HistoryStore.shared.clear(containerID: self?.containerID ?? ContainerScope.resolveContainerID(nil))
                self?.expanded.removeAll()
                self?.reloadAfterMutation()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }

    private func deleteDomain(host: String, day: Date?) {
        let count: Int = {
            if mode == .bookmarks {
                return bookmarkGroups.first(where: { $0.host == host })?.items.count ?? 0
            }
            guard let day else { return 0 }
            return historyDays.first(where: { Calendar.current.isDate($0.day, inSameDayAs: day) })?
                .groups.first(where: { $0.host == host })?.items.count ?? 0
        }()
        let alert = UIAlertController(
            title: "Delete \(host)?",
            message: count == 1 ? "1 entry will be deleted." : "\(count) entries will be deleted.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            if self.mode == .bookmarks {
                BookmarkStore.shared.remove(host: host, containerID: self.containerID)
            } else {
                HistoryStore.shared.remove(host: host, containerID: self.containerID, onDayOf: day)
            }
            self.expanded.remove(self.expandKey(day: day, host: host))
            self.reloadAfterMutation()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func reloadAfterMutation() {
        reloadData()
        tableView.reloadData()
        updateChrome()
    }
}

// MARK: - Cells

private enum LibraryRowIcon {
    static let delete = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    static let chevron = UIImage.SymbolConfiguration(pointSize: 7, weight: .light)
    static let hitSize: CGFloat = 22
}

private final class LibraryDomainCell: UITableViewCell {
    static let reuseID = "LibraryDomainCell"
    var onDelete: (() -> Void)?

    private let avatar = LetterAvatarView()
    private let hostLabel = UILabel()
    private let countBadge = UIView()
    private let countLabel = UILabel()
    private let chevronButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let rowStack = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = BrowserTheme.background
        contentView.backgroundColor = BrowserTheme.background

        hostLabel.font = .systemFont(ofSize: 16, weight: .medium)
        hostLabel.textColor = BrowserTheme.textPrimary
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countBadge.backgroundColor = BrowserTheme.secondaryCard
        countBadge.clipsToBounds = true
        countBadge.setContentHuggingPriority(.required, for: .horizontal)
        countBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = BrowserTheme.textSecondary
        countLabel.textAlignment = .center
        countBadge.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.equalToSuperview().offset(6)
            make.trailing.equalToSuperview().offset(-6)
        }
        countBadge.snp.makeConstraints { make in
            make.height.equalTo(20)
            make.width.greaterThanOrEqualTo(20)
        }

        chevronButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: LibraryRowIcon.chevron), for: .normal)
        chevronButton.tintColor = BrowserTheme.textSecondary
        chevronButton.isUserInteractionEnabled = false
        chevronButton.setContentHuggingPriority(.required, for: .horizontal)
        chevronButton.snp.makeConstraints { make in
            make.size.equalTo(LibraryRowIcon.hitSize)
        }

        deleteButton.setImage(UIImage(systemName: "xmark", withConfiguration: LibraryRowIcon.delete), for: .normal)
        deleteButton.tintColor = BrowserTheme.textSecondary
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.setContentHuggingPriority(.required, for: .horizontal)
        deleteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        deleteButton.snp.makeConstraints { make in
            make.size.equalTo(LibraryRowIcon.hitSize)
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 6
        rowStack.addArrangedSubview(avatar)
        rowStack.addArrangedSubview(hostLabel)
        rowStack.setCustomSpacing(8, after: hostLabel)
        rowStack.addArrangedSubview(countBadge)
        rowStack.setCustomSpacing(2, after: countBadge)
        rowStack.addArrangedSubview(chevronButton)
        rowStack.addArrangedSubview(spacer)
        rowStack.addArrangedSubview(deleteButton)

        contentView.addSubview(rowStack)
        avatar.snp.makeConstraints { make in
            make.size.equalTo(28)
        }
        rowStack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-10)
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().offset(-10)
            make.height.greaterThanOrEqualTo(32)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        countBadge.layer.cornerRadius = countBadge.bounds.height / 2
    }

    func configure(host: String, count: Int, expanded: Bool) {
        avatar.configure(title: host, colorSeed: host)
        hostLabel.text = host
        countLabel.text = "\(count)"
        countBadge.backgroundColor = BrowserTheme.secondaryCard
        countLabel.textColor = BrowserTheme.textSecondary
        chevronButton.setImage(
            UIImage(
                systemName: expanded ? "chevron.up" : "chevron.down",
                withConfiguration: LibraryRowIcon.chevron
            ),
            for: .normal
        )
    }

    @objc private func deleteTapped() { onDelete?() }
}

private final class LibraryPageCell: UITableViewCell {
    static let reuseID = "LibraryPageCell"
    var onDelete: (() -> Void)?

    private let avatar = LetterAvatarView()
    private let titleLabel = UILabel()
    private let urlLabel = UILabel()
    private let timeLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private let textStack = UIStackView()
    private var avatarLeadingConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = BrowserTheme.background
        contentView.backgroundColor = BrowserTheme.background

        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail

        urlLabel.font = .systemFont(ofSize: 12, weight: .regular)
        urlLabel.textColor = BrowserTheme.textSecondary
        urlLabel.lineBreakMode = .byTruncatingMiddle

        timeLabel.font = .systemFont(ofSize: 12, weight: .regular)
        timeLabel.textColor = BrowserTheme.textSecondary
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        deleteButton.setImage(UIImage(systemName: "xmark", withConfiguration: LibraryRowIcon.delete), for: .normal)
        deleteButton.tintColor = BrowserTheme.textSecondary
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(urlLabel)
        textStack.axis = .vertical
        textStack.spacing = 2

        contentView.addSubview(avatar)
        contentView.addSubview(textStack)
        contentView.addSubview(timeLabel)
        contentView.addSubview(deleteButton)

        avatar.snp.makeConstraints { make in
            avatarLeadingConstraint = make.leading.equalToSuperview().offset(16).constraint
            make.top.equalToSuperview().offset(12)
            make.size.equalTo(28)
        }
        deleteButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
            make.size.equalTo(LibraryRowIcon.hitSize)
        }
        timeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(deleteButton.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(avatar.snp.trailing).offset(12)
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().offset(-10)
            make.trailing.lessThanOrEqualTo(timeLabel.snp.leading).offset(-8)
            make.trailing.lessThanOrEqualTo(deleteButton.snp.leading).offset(-8)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, urlString: String, timeText: String?, host: String, indented: Bool) {
        avatar.configure(title: title.isEmpty ? host : title, colorSeed: host)
        titleLabel.text = title.isEmpty ? host : title
        urlLabel.text = urlString
        timeLabel.text = timeText
        timeLabel.isHidden = timeText == nil
        avatarLeadingConstraint?.update(offset: indented ? 36 : 16)
    }

    @objc private func deleteTapped() { onDelete?() }
}
