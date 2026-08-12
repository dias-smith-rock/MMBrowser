import UIKit

final class BookmarksViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    /// When set, shows an “Add Current Page” entry at the top of the list.
    var currentPageTitle: String?
    var currentPageURL: URL?
    var containerID: UUID = ContainerScope.resolveContainerID(nil)

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [BookmarkItem] = []
    private var isSelecting = false
    private let addCurrentTitleLabel = UILabel()
    private let addCurrentSubtitle = UILabel()
    private let addCurrentURLLabel = UILabel()
    private let addCurrentHeader = UIView()
    private let addCurrentCard = UIView()

    private lazy var selectButton = UIBarButtonItem(title: "Select", style: .plain, target: self, action: #selector(toggleSelect))
    private lazy var sortButton = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: self, action: #selector(presentSortMenu))
    private lazy var deleteButton = UIBarButtonItem(title: "Delete", style: .plain, target: self, action: #selector(deleteSelected))
    private lazy var doneSelectButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(toggleSelect))

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bookmarks"
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        reloadItems()
        setupAddCurrentHeader()
        tableView.backgroundColor = BrowserTheme.background
        tableView.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.25)
        tableView.tintColor = BrowserTheme.chromeBlue
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        updateToolbarButtons()
        refreshAddCurrentHeader()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadItems()
        tableView.reloadData()
        updateToolbarButtons()
        refreshAddCurrentHeader()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard tableView.tableHeaderView === addCurrentHeader else { return }
        layoutAddCurrentHeaderIfNeeded()
    }

    private func setupAddCurrentHeader() {
        addCurrentHeader.backgroundColor = BrowserTheme.background

        addCurrentCard.backgroundColor = BrowserTheme.card
        addCurrentCard.layer.cornerRadius = 12
        addCurrentCard.clipsToBounds = true

        let icon = UIImageView(image: UIImage(systemName: "plus.circle.fill"))
        icon.tintColor = BrowserTheme.chromeBlue
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        addCurrentTitleLabel.text = "Add Current Page"
        addCurrentTitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        addCurrentTitleLabel.textColor = BrowserTheme.textPrimary
        addCurrentTitleLabel.numberOfLines = 1

        addCurrentSubtitle.font = .systemFont(ofSize: 14, weight: .medium)
        addCurrentSubtitle.textColor = BrowserTheme.textPrimary
        addCurrentSubtitle.numberOfLines = 2
        addCurrentSubtitle.lineBreakMode = .byTruncatingTail

        addCurrentURLLabel.font = .systemFont(ofSize: 12)
        addCurrentURLLabel.textColor = BrowserTheme.textSecondary
        addCurrentURLLabel.numberOfLines = 2
        addCurrentURLLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = UIStackView(arrangedSubviews: [addCurrentTitleLabel, addCurrentSubtitle, addCurrentURLLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .fill

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 12

        addCurrentHeader.addSubview(addCurrentCard)
        addCurrentCard.addSubview(row)
        addCurrentCard.translatesAutoresizingMaskIntoConstraints = false
        row.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addCurrentCard.leadingAnchor.constraint(equalTo: addCurrentHeader.leadingAnchor, constant: 16),
            addCurrentCard.trailingAnchor.constraint(equalTo: addCurrentHeader.trailingAnchor, constant: -16),
            addCurrentCard.topAnchor.constraint(equalTo: addCurrentHeader.topAnchor, constant: 10),
            addCurrentCard.bottomAnchor.constraint(equalTo: addCurrentHeader.bottomAnchor, constant: -10),
            row.leadingAnchor.constraint(equalTo: addCurrentCard.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: addCurrentCard.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: addCurrentCard.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: addCurrentCard.bottomAnchor, constant: -14),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            icon.topAnchor.constraint(equalTo: row.topAnchor, constant: 1)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(addCurrentPageTapped))
        addCurrentCard.addGestureRecognizer(tap)
        addCurrentCard.isUserInteractionEnabled = true
    }

    private func refreshAddCurrentHeader() {
        guard !isSelecting, let url = currentPageURL, !BookmarkStore.shared.contains(url: url, containerID: containerID) else {
            tableView.tableHeaderView = nil
            return
        }
        let pageTitle = (currentPageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.host
            ?? "Untitled"
        addCurrentTitleLabel.text = "Add Current Page"
        addCurrentSubtitle.text = pageTitle
        addCurrentURLLabel.text = url.absoluteString
        addCurrentHeader.isUserInteractionEnabled = true
        addCurrentHeader.alpha = 1
        tableView.tableHeaderView = addCurrentHeader
        layoutAddCurrentHeaderIfNeeded()
    }

    private func layoutAddCurrentHeaderIfNeeded() {
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        guard width > 0 else { return }
        addCurrentHeader.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        addCurrentHeader.setNeedsLayout()
        addCurrentHeader.layoutIfNeeded()
        let size = addCurrentHeader.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let height = max(88, ceil(size.height))
        if abs(addCurrentHeader.frame.height - height) > 0.5 || abs(addCurrentHeader.frame.width - width) > 0.5 {
            addCurrentHeader.frame = CGRect(x: 0, y: 0, width: width, height: height)
            tableView.tableHeaderView = addCurrentHeader
        }
    }

    @objc private func addCurrentPageTapped() {
        guard let url = currentPageURL else { return }
        let title = currentPageTitle ?? ""
        if BookmarkStore.shared.add(title: title, url: url, containerID: containerID) {
            reloadItems()
            tableView.reloadData()
            updateToolbarButtons()
            refreshAddCurrentHeader()
            Toast.show("Bookmark added", from: self)
        } else {
            refreshAddCurrentHeader()
            Toast.show("Already bookmarked", from: self)
        }
    }

    private func reloadItems() {
        items = BookmarkStore.shared.items(containerID: containerID)
    }

    private func updateToolbarButtons() {
        if isSelecting {
            let count = tableView.indexPathsForSelectedRows?.count ?? 0
            deleteButton.isEnabled = count > 0
            deleteButton.title = count > 0 ? "Delete (\(count))" : "Delete"
            navigationItem.rightBarButtonItems = [doneSelectButton, deleteButton]
            tableView.tableHeaderView = nil
        } else {
            selectButton.isEnabled = !items.isEmpty
            navigationItem.rightBarButtonItems = [selectButton, sortButton]
            refreshAddCurrentHeader()
        }
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.urlString
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.background
        cell.selectionStyle = .default
        cell.accessoryType = isSelecting ? .none : .detailButton
        cell.tintColor = BrowserTheme.chromeBlue
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isSelecting {
            updateToolbarButtons()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if let url = items[indexPath.row].url {
            onSelectURL?(url)
        }
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        presentEdit(for: items[indexPath.row])
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isSelecting {
            updateToolbarButtons()
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isSelecting else { return nil }
        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
            guard let self = self else { done(false); return }
            self.presentEdit(for: self.items[indexPath.row])
            done(true)
        }
        edit.backgroundColor = BrowserTheme.chromeBlue

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self = self else { done(false); return }
            BookmarkStore.shared.remove(id: self.items[indexPath.row].id)
            self.reloadItems()
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.updateToolbarButtons()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isSelecting else { return nil }
        let item = items[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let open = UIAction(title: "Open", image: UIImage(systemName: "safari")) { _ in
                if let url = item.url {
                    self?.onSelectURL?(url)
                }
            }
            let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { _ in
                self?.presentEdit(for: item)
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                BookmarkStore.shared.remove(id: item.id)
                self?.reloadItems()
                self?.tableView.reloadData()
                self?.updateToolbarButtons()
            }
            return UIMenu(children: [open, edit, delete])
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        !isSelecting && BookmarkStore.shared.sort == .manual
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        BookmarkStore.shared.moveItem(from: sourceIndexPath.row, to: destinationIndexPath.row, containerID: containerID)
        reloadItems()
    }

    // MARK: - Actions

    @objc private func close() { dismiss(animated: true) }

    @objc private func toggleSelect() {
        isSelecting.toggle()
        tableView.setEditing(isSelecting, animated: true)
        tableView.reloadData()
        updateToolbarButtons()
    }

    @objc private func deleteSelected() {
        guard let paths = tableView.indexPathsForSelectedRows, !paths.isEmpty else { return }
        let ids = Set(paths.map { items[$0.row].id })
        let alert = UIAlertController(
            title: ids.count == 1 ? "Delete Bookmark?" : "Delete \(ids.count) Bookmarks?",
            message: "This cannot be undone.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            BookmarkStore.shared.remove(ids: ids)
            self.reloadItems()
            self.isSelecting = false
            self.tableView.setEditing(false, animated: true)
            self.tableView.reloadData()
            self.updateToolbarButtons()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = deleteButton
        }
        present(alert, animated: true)
    }

    @objc private func presentSortMenu() {
        let sheet = UIAlertController(title: "Sort Bookmarks", message: nil, preferredStyle: .actionSheet)
        let current = BookmarkStore.shared.sort
        for option in BookmarkSort.allCases {
            let title = option == current ? "✓ \(option.displayName)" : option.displayName
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                BookmarkStore.shared.setSort(option)
                self.reloadItems()
                self.tableView.reloadData()
                Toast.show("Sorted: \(option.displayName)", from: self)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = sortButton
        }
        present(sheet, animated: true)
    }

    private func presentEdit(for item: BookmarkItem) {
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
            guard let self = self else { return }
            let title = alert.textFields?[0].text ?? ""
            let urlString = alert.textFields?[1].text ?? ""
            if BookmarkStore.shared.update(id: item.id, title: title, urlString: urlString) {
                self.reloadItems()
                self.tableView.reloadData()
                Toast.show("Bookmark updated", from: self)
            } else {
                Toast.show("Couldn’t save — check the URL or duplicate", from: self)
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - Drag & drop reorder (manual sort)

extension BookmarksViewController: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard !isSelecting, BookmarkStore.shared.sort == .manual else { return [] }
        let item = items[indexPath.row]
        let provider = NSItemProvider(object: item.id.uuidString as NSString)
        let drag = UIDragItem(itemProvider: provider)
        drag.localObject = item.id
        return [drag]
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        guard !isSelecting, BookmarkStore.shared.sort == .manual,
              session.localDragSession != nil else {
            return UITableViewDropProposal(operation: .cancel)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard BookmarkStore.shared.sort == .manual,
              let destination = coordinator.destinationIndexPath,
              let item = coordinator.items.first,
              let source = item.sourceIndexPath else { return }
        tableView.performBatchUpdates {
            BookmarkStore.shared.moveItem(from: source.row, to: destination.row, containerID: containerID)
            reloadItems()
            tableView.moveRow(at: source, to: destination)
        }
        coordinator.drop(item.dragItem, toRowAt: destination)
    }
}
