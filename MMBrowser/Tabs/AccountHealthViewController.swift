import UIKit
import SnapKit

/// Per-account health summary: history/bookmarks counts, cookie domains, identity consistency hints.
final class AccountHealthViewController: UIViewController, UITableViewDataSource {
    private let tabManager: TabManager
    private let container: BrowserContainer
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var rows: [(title: String, detail: String)] = []

    init(tabManager: TabManager, container: BrowserContainer) {
        self.tabManager = tabManager
        self.container = container
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Account Health"
        view.backgroundColor = BrowserTheme.background
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        reloadMetrics()
    }

    private func reloadMetrics() {
        let historyCount = HistoryStore.shared.items(containerID: container.id).count
        let bookmarkCount = BookmarkStore.shared.items(containerID: container.id).count
        let tabCount = tabManager.normalTabs.filter { $0.containerID == container.id }.count
        rows = [
            ("Open tabs", "\(tabCount)"),
            ("History entries", "\(historyCount)"),
            ("Bookmarks", "\(bookmarkCount)"),
            ("Location", container.locationSummary),
            ("Locale", container.identity.localeIdentifier ?? "Device default"),
            ("User agent", container.identity.userAgentMode.displayName),
            ("Strip tracking URLs", container.identity.stripTrackingParams ? "On" : "Off"),
            ("Network IP", "Not changed — geolocation only affects browser APIs")
        ]
        ContainerSiteDataService.estimatedLoggedInDomains(sessionID: container.sessionID) { [weak self] count in
            guard let self else { return }
            self.rows.insert(("Sites with cookies", "\(count)"), at: 3)
            self.tableView.reloadData()
        }
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
        BrowserTheme.styleListCell(cell)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.detail
        cell.selectionStyle = .none
        return cell
    }
}
