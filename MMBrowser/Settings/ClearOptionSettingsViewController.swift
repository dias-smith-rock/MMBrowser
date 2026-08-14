import UIKit
import SnapKit

/// Settings → Clear Option: auto-clear data + session/tab behavior.
final class ClearOptionSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Section: Int, CaseIterable { case autoClear, session }

    private enum AutoClearRow: Int, CaseIterable {
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
            case .cookies: return "Website cookies (turning on signs you out)"
            case .history: return "Cleared when you leave the app"
            case .localStorage: return "Site storage / IndexedDB (needed for many logins)"
            }
        }

        var isOn: Bool {
            switch self {
            case .cache: return AppSettings.autoClearCache
            case .cookies: return AppSettings.autoClearCookies
            case .history: return AppSettings.autoClearHistory
            case .localStorage: return AppSettings.autoClearLocalStorage
            }
        }

        func setOn(_ value: Bool) {
            switch self {
            case .cache: AppSettings.autoClearCache = value
            case .cookies: AppSettings.autoClearCookies = value
            case .history: AppSettings.autoClearHistory = value
            case .localStorage: AppSettings.autoClearLocalStorage = value
            }
        }
    }

    private enum SessionRow: Int, CaseIterable {
        case closeAllTabsOnExit, showTabsPreviewImages

        var title: String {
            switch self {
            case .closeAllTabsOnExit: return "Close All Tabs on Exit"
            case .showTabsPreviewImages: return "Show Tabs Preview Images"
            }
        }

        var detail: String {
            switch self {
            case .closeAllTabsOnExit: return "Leave one fresh New Tab when you leave the app"
            case .showTabsPreviewImages: return "Thumbnails on the tab switcher"
            }
        }

        var isOn: Bool {
            switch self {
            case .closeAllTabsOnExit: return AppSettings.closeAllTabsOnExit
            case .showTabsPreviewImages: return AppSettings.showTabsPreviewImages
            }
        }

        func setOn(_ value: Bool) {
            switch self {
            case .closeAllTabsOnExit: AppSettings.closeAllTabsOnExit = value
            case .showTabsPreviewImages: AppSettings.showTabsPreviewImages = value
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Clear Option"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .autoClear: return AutoClearRow.allCases.count
        case .session: return SessionRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .autoClear: return "Auto-Clear on Exit"
        case .session: return "Session"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .autoClear:
            return "Only selected items are removed when you leave the app. Cache, Cookies, History, and Local Storage all default off so browsing sessions stay intact. Enabling Cookies or Local Storage will clear them for every account immediately."
        case .session:
            return "Close All Tabs on Exit resets to a single New Tab when you background the app. Turn off preview images to hide webpage thumbnails in the tab switcher."
        }
    }

    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        BrowserTheme.styleListCell(cell)
        cell.selectionStyle = .none
        let sw = UISwitch()
        switch Section(rawValue: indexPath.section)! {
        case .autoClear:
            let row = AutoClearRow.allCases[indexPath.row]
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.detail
            sw.tag = 100 + row.rawValue
            sw.isOn = row.isOn
            sw.addTarget(self, action: #selector(autoClearChanged(_:)), for: .valueChanged)
        case .session:
            let row = SessionRow.allCases[indexPath.row]
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = row.detail
            sw.tag = 200 + row.rawValue
            sw.isOn = row.isOn
            sw.addTarget(self, action: #selector(sessionChanged(_:)), for: .valueChanged)
        }
        cell.accessoryView = sw
        return cell
    }

    @objc private func autoClearChanged(_ sw: UISwitch) {
        guard let row = AutoClearRow(rawValue: sw.tag - 100) else { return }
        if sw.isOn, row == .cookies || row == .localStorage {
            confirmEnableLoginWipingClear(row: row, switch: sw)
            return
        }
        row.setOn(sw.isOn)
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

    private func confirmEnableLoginWipingClear(row: AutoClearRow, switch sw: UISwitch) {
        let title = row == .cookies ? "Clear Cookies on Exit?" : "Clear Site Storage on Exit?"
        let message = row == .cookies
            ? "This signs you out of websites in every account now, and again each time you leave the app."
            : "This removes local site data (including many login sessions) for every account now, and again each time you leave the app."
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            sw.setOn(false, animated: true)
        })
        alert.addAction(UIAlertAction(title: "Enable & Clear", style: .destructive) { [weak self] _ in
            guard let self else { return }
            row.setOn(true)
            if row == .cookies {
                AutoClearManager.clearNow(cookies: true)
            } else {
                AutoClearManager.clearNow(localStorage: true)
            }
            Toast.show(row == .cookies ? "Cookies cleared" : "Site storage cleared", from: self)
        })
        present(alert, animated: true)
    }

    @objc private func sessionChanged(_ sw: UISwitch) {
        guard let row = SessionRow(rawValue: sw.tag - 200) else { return }
        row.setOn(sw.isOn)
        if row == .showTabsPreviewImages, !sw.isOn {
            Toast.show("Tab previews off", from: self)
        }
    }
}
