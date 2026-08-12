import UIKit
import SnapKit

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case privacy, accounts, clearOption, tools, youtube, media, downloads, gestures, search, home, about }
    var onRequestRebuildWebViews: (() -> Void)?
    var onAccountsChanged: (() -> Void)?
    weak var tabManager: TabManager?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(close))
        applyChrome()

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        NotificationCenter.default.addObserver(self, selector: #selector(filterStatusChanged), name: .filterStatusChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
        tableView.reloadData()
    }

    @objc private func filterStatusChanged() {
        tableView.reloadSections(IndexSet(integer: Section.about.rawValue), with: .none)
    }

    @objc private func themeChanged() {
        applyChrome()
        tableView.reloadData()
    }

    private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        tableView.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .privacy: return 8
        case .accounts: return 2
        case .clearOption: return 1
        case .tools: return 1
        case .youtube: return 2
        case .media: return 2
        case .downloads: return 1
        case .gestures: return 1
        case .search: return SearchEngine.all.count
        case .home: return 1
        case .about: return 3
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .privacy: return "Privacy & Security"
        case .accounts: return "Accounts"
        case .clearOption: return "Clear Option"
        case .tools: return "Tools"
        case .youtube: return "Focus & Video"
        case .media: return "Media"
        case .downloads: return "Downloads"
        case .gestures: return "Gestures"
        case .search: return "Search Engine"
        case .home: return "Appearance"
        case .about: return "About"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .privacy:
            return "Location Deny/Spoof only affects GPS-like browser APIs—not your network IP."
        case .accounts:
            return "Accounts keep separate cookies, history, bookmarks, home shortcuts, and passwords. Downloads and Reading List are Shared."
        case .clearOption:
            return "Auto-clear when you leave can wipe site data for every account. To remove one identity only, delete that account under Manage Accounts. History listed here is still recorded during the session unless History auto-clear is on."
        case .tools:
            return "Hide page elements and save rules for sites you visit often."
        case .youtube:
            return "Fewer YouTube interruptions is best-effort and may stop working when the site changes. Shorts Focus hides Shorts shelves and redirects Shorts links."
        case .media:
            return "Background audio keeps supported video sites playing when you leave the app. Picture in Picture requires system support."
        case .downloads:
            return "Get a notification when a download finishes or fails while the app is in the background."
        case .gestures:
            return "One-finger Hook → back, Hook ← forward, Hook ○ bookmark."
        default:
            return nil
        }
    }

    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
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
                cell.textLabel?.text = "Accurate Block Count"
                cell.detailTextLabel?.text = "Shield badge via page scan · uses more CPU"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.accurateBlockCountEnabled
                sw.isEnabled = AppSettings.trackerProtectionEnabled
                sw.addTarget(self, action: #selector(accurateBlockCountChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 2:
                cell.textLabel?.text = "Block Images"
                cell.detailTextLabel?.text = "No-image mode for all tabs"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.noImagesEnabled
                sw.addTarget(self, action: #selector(noImagesChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 3:
                cell.textLabel?.text = "Aggressive Image Block"
                cell.detailTextLabel?.text = "Also scrub images inside iframes"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.aggressiveNoImagesEnabled
                sw.isEnabled = AppSettings.noImagesEnabled
                sw.addTarget(self, action: #selector(aggressiveNoImagesChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 4:
                cell.textLabel?.text = "HTTPS First"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.httpsOnly
                sw.addTarget(self, action: #selector(httpsChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 5:
                cell.textLabel?.text = "Location"
                cell.detailTextLabel?.text = AppSettings.locationSummary
                cell.accessoryType = .disclosureIndicator
            case 6:
                cell.textLabel?.text = "App Lock"
                cell.detailTextLabel?.text = AppLockSettings.isEnabled ? "On" : "Off"
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Privacy Explained"
                cell.accessoryType = .disclosureIndicator
            }
        case .accounts:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Accounts"
                cell.detailTextLabel?.text = "Separate logins and cookies"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Isolated vs Shared"
                cell.detailTextLabel?.text = "What stays per account"
                cell.accessoryType = .disclosureIndicator
            }
        case .clearOption:
            cell.textLabel?.text = "Clear Option"
            cell.detailTextLabel?.text = AppSettings.clearOptionSummary
            cell.accessoryType = .disclosureIndicator
        case .tools:
            cell.textLabel?.text = "Webpage Cleaner"
            cell.detailTextLabel?.text = "Manage hidden element rules"
            cell.accessoryType = .disclosureIndicator
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
        case .downloads:
            cell.textLabel?.text = "Completion Alerts"
            cell.detailTextLabel?.text = "Notify when downloads finish"
            cell.selectionStyle = .none
            let sw = UISwitch()
            sw.isOn = AppSettings.downloadCompletionNotificationsEnabled
            sw.addTarget(self, action: #selector(downloadNotifyChanged(_:)), for: .valueChanged)
            cell.accessoryView = sw
        case .gestures:
            cell.textLabel?.text = "Gestures"
            cell.detailTextLabel?.text = GestureActionMap.summary
            cell.accessoryType = .disclosureIndicator
        case .search:
            let engine = SearchEngine.all[indexPath.row]
            cell.textLabel?.text = engine.name
            cell.accessoryType = engine.id == AppSettings.searchEngineID ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .home:
            cell.textLabel?.text = "Appearance"
            cell.detailTextLabel?.text = ThemeManager.shared.current.name
            cell.accessoryType = .disclosureIndicator
        case .about:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "XBrowser 1.0"
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
            if indexPath.row == 5 {
                let location = LocationSettingsViewController()
                location.onChanged = { [weak self] in
                    self?.onRequestRebuildWebViews?()
                    self?.tableView.reloadData()
                }
                navigationController?.pushViewController(location, animated: true)
            } else if indexPath.row == 6 {
                navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
            } else if indexPath.row == 7 {
                navigationController?.pushViewController(PrivacyInfoViewController(), animated: true)
            }
        case .accounts:
            if indexPath.row == 1 {
                navigationController?.pushViewController(IsolatedVsSharedViewController(), animated: true)
                return
            }
            guard let tabManager else { return }
            let manage = ContainerManageViewController(tabManager: tabManager)
            manage.showsDoneButton = false
            manage.onChanged = { [weak self] in
                self?.onAccountsChanged?()
            }
            navigationController?.pushViewController(manage, animated: true)
        case .clearOption:
            navigationController?.pushViewController(ClearOptionSettingsViewController(), animated: true)
        case .tools:
            navigationController?.pushViewController(PageCleanerRulesViewController(), animated: true)
        case .gestures:
            navigationController?.pushViewController(GestureSettingsViewController(), animated: true)
        case .search:
            SearchEngineManager.setCurrent(SearchEngine.all[indexPath.row])
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        case .home:
            navigationController?.pushViewController(AppearanceSettingsViewController(), animated: true)
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
                        // Content-rule hot refresh is driven by `.filterManifestUpdated`.
                    }
                })
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                present(alert, animated: true)
            } else if indexPath.row == 2 {
                let alert = UIAlertController(
                    title: "What's New",
                    message: "Accounts: separate logins with a switcher in the address bar, plus lock, clear, and tracker blocking. Webpage Cleaner, Reader Mode, Reading List, Downloads, and a home page you control.",
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
        if !sw.isOn, AppSettings.accurateBlockCountEnabled {
            AppSettings.accurateBlockCountEnabled = false
        }
        tableView.reloadSections(IndexSet(integer: Section.privacy.rawValue), with: .none)
        Toast.show(sw.isOn ? "Ads & trackers blocked" : "Ads & trackers allowed", from: self)
    }
    @objc private func accurateBlockCountChanged(_ sw: UISwitch) {
        AppSettings.accurateBlockCountEnabled = sw.isOn
        Toast.show(sw.isOn ? "Accurate block count on" : "Accurate block count off", from: self)
    }
    @objc private func shortsChanged(_ sw: UISwitch) {
        AppSettings.hideShortsEnabled = sw.isOn
        Toast.show(sw.isOn ? "Shorts Focus on" : "Shorts Focus off", from: self)
    }
    @objc private func ytShieldChanged(_ sw: UISwitch) {
        AppSettings.youtubeAdShieldEnabled = sw.isOn
        Toast.show(sw.isOn ? "YouTube video filter on" : "YouTube video filter off", from: self)
    }
    @objc private func bgAudioChanged(_ sw: UISwitch) {
        AppSettings.backgroundAudioEnabled = sw.isOn
        MediaPlaybackSupport.configureAudioSessionIfNeeded()
        Toast.show(sw.isOn ? "Background audio on" : "Background audio off", from: self)
    }
    @objc private func pipChanged(_ sw: UISwitch) {
        AppSettings.pictureInPictureEnabled = sw.isOn
        Toast.show(sw.isOn ? "Picture in Picture on" : "Picture in Picture off", from: self)
    }
    @objc private func downloadNotifyChanged(_ sw: UISwitch) {
        AppSettings.downloadCompletionNotificationsEnabled = sw.isOn
        if sw.isOn {
            DownloadLocalNotifications.shared.requestAuthorizationIfNeeded { [weak self] granted in
                guard let self else { return }
                if granted {
                    Toast.show("Download alerts on", from: self)
                } else {
                    Toast.show("Allow notifications in Settings to get alerts", from: self)
                }
            }
        } else {
            Toast.show("Download alerts off", from: self)
        }
    }
    @objc private func noImagesChanged(_ sw: UISwitch) {
        AppSettings.noImagesEnabled = sw.isOn
        tableView.reloadSections(IndexSet(integer: Section.privacy.rawValue), with: .none)
        Toast.show(sw.isOn ? "Block images on" : "Block images off", from: self)
    }
    @objc private func aggressiveNoImagesChanged(_ sw: UISwitch) {
        AppSettings.aggressiveNoImagesEnabled = sw.isOn
        Toast.show(sw.isOn ? "Aggressive image block on" : "Aggressive image block off", from: self)
    }
    @objc private func httpsChanged(_ sw: UISwitch) { AppSettings.httpsOnly = sw.isOn }
    @objc private func close() { dismiss(animated: true) }
}
