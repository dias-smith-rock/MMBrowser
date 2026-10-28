import UIKit
import SnapKit
import SafariServices

final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable {
        case premium, privacyProtections, privacyData, privacyAccess, privacyLearn, accounts, tools, youtube, media, searchPrivacy, searchGeneral, home, about
    }

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
        tableView.reloadSections(
            IndexSet([Section.privacyProtections.rawValue, Section.about.rawValue]),
            with: .none
        )
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
        case .privacyProtections: return 6
        case .privacyData: return 4
        case .privacyAccess: return 3
        case .privacyLearn: return 2
        case .accounts: return 2
        case .tools: return 1
        case .youtube: return 2
        case .media: return 2
        case .searchPrivacy: return SearchEngine.privacyFriendly.count
        case .searchGeneral: return SearchEngine.general.count
        case .home: return 1
        case .about: return 7
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .premium: return "Premium"
        case .privacyProtections: return "Protections"
        case .privacyData: return "Data"
        case .privacyAccess: return "Access"
        case .privacyLearn: return "Learn more"
        case .accounts: return "Spaces"
        case .tools: return "Tools"
        case .youtube: return "Focus & Video"
        case .media: return "Media"
        case .searchPrivacy: return "Privacy-friendly"
        case .searchGeneral: return "General"
        case .home: return "Appearance"
        case .about: return "About"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .premium:
            return "Free includes \(PremiumStore.freeSpaceLimit) Spaces. Premium unlocks unlimited Spaces and Space Lock."
        case .privacyProtections:
            return "Filter lists can update when sites change. Protection is best-effort."
        case .privacyData:
            return "Cookies, cache, history, and bookmarks are stored per Space. Tabs in the same Space share that Space’s data. Auto-clear stays off so logins remain signed in."
        case .searchGeneral:
            return "Used for address-bar search."
        case .privacyAccess:
            return "Location Deny/Spoof only affects GPS-like browser APIs—not your network IP."
        case .accounts:
            return "Spaces keep separate cookies, history, bookmarks, Watch Later, Reading List, home shortcuts, and passwords. Downloaded files are Shared across Spaces."
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
            cell.detailTextLabel?.text = PremiumStore.shared.isPremiumActive ? "Active" : "Spaces & Space Lock"
            cell.accessoryType = .disclosureIndicator
        case .privacyProtections:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Recommended for privacy"
                cell.detailTextLabel?.text = "Checklist · does not wipe logins"
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Block Ads & Trackers"
                cell.detailTextLabel?.text = "Network ads, trackers, and page banners"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.trackerProtectionEnabled
                sw.addTarget(self, action: #selector(tpChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 2:
                cell.textLabel?.text = "Accurate Block Count"
                cell.detailTextLabel?.text = "Shield badge via page scan · uses more CPU"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.accurateBlockCountEnabled
                sw.isEnabled = AppSettings.trackerProtectionEnabled
                sw.addTarget(self, action: #selector(accurateBlockCountChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 3:
                cell.textLabel?.text = "HTTPS First"
                cell.detailTextLabel?.text = "Prefer secure connections"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.httpsOnly
                sw.addTarget(self, action: #selector(httpsChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 4:
                cell.textLabel?.text = "Global Privacy Control"
                cell.detailTextLabel?.text = "Sec-GPC opt-out signal"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.globalPrivacyControlEnabled
                sw.addTarget(self, action: #selector(gpcChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            default:
                cell.textLabel?.text = "Filter lists"
                cell.detailTextLabel?.text = FilterUpdateManager.shared.filterStatusLine
                cell.accessoryType = .disclosureIndicator
            }
        case .privacyData:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Block Images"
                cell.detailTextLabel?.text = "No-image mode for all tabs"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.noImagesEnabled
                sw.addTarget(self, action: #selector(noImagesChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 1:
                cell.textLabel?.text = "Aggressive Image Block"
                cell.detailTextLabel?.text = "Also scrub images inside iframes"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.aggressiveNoImagesEnabled
                sw.isEnabled = AppSettings.noImagesEnabled
                sw.addTarget(self, action: #selector(aggressiveNoImagesChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            case 2:
                cell.textLabel?.text = "Clear Option"
                cell.detailTextLabel?.text = AppSettings.clearOptionSummary
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Erase browsing data"
                cell.detailTextLabel?.text = "This Space or all Spaces"
                cell.accessoryType = .disclosureIndicator
            }
        case .privacyAccess:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Location"
                cell.detailTextLabel?.text = AppSettings.locationSummary
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "App Lock"
                cell.detailTextLabel?.text = AppLockSettings.isEnabled
                    ? "On · whole-app PIN / pattern"
                    : "Off · protect the whole app"
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Default browser"
                cell.detailTextLabel?.text = "Off — links may open in Safari"
                cell.accessoryType = .disclosureIndicator
            }
        case .privacyLearn:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Privacy Explained"
                cell.detailTextLabel?.text = "Private by default, Spaces, and limits"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "What we collect"
                cell.detailTextLabel?.text = "On-device data and diagnostics"
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
        case .tools:
            cell.textLabel?.text = "Web Editor"
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
                cell.detailTextLabel?.text = "Keep playing after leave / lock screen"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.backgroundAudioEnabled
                sw.addTarget(self, action: #selector(bgAudioChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            } else {
                cell.textLabel?.text = "Picture in Picture"
                cell.detailTextLabel?.text = "Floating system video window"
                cell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppSettings.pictureInPictureEnabled
                sw.addTarget(self, action: #selector(pipChanged(_:)), for: .valueChanged)
                cell.accessoryView = sw
            }
        case .searchPrivacy, .searchGeneral:
            let engines = indexPath.section == Section.searchPrivacy.rawValue
                ? SearchEngine.privacyFriendly
                : SearchEngine.general
            let engine = engines[indexPath.row]
            let recommended = engine.id == SearchEngine.duckDuckGo.id
            cell.textLabel?.text = recommended ? "\(engine.name) · Recommended" : engine.name
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
        case .privacyProtections:
            if indexPath.row == 0 {
                let recommended = PrivacyRecommendedViewController()
                recommended.onRequestRebuildWebViews = { [weak self] in
                    self?.onRequestRebuildWebViews?()
                }
                navigationController?.pushViewController(recommended, animated: true)
            } else if indexPath.row == 5 {
                presentFilterUpdateAlert()
            }
        case .privacyData:
            if indexPath.row == 2 {
                navigationController?.pushViewController(ClearOptionSettingsViewController(), animated: true)
            } else if indexPath.row == 3 {
                presentEraseBrowsingData()
            }
        case .privacyAccess:
            if indexPath.row == 0 {
                let location = LocationSettingsViewController()
                location.onChanged = { [weak self] in
                    self?.onRequestRebuildWebViews?()
                    self?.tableView.reloadData()
                }
                navigationController?.pushViewController(location, animated: true)
            } else if indexPath.row == 1 {
                navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
            } else {
                presentDefaultBrowserHelp()
            }
        case .privacyLearn:
            if indexPath.row == 0 {
                navigationController?.pushViewController(PrivacyInfoViewController(), animated: true)
            } else {
                navigationController?.pushViewController(WhatWeCollectViewController(), animated: true)
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
        case .tools:
            navigationController?.pushViewController(PageCleanerRulesViewController(), animated: true)
        case .searchPrivacy, .searchGeneral:
            let engines = indexPath.section == Section.searchPrivacy.rawValue
                ? SearchEngine.privacyFriendly
                : SearchEngine.general
            SearchEngineManager.setCurrent(engines[indexPath.row])
            tableView.reloadData()
        case .home:
            navigationController?.pushViewController(AppearanceSettingsViewController(), animated: true)
        case .about:
            switch indexPath.row {
            case 1:
                presentFilterUpdateAlert()
            case 2:
                let alert = UIAlertController(
                    title: "What's New",
                    message: "Private by default and isolated by Space. Ads and trackers are blocked, HTTPS First and Global Privacy Control are on, and each Space keeps its own cookies and logins. Not a VPN. YouTube video ads stay best-effort.",
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

    private func presentEraseBrowsingData() {
        guard let tabManager else { return }
        let tab = tabManager.selectedTab
        let container = tab.flatMap { tabManager.container(id: $0.containerID) } ?? tabManager.sortedContainers.first
        guard let container else { return }
        let erase = EraseBrowsingDataViewController(
            mode: .space(name: container.name, containerID: container.id, sessionID: container.sessionID),
            allSpaces: tabManager.sortedContainers.map { ($0.id, $0.sessionID) }
        )
        erase.onFinished = { [weak self] outcome in
            guard let self else { return }
            if case .erasedSpaces(let ids) = outcome {
                for containerID in ids {
                    let tabIDs = tabManager.normalTabs.filter { $0.containerID == containerID }.map(\.id)
                    tabIDs.forEach { tabManager.closeTab(id: $0) }
                    _ = tabManager.addTab(incognito: false, select: true, containerID: containerID)
                }
            }
            Toast.show("Browsing data erased", from: self)
            self.onRequestRebuildWebViews?()
        }
        let nav = UINavigationController(rootViewController: erase)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    private func presentDefaultBrowserHelp() {
        let alert = UIAlertController(
            title: "Default browser",
            message: "Off — links may open in Safari.\n\nSettings → Apps → XBrowser → Default Browser App → XBrowser",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open iPhone Settings", style: .default) { _ in
            if #available(iOS 18.3, *),
               let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString) {
                UIApplication.shared.open(url)
                return
            }
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }

    private func presentFilterUpdateAlert() {
        let alert = UIAlertController(
            title: "Filter lists",
            message: "\(FilterUpdateManager.shared.filterStatusLine)\n\nFilters block page ads and trackers. Protection is best-effort.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Update now", style: .default) { [weak self] _ in
            FilterUpdateManager.shared.refresh(force: true) { ok in
                self?.tableView.reloadData()
                if let self = self {
                    Toast.show(ok ? "Filters updated" : "Using cached / bundled filters", from: self)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
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
        tableView.reloadSections(IndexSet(integer: Section.privacyProtections.rawValue), with: .none)
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
        tableView.reloadSections(IndexSet(integer: Section.privacyData.rawValue), with: .none)
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

    @objc private func gpcChanged(_ sw: UISwitch) {
        AppSettings.globalPrivacyControlEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "global_privacy_control", enabled: sw.isOn)
        onRequestRebuildWebViews?()
        Toast.show(sw.isOn ? "Global Privacy Control on" : "Global Privacy Control off", from: self)
    }

    @objc private func close() { dismiss(animated: true) }
}
