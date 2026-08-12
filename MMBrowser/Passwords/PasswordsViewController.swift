import UIKit
import SnapKit

final class PasswordsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchController = UISearchController(searchResultsController: nil)
    private var items: [PasswordItem] = []
    private var query = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Passwords"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PasswordStore.shared.reload()
        reload()
    }

    @objc private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        if let nav = navigationController {
            BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        }
        tableView.reloadData()
    }

    @objc private func appDidEnterBackground() {
        PasswordVaultGate.invalidate()
    }

    private func reload() {
        items = PasswordStore.shared.items(matching: query)
        tableView.reloadData()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func addTapped() {
        let edit = PasswordEditViewController(
            mode: .create,
            defaultContainerID: ContainerScope.defaultContainerID()
        )
        edit.onSaved = { [weak self] in self?.reload() }
        let nav = UINavigationController(rootViewController: edit)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = searchController.searchBar.text ?? ""
        reload()
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return max(items.count, 1)
        default: return items.isEmpty ? 0 : 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? "SAVED PASSWORDS" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = indexPath.section == 1 && !items.isEmpty ? "subtitle" : "basic"
        let cell = tableView.dequeueReusableCell(withIdentifier: id)
            ?? UITableViewCell(style: id == "subtitle" ? .subtitle : .default, reuseIdentifier: id)
        cell.accessoryView = nil
        cell.imageView?.image = nil
        cell.detailTextLabel?.text = nil
        cell.textLabel?.numberOfLines = 1
        cell.textLabel?.textAlignment = .natural
        cell.selectionStyle = .default
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary

        switch indexPath.section {
        case 0:
            cell.textLabel?.text = "AutoFill settings"
            cell.accessoryType = .disclosureIndicator
            cell.imageView?.image = UIImage(systemName: "gearshape")
            cell.imageView?.tintColor = BrowserTheme.chromeBlue
        case 1:
            if items.isEmpty {
                cell.textLabel?.text = "No saved passwords"
                cell.textLabel?.textColor = BrowserTheme.textSecondary
                cell.accessoryType = .none
                cell.selectionStyle = .none
            } else {
                let item = items[indexPath.row]
                cell.textLabel?.text = item.host
                cell.detailTextLabel?.text = item.username
                cell.accessoryType = .disclosureIndicator
                cell.imageView?.image = UIImage(systemName: "globe")
                cell.imageView?.tintColor = BrowserTheme.chromeBlue
            }
        default:
            cell.textLabel?.text = "Delete all passwords"
            cell.textLabel?.textColor = .systemRed
            cell.accessoryType = .none
            cell.textLabel?.textAlignment = .center
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            navigationController?.pushViewController(AutofillSettingsViewController(), animated: true)
        case 1:
            guard !items.isEmpty else { return }
            let detail = PasswordDetailViewController(item: items[indexPath.row])
            detail.onChanged = { [weak self] in self?.reload() }
            navigationController?.pushViewController(detail, animated: true)
        default:
            confirmDeleteAll()
        }
    }

    private func confirmDeleteAll() {
        let alert = UIAlertController(
            title: "Delete All Passwords?",
            message: "This permanently removes every saved password from this device.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Delete All", style: .destructive) { [weak self] _ in
            _ = PasswordStore.shared.removeAll()
            self?.reload()
            if let self { Toast.show("All passwords deleted", from: self) }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.bounds
        }
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }
}
