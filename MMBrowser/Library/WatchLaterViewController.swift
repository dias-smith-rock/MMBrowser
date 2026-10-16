import UIKit

/// Watch Later list for one space: add, edit, delete, and clear.
final class WatchLaterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    var containerID: UUID = ContainerScope.resolveContainerID(nil)
    var currentPageTitle: String?
    var currentPageURL: URL?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [(day: Date, items: [WatchLaterItem])] = []

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Watch Later"
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addTapped)),
            UIBarButtonItem(title: "Clear All", style: .plain, target: self, action: #selector(clearAll))
        ]
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        reloadSections()
        tableView.backgroundColor = BrowserTheme.background
        tableView.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.25)
        tableView.tintColor = BrowserTheme.chromeBlue
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        updateClearButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSections()
        tableView.reloadData()
        updateClearButton()
    }

    private func reloadSections() {
        sections = WatchLaterStore.shared.sectionsByDay(containerID: containerID)
    }

    private func updateClearButton() {
        navigationItem.rightBarButtonItems?.last?.isEnabled = !sections.isEmpty
    }

    private func title(for day: Date) -> String {
        dayFormatter.string(from: day)
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        makeDayHeader(
            title: title(for: sections[section].day),
            count: sections[section].items.count,
            section: section
        )
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 44 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let item = sections[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.urlString
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.card
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let url = sections[indexPath.section].items[indexPath.row].url {
            onSelectURL?(url)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let item = self.sections[indexPath.section].items[indexPath.row]
            WatchLaterStore.shared.remove(id: item.id)
            self.reloadAfterMutation()
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let item = self.sections[indexPath.section].items[indexPath.row]
            self.presentEditor(item: item)
            done(true)
        }
        edit.backgroundColor = BrowserTheme.chromeBlue
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    private func makeDayHeader(title: String, count: Int, section: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let titleLabel = UILabel()
        titleLabel.text = "\(title)  ·  \(count)"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        clearButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        clearButton.tag = section
        clearButton.addTarget(self, action: #selector(clearDayButtonTapped(_:)), for: .touchUpInside)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, clearButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    @objc private func clearDayButtonTapped(_ sender: UIButton) {
        confirmClearDay(at: sender.tag)
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func addTapped() {
        presentEditor(item: nil)
    }

    @objc private func clearAll() {
        let alert = UIAlertController(
            title: "Clear Watch Later?",
            message: "Every Watch Later entry in this space will be removed.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            guard let self else { return }
            WatchLaterStore.shared.clear(containerID: self.containerID)
            self.reloadAfterMutation()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(alert, animated: true)
    }

    private func confirmClearDay(at section: Int) {
        guard sections.indices.contains(section) else { return }
        let day = sections[section].day
        let label = title(for: day)
        let count = sections[section].items.count
        let alert = UIAlertController(
            title: "Clear \(label)?",
            message: count == 1 ? "1 entry will be deleted." : "\(count) entries will be deleted.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Clear Day", style: .destructive) { [weak self] _ in
            guard let self else { return }
            WatchLaterStore.shared.remove(onDayOf: day, containerID: self.containerID)
            self.reloadAfterMutation()
            Toast.show("Cleared \(label)", from: self)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.rectForHeader(inSection: section)
        }
        present(alert, animated: true)
    }

    private func presentEditor(item: WatchLaterItem?) {
        let isNew = item == nil
        let alert = UIAlertController(
            title: isNew ? "Add to Watch Later" : "Edit Watch Later",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Title"
            field.text = item?.title ?? self.currentPageTitle
            field.clearButtonMode = .whileEditing
        }
        alert.addTextField { field in
            field.placeholder = "https://"
            field.text = item?.urlString ?? self.currentPageURL?.absoluteString
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: isNew ? "Add" : "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?.first?.text ?? ""
            let rawURL = alert.textFields?.dropFirst().first?.text ?? ""
            guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                Toast.show("Enter a valid http or https URL", from: self)
                return
            }
            if let item {
                if WatchLaterStore.shared.update(id: item.id, title: title, url: url) {
                    Toast.show("Saved", from: self)
                } else {
                    Toast.show("Couldn’t save. Use a unique URL.", from: self)
                }
            } else if WatchLaterStore.shared.add(title: title, url: url, containerID: self.containerID) {
                Toast.show("Added to Watch Later", from: self)
            } else {
                Toast.show("Already in Watch Later", from: self)
            }
            self.reloadAfterMutation()
        })
        present(alert, animated: true)
    }

    private func reloadAfterMutation() {
        reloadSections()
        tableView.reloadData()
        updateClearButton()
    }
}
