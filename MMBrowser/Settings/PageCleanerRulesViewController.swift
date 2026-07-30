import UIKit
import SnapKit

final class PageCleanerRulesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [(host: String, rules: [PageCleanerRule])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Webpage Cleaner"
        view.backgroundColor = BrowserTheme.background
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyDarkNavigationBar(to: navigationBar)
        }

        tableView.overrideUserInterfaceStyle = .dark
        tableView.backgroundColor = BrowserTheme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadData),
            name: .pageCleanerRulesChanged,
            object: nil
        )
        reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func reloadData() {
        sections = PageCleanerStore.shared.groupedByHost()
        tableView.reloadData()
        navigationItem.rightBarButtonItem = sections.isEmpty
            ? nil
            : UIBarButtonItem(title: "Clear All", style: .plain, target: self, action: #selector(clearAll))
    }

    @objc private func clearAll() {
        let alert = UIAlertController(
            title: "Clear all cleaner rules?",
            message: "Hidden elements will show again after pages reload.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            PageCleanerStore.shared.removeAll()
        })
        present(alert, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        max(sections.count, 1)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if sections.isEmpty { return 1 }
        return sections[section].rules.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if sections.isEmpty { return nil }
        return sections[section].host
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.selectionStyle = .none
        cell.accessoryType = .none

        if sections.isEmpty {
            cell.textLabel?.text = "No rules yet"
            cell.detailTextLabel?.text = "Tap the wand icon, then pick This site or This page"
            return cell
        }

        let rule = sections[indexPath.section].rules[indexPath.row]
        cell.textLabel?.text = rule.label
        if let urlString = rule.urlString {
            cell.detailTextLabel?.text = "This page · \(urlString)"
        } else {
            cell.detailTextLabel?.text = "Entire site · \(rule.selector)"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        !sections.isEmpty
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, !sections.isEmpty else { return }
        let rule = sections[indexPath.section].rules[indexPath.row]
        PageCleanerStore.shared.remove(id: rule.id)
    }
}
