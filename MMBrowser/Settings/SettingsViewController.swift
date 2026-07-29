import UIKit
import SnapKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case privacy, search, home, about }
    var onRequestRebuildWebViews: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = BrowserTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
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
        case .privacy: return 6
        case .search: return SearchEngine.all.count
        case .home: return 4
        case .about: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .privacy: return "Privacy & Security"
        case .search: return "Search Engine"
        case .home: return "Home Page"
        case .about: return "About"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .privacy:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Tracker Protection"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.trackerProtectionEnabled
                sw.addTarget(self, action: #selector(tpChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 1:
                cell.textLabel?.text = "Block Images"
                cell.detailTextLabel?.text = "No-image mode for all tabs"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.noImagesEnabled
                sw.addTarget(self, action: #selector(noImagesChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 2:
                cell.textLabel?.text = "HTTPS First"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.httpsOnly
                sw.addTarget(self, action: #selector(httpsChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 3:
                cell.textLabel?.text = "Webpage Cleaner"
                cell.detailTextLabel?.text = "Manage hidden element rules"
                cell.accessoryType = .disclosureIndicator
            case 4:
                cell.textLabel?.text = "Clear Browsing Data"
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Privacy Explained"
                cell.accessoryType = .disclosureIndicator
            }
        case .search:
            let engine = SearchEngine.all[indexPath.row]
            cell.textLabel?.text = engine.name
            cell.accessoryType = engine.id == AppSettings.searchEngineID ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .home:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Show Shortcuts"
                let sw = UISwitch(); sw.isOn = AppSettings.showShortcuts
                sw.addTarget(self, action: #selector(shortcutsChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw; cell.selectionStyle = .none
            case 1:
                cell.textLabel?.text = "Show Continue"
                let sw = UISwitch(); sw.isOn = AppSettings.showContinue
                sw.addTarget(self, action: #selector(continueChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw; cell.selectionStyle = .none
            case 2:
                cell.textLabel?.text = "Show Discover"
                let sw = UISwitch(); sw.isOn = AppSettings.showDiscover
                sw.addTarget(self, action: #selector(discoverChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw; cell.selectionStyle = .none
            default:
                cell.textLabel?.text = "Wallpaper"
                cell.detailTextLabel?.text = ["Default", "Deep Blue", "Forest", "Midnight"][AppSettings.homeWallpaperIndex % 4]
                cell.accessoryType = .disclosureIndicator
            }
        case .about:
            cell.textLabel?.text = indexPath.row == 0 ? "MMBrowser 1.0" : "What's New"
            cell.selectionStyle = indexPath.row == 0 ? .none : .default
            if indexPath.row == 1 { cell.accessoryType = .disclosureIndicator }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .privacy:
            if indexPath.row == 3 {
                navigationController?.pushViewController(PageCleanerRulesViewController(), animated: true)
            } else if indexPath.row == 4 {
                navigationController?.pushViewController(ClearBrowsingDataViewController(), animated: true)
            } else if indexPath.row == 5 {
                navigationController?.pushViewController(PrivacyInfoViewController(), animated: true)
            }
        case .search:
            SearchEngineManager.setCurrent(SearchEngine.all[indexPath.row])
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        case .home:
            if indexPath.row == 3 {
                AppSettings.homeWallpaperIndex = (AppSettings.homeWallpaperIndex + 1) % 4
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        case .about:
            if indexPath.row == 1 {
                let alert = UIAlertController(title: "What's New", message: "Tracker protection, Reader Mode, Reading List, Downloads, custom search engines, tab search & groups, branded home.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func tpChanged(_ sw: UISwitch) {
        AppSettings.trackerProtectionEnabled = sw.isOn
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Tracker protection on" : "Tracker protection off", from: self)
    }
    @objc private func noImagesChanged(_ sw: UISwitch) {
        AppSettings.noImagesEnabled = sw.isOn
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Block images on" : "Block images off", from: self)
    }
    @objc private func httpsChanged(_ sw: UISwitch) { AppSettings.httpsOnly = sw.isOn }
    @objc private func shortcutsChanged(_ sw: UISwitch) { AppSettings.showShortcuts = sw.isOn }
    @objc private func continueChanged(_ sw: UISwitch) { AppSettings.showContinue = sw.isOn }
    @objc private func discoverChanged(_ sw: UISwitch) { AppSettings.showDiscover = sw.isOn }
    @objc private func close() { dismiss(animated: true) }
}
