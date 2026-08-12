import UIKit
import SnapKit

final class ContainerSiteDataViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let container: BrowserContainer
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var summaries: [SiteDataSummary] = []

    init(container: BrowserContainer) {
        self.container = container
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Site Data"
        view.backgroundColor = BrowserTheme.background
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear All",
            style: .plain,
            target: self,
            action: #selector(clearAllTapped)
        )

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        reload()
    }

    private func reload() {
        ContainerSiteDataService.fetchSummaries(sessionID: container.sessionID) { [weak self] items in
            self?.summaries = items
            self?.tableView.reloadData()
        }
    }

    @objc private func clearAllTapped() {
        let alert = UIAlertController(
            title: "Clear Site Data?",
            message: "Removes cookies, cache, and storage for all sites in “\(container.name)”.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            ContainerSiteDataService.clearAll(sessionID: self.container.sessionID) {
                self.reload()
            }
        }))
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(summaries.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        BrowserTheme.styleListCell(cell)
        guard !summaries.isEmpty else {
            cell.textLabel?.text = "No site data stored"
            cell.selectionStyle = .none
            return cell
        }
        let item = summaries[indexPath.row]
        cell.textLabel?.text = item.host
        cell.detailTextLabel?.text = "\(item.recordCount) record(s) · \(item.dataTypes.count) type(s)"
        cell.accessoryType = .none
        return cell
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard summaries.indices.contains(indexPath.row) else { return nil }
        let host = summaries[indexPath.row].host
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            ContainerSiteDataService.remove(host: host, sessionID: self.container.sessionID) {
                self.reload()
            }
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
