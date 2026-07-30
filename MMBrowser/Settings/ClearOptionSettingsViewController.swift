import UIKit
import SnapKit

/// Settings → Clear Option: toggles for auto-clearing cache / cookies / history / local storage.
final class ClearOptionSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Row: Int, CaseIterable {
        case cache, cookies, history, localStorage

        var title: String {
            switch self {
            case .cache: return "Cache"
            case .cookies: return "Cookies"
            case .history: return "History"
            case .localStorage: return "Local Storage"
            }
        }

        var detail: String {
            switch self {
            case .cache: return "Disk and memory caches"
            case .cookies: return "Website cookies"
            case .history: return "Browsing history list"
            case .localStorage: return "Local / session / IndexedDB storage"
            }
        }

        var isOn: Bool {
            get {
                switch self {
                case .cache: return AppSettings.autoClearCache
                case .cookies: return AppSettings.autoClearCookies
                case .history: return AppSettings.autoClearHistory
                case .localStorage: return AppSettings.autoClearLocalStorage
                }
            }
            set {
                switch self {
                case .cache: AppSettings.autoClearCache = newValue
                case .cookies: AppSettings.autoClearCookies = newValue
                case .history: AppSettings.autoClearHistory = newValue
                case .localStorage: AppSettings.autoClearLocalStorage = newValue
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Clear Option"
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
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { Row.allCases.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Auto-Clear on Exit"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "When enabled, selected data is removed when you leave the app, and again on next launch (covers crash or force quit). History is only kept (and shown in the menu) when History auto-clear is off."
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.selectionStyle = .none
        let row = Row.allCases[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.detail
        let sw = UISwitch()
        sw.tag = row.rawValue
        sw.isOn = row.isOn
        sw.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        cell.accessoryView = sw
        return cell
    }

    @objc private func switchChanged(_ sw: UISwitch) {
        guard let row = Row(rawValue: sw.tag) else { return }
        row.isOn = sw.isOn
        guard sw.isOn else { return }
        switch row {
        case .cache:
            AutoClearManager.clearNow(cache: true)
        case .cookies:
            AutoClearManager.clearNow(cookies: true)
        case .history:
            AutoClearManager.clearNow(history: true)
            Toast.show("History cleared", from: self)
        case .localStorage:
            AutoClearManager.clearNow(localStorage: true)
        }
    }
}
