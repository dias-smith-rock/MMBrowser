import UIKit
import SnapKit

/// Spaces management hub.
final class SpacesSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    var onAccountsChanged: (() -> Void)?
    weak var tabManager: TabManager?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Spaces"
        applyChrome()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
        tableView.reloadData()
    }

    @objc private func themeChanged() {
        applyChrome()
        tableView.reloadData()
    }

    private func applyChrome() {
        BrowserTheme.applyScreenChrome(to: self)
        tableView.backgroundColor = BrowserTheme.background
        tableView.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Spaces keep separate cookies, history, bookmarks, Watch Later, Reading List, home shortcuts, and passwords. Downloaded files are Shared across Spaces."
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        if indexPath.row == 0 {
            let count = tabManager?.visibleContainers.count ?? 0
            cell.textLabel?.text = "Manage Spaces"
            cell.detailTextLabel?.text = count == 1 ? "1 Space" : "\(count) Spaces"
        } else {
            cell.textLabel?.text = "Isolated vs Shared"
            cell.detailTextLabel?.text = "What stays per space"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 1 {
            navigationController?.pushViewController(IsolatedVsSharedViewController(), animated: true)
            return
        }
        guard let tabManager else { return }
        let manage = ContainerManageViewController(tabManager: tabManager)
        manage.showsDoneButton = false
        manage.onChanged = { [weak self] in
            self?.onAccountsChanged?()
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(manage, animated: true)
    }
}
