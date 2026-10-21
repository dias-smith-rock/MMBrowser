import UIKit
import SnapKit
import SafariServices

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case premium, privacy, accounts, clearOption, tools, youtube, media, search, home, about }

    private enum AboutLinks {
        static let privacy = URL(string: "https://xxxxxbrowser.cc/privacy.html")!
        static let terms = URL(string: "https://xxxxxbrowser.cc/terms.html")!
        static let rateUs = URL(string: "https://apps.apple.com/app/id6804914972?action=write-review")!
        static let contactUs = URL(string: "mailto:gaowei85714@gmail.com")!
    }

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
        case .premium: return 1
        case .privacy: return 9
        case .accounts: return 2
        case .clearOption: return 1
        case .tools: return 1
        case .youtube: return 2
        case .media: return 2
        case .search: return SearchEngine.all.count
        case .home: return 1
        case .about: return 7
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .premium: return "Premium"
        case .privacy: return "Privacy & Security"
        case .accounts: return "Spaces"
        case .clearOption: return "Clear Option"
        case .tools: return "Tools"
        case .youtube: return "Focus & Video"
        case .media: return "Media"
        case .search: return "Search Engine"
        case .home: return "Appearance"
        case .about: return "About"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .premium:
            return "Free includes \(PremiumStore.freeSpaceLimit) Spaces. Premium unlocks unlimited Spaces."
        case .privacy:
            return "Location Deny/Spoof only affects GPS-like browser APIs—not your network IP."
        case .accounts:
            return "Spaces keep separate cookies, history, bookmarks, home shortcuts, and passwords. Downloads and Reading List are Shared."
        case .clearOption:
            return "Auto-clear when you leave can wipe site data for every space. To remove one identity only, delete that space under Manage Spaces. History listed here is still recorded during the session unless History auto-clear is on."
        case .tools:
            return "Hide page elements and save rules for sites you visit often."
        case .youtube:
            return "Fewer YouTube interruptions is best-effort and may stop working when the site changes. Shorts Focus hides Shorts shelves and redirects Shorts links."
        case .media:
            return "Background audio keeps supported video sites playing when you leave the app. Picture in Picture requires system support."
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
        case .premium:
            cell.textLabel?.text = "XBrowser Premium"
            cell.detailTextLabel?.text = PremiumStore.shared.isPremiumActive ? "Active" : "Unlock unlimited Spaces"
            cell.accessoryType = .disclosureIndicator
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
            case 7:
                cell.textLabel?.text = "Ad Tracking"
                cell.detailTextLabel?.text = AdConsentManager.trackingAuthorizationSummary
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Privacy Explained"
                cell.accessoryType = .disclosureIndicator
            }
        case .accounts:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Spaces"
                cell.detailTextLabel?.text = "Separate logins and cookies"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Isolated vs Shared"
                cell.detailTextLabel?.text = "What stays per space"
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
            case 2:
                cell.textLabel?.text = "What's New"
                cell.accessoryType = .disclosureIndicator
            case 3:
                cell.textLabel?.text = "Privacy Policy"
                cell.accessoryType = .disclosureIndicator
            case 4:
                cell.textLabel?.text = "Terms of Use"
                cell.accessoryType = .disclosureIndicator
            case 5:
                cell.textLabel?.text = "Rate Us"
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Contact Us"
                cell.accessoryType = .disclosureIndicator
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .premium:
            PremiumCoordinator.presentPaywall(from: self, source: "settings")
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
                presentAdTrackingOptions()
            } else if indexPath.row == 8 {
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
        case .search:
            SearchEngineManager.setCurrent(SearchEngine.all[indexPath.row])
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
        case .home:
            navigationController?.pushViewController(AppearanceSettingsViewController(), animated: true)
        case .about:
            switch indexPath.row {
            case 1:
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
            case 2:
                let alert = UIAlertController(
                    title: "What's New",
                    message: "Spaces: separate logins with a switcher in the address bar, plus lock, clear, and tracker blocking. Webpage Cleaner, Reader Mode, Reading List, Downloads, and a home page you control.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            case 3:
                openLegalURL(AboutLinks.privacy)
            case 4:
                openLegalURL(AboutLinks.terms)
            case 5:
                UIApplication.shared.open(AboutLinks.rateUs)
            case 6:
                UIApplication.shared.open(AboutLinks.contactUs)
            default:
                break
            }
        default:
            break
        }
    }

    private func openLegalURL(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = BrowserTheme.chromeBlue
        present(safari, animated: true)
    }

    @objc private func tpChanged(_ sw: UISwitch) {
        AppSettings.trackerProtectionEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "tracker_protection", enabled: sw.isOn)
        if !sw.isOn, AppSettings.accurateBlockCountEnabled {
            AppSettings.accurateBlockCountEnabled = false
        }
        tableView.reloadSections(IndexSet(integer: Section.privacy.rawValue), with: .none)
        Toast.show(sw.isOn ? "Ads & trackers blocked" : "Ads & trackers allowed", from: self)
    }
    @objc private func accurateBlockCountChanged(_ sw: UISwitch) {
        AppSettings.accurateBlockCountEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "accurate_block_count", enabled: sw.isOn)
        Toast.show(sw.isOn ? "Accurate block count on" : "Accurate block count off", from: self)
    }
    @objc private func shortsChanged(_ sw: UISwitch) {
        AppSettings.hideShortsEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "hide_shorts", enabled: sw.isOn)
        Toast.show(sw.isOn ? "Shorts Focus on" : "Shorts Focus off", from: self)
    }
    @objc private func ytShieldChanged(_ sw: UISwitch) {
        AppSettings.youtubeAdShieldEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "youtube_ad_shield", enabled: sw.isOn)
        Toast.show(sw.isOn ? "YouTube video filter on" : "YouTube video filter off", from: self)
    }
    @objc private func bgAudioChanged(_ sw: UISwitch) {
        AppSettings.backgroundAudioEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "background_audio", enabled: sw.isOn)
        Toast.show(sw.isOn ? "Background audio on" : "Background audio off", from: self)
    }
    @objc private func pipChanged(_ sw: UISwitch) {
        AppSettings.pictureInPictureEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "picture_in_picture", enabled: sw.isOn)
        Toast.show(sw.isOn ? "Picture in Picture on" : "Picture in Picture off", from: self)
    }
    @objc private func noImagesChanged(_ sw: UISwitch) {
        AppSettings.noImagesEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "no_images", enabled: sw.isOn)
        tableView.reloadSections(IndexSet(integer: Section.privacy.rawValue), with: .none)
        Toast.show(sw.isOn ? "Block images on" : "Block images off", from: self)
    }
    @objc private func aggressiveNoImagesChanged(_ sw: UISwitch) {
        AppSettings.aggressiveNoImagesEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "aggressive_no_images", enabled: sw.isOn)
        Toast.show(sw.isOn ? "Aggressive image block on" : "Aggressive image block off", from: self)
    }
    @objc private func httpsChanged(_ sw: UISwitch) {
        AppSettings.httpsOnly = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "https_only", enabled: sw.isOn)
    }

    private func presentAdTrackingOptions() {
        if AdConsentManager.isPrivacyOptionsRequired {
            Task { @MainActor in
                do {
                    try await AdConsentManager.presentPrivacyOptions(from: self)
                    tableView.reloadData()
                } catch {
                    Toast.show("Couldn’t open ad privacy options", from: self)
                }
            }
            return
        }

        let alert = UIAlertController(
            title: "Ad Tracking",
            message: "XBrowser shows ads and may track your activity across other companies’ apps and websites to personalize and measure ads.\n\nCurrent status: \(AdConsentManager.trackingAuthorizationSummary).\n\nYou can change this in iOS Settings → Privacy & Security → Tracking.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Open iOS Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}
