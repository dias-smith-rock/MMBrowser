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
            get {
                switch self {
                case .closeAllTabsOnExit: return AppSettings.closeAllTabsOnExit
                case .showTabsPreviewImages: return AppSettings.showTabsPreviewImages
                }
            }
            set {
                switch self {
                case .closeAllTabsOnExit: AppSettings.closeAllTabsOnExit = newValue
                case .showTabsPreviewImages: AppSettings.showTabsPreviewImages = newValue
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
            return "When enabled, selected data is removed when you leave the app, and again on next launch (covers crash or force quit). History is only kept (and shown in the menu) when History auto-clear is off."
        case .session:
            return "Close All Tabs on Exit resets to a single New Tab when you background the app. Turn off preview images to hide webpage thumbnails in the tab switcher."
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
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
        guard var row = AutoClearRow(rawValue: sw.tag - 100) else { return }
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

    @objc private func sessionChanged(_ sw: UISwitch) {
        guard var row = SessionRow(rawValue: sw.tag - 200) else { return }
        row.isOn = sw.isOn
        if row == .showTabsPreviewImages, !sw.isOn {
            Toast.show("Tab previews off", from: self)
        }
    }
}
