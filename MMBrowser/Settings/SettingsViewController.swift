import UIKit
import SnapKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case privacy, youtube, media, search, home, about }
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

        NotificationCenter.default.addObserver(self, selector: #selector(filterStatusChanged), name: .filterStatusChanged, object: nil)
    }

    @objc private func filterStatusChanged() {
        tableView.reloadSections(IndexSet(integer: Section.about.rawValue), with: .none)
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .privacy: return 7
        case .youtube: return 2
        case .media: return 2
        case .search: return SearchEngine.all.count
        case .home: return 4
        case .about: return 3
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .privacy: return "Privacy & Security"
        case .youtube: return "Focus & Video"
        case .media: return "Media"
        case .search: return "Search Engine"
        case .home: return "Home Page"
        case .about: return "About"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .youtube:
            return "Fewer YouTube interruptions is best-effort and may stop working when the site changes. Shorts Focus hides Shorts shelves and redirects Shorts links."
        case .media:
            return "Background audio keeps supported video sites playing when you leave the app. Picture in Picture requires system support."
        default:
            return nil
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
                cell.textLabel?.text = "Block Ads & Trackers"
                cell.detailTextLabel?.text = "Network ads, trackers, and page banners"
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
                cell.textLabel?.text = "App Lock"
                cell.detailTextLabel?.text = AppLockSettings.isEnabled ? "On" : "Off"
                cell.accessoryType = .disclosureIndicator
            case 4:
                cell.textLabel?.text = "Webpage Cleaner"
                cell.detailTextLabel?.text = "Manage hidden element rules"
                cell.accessoryType = .disclosureIndicator
            case 5:
                cell.textLabel?.text = "Clear Browsing Data"
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Privacy Explained"
                cell.accessoryType = .disclosureIndicator
            }
        case .youtube:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Hide Shorts"
                cell.detailTextLabel?.text = "Focus Mode — hide shelves and redirect Shorts"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.hideShortsEnabled
                sw.addTarget(self, action: #selector(shortsChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "Fewer YouTube Video Ads"
                cell.detailTextLabel?.text = "Experimental · best-effort"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.youtubeAdShieldEnabled
                sw.addTarget(self, action: #selector(ytShieldChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            }
        case .media:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Background Audio"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.backgroundAudioEnabled
                sw.addTarget(self, action: #selector(bgAudioChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "Picture in Picture"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.pictureInPictureEnabled
                sw.addTarget(self, action: #selector(pipChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
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
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "MMBrowser 1.0"
                cell.selectionStyle = .none
            case 1:
                cell.textLabel?.text = "Filters"
                cell.detailTextLabel?.text = FilterUpdateManager.shared.statusSummary
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "What's New"
                cell.accessoryType = .disclosureIndicator
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .privacy:
            if indexPath.row == 3 {
                navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
            } else if indexPath.row == 4 {
                navigationController?.pushViewController(PageCleanerRulesViewController(), animated: true)
            } else if indexPath.row == 5 {
                navigationController?.pushViewController(ClearBrowsingDataViewController(), animated: true)
            } else if indexPath.row == 6 {
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
                let alert = UIAlertController(
                    title: "Filters",
                    message: "Status: \(FilterUpdateManager.shared.statusSummary)\n\nFilters block page ads and trackers. YouTube video filters are updated when available so the app can recover after site changes.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Check for Updates", style: .default) { [weak self] _ in
                    FilterUpdateManager.shared.refresh(force: true) { ok in
                        self?.tableView.reloadSections(IndexSet(integer: Section.about.rawValue), with: .none)
                        if let self = self {
                            Toast.show(ok ? "Filters updated" : "Using cached / bundled filters", from: self)
                        }
                        self?.onRequestRebuildWebViews?()
                    }
                })
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                present(alert, animated: true)
            } else if indexPath.row == 2 {
                let alert = UIAlertController(
                    title: "What's New",
                    message: "Block Ads & Trackers, Focus Mode (hide Shorts), fewer YouTube interruptions (best-effort), background audio & Picture in Picture, Reader Mode, Reading List, Downloads, and a home page you control.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        default:
            break
        }
    }

    @objc private func tpChanged(_ sw: UISwitch) {
        AppSettings.trackerProtectionEnabled = sw.isOn
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Ads & trackers blocked" : "Ads & trackers allowed", from: self)
    }
    @objc private func shortsChanged(_ sw: UISwitch) {
        AppSettings.hideShortsEnabled = sw.isOn
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Shorts Focus on" : "Shorts Focus off", from: self)
    }
    @objc private func ytShieldChanged(_ sw: UISwitch) {
        AppSettings.youtubeAdShieldEnabled = sw.isOn
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "YouTube video filter on" : "YouTube video filter off", from: self)
    }
    @objc private func bgAudioChanged(_ sw: UISwitch) {
        AppSettings.backgroundAudioEnabled = sw.isOn
        MediaPlaybackSupport.configureAudioSessionIfNeeded()
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Background audio on" : "Background audio off", from: self)
    }
    @objc private func pipChanged(_ sw: UISwitch) {
        AppSettings.pictureInPictureEnabled = sw.isOn
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Picture in Picture on" : "Picture in Picture off", from: self)
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
