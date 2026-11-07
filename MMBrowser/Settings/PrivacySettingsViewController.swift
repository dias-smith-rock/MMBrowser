import UIKit
import SnapKit

/// Privacy & Security hub: protections, data, access, and learn-more pages.
final class PrivacySettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable {
        case protections, data, access, learn
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    var onRequestRebuildWebViews: (() -> Void)?
    weak var tabManager: TabManager?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy & Security"
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
        tableView.reloadSections(IndexSet(integer: Section.protections.rawValue), with: .none)
    }

    @objc private func themeChanged() {
        applyChrome()
        tableView.reloadData()
    }

    private func applyChrome() {
        BrowserTheme.applyScreenChrome(to: self)
        tableView.backgroundColor = BrowserTheme.background
        tableView.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .protections: return 6
        case .data: return 4
        case .access: return DefaultBrowserFeature.isEnabled ? 3 : 2
        case .learn: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .protections: return "Protections"
        case .data: return "Data"
        case .access: return "Access"
        case .learn: return "Learn more"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .protections:
            return "Filter lists can update when sites change. Protection is best-effort."
        case .data:
            return "Cookies, cache, history, and bookmarks are stored per Space. Tabs in the same Space share that Space’s data. Cache, cookies, history, and local storage clear when you leave the app unless you turn them off in Clear Option."
        case .access:
            return "Location Deny/Spoof only affects GPS-like browser APIs—not your network IP."
        case .learn:
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
        let cell = dequeue(tableView)
        switch Section(rawValue: indexPath.section)! {
        case .protections:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Recommended for privacy"
                cell.detailTextLabel?.text = "Private-browser defaults"
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Block Ads & Trackers"
                cell.detailTextLabel?.text = "Network ads, trackers, and page banners"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.trackerProtectionEnabled, action: #selector(tpChanged(_:)))
            case 2:
                cell.textLabel?.text = "Accurate Block Count"
                cell.detailTextLabel?.text = "Shield badge via page scan · uses more CPU"
                cell.selectionStyle = .none
                let sw = makeSwitch(on: AppSettings.accurateBlockCountEnabled, action: #selector(accurateBlockCountChanged(_:)))
                sw.isEnabled = AppSettings.trackerProtectionEnabled
                cell.accessoryView = sw
            case 3:
                cell.textLabel?.text = "HTTPS First"
                cell.detailTextLabel?.text = "Prefer secure connections"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.httpsOnly, action: #selector(httpsChanged(_:)))
            case 4:
                cell.textLabel?.text = "Global Privacy Control"
                cell.detailTextLabel?.text = "Sec-GPC opt-out signal"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.globalPrivacyControlEnabled, action: #selector(gpcChanged(_:)))
            default:
                cell.textLabel?.text = "Filter lists"
                cell.detailTextLabel?.text = FilterUpdateManager.shared.filterStatusLine
                cell.accessoryType = .disclosureIndicator
            }
        case .data:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Block Images"
                cell.detailTextLabel?.text = "No-image mode for all tabs"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.noImagesEnabled, action: #selector(noImagesChanged(_:)))
            case 1:
                cell.textLabel?.text = "Aggressive Image Block"
                cell.detailTextLabel?.text = "Also scrub images inside iframes"
                cell.selectionStyle = .none
                let sw = makeSwitch(on: AppSettings.aggressiveNoImagesEnabled, action: #selector(aggressiveNoImagesChanged(_:)))
                sw.isEnabled = AppSettings.noImagesEnabled
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
        case .access:
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
        case .learn:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Privacy Explained"
                cell.detailTextLabel?.text = "Private by default, Spaces, and limits"
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "What we collect"
                cell.detailTextLabel?.text = "On-device data and diagnostics"
                cell.accessoryType = .disclosureIndicator
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .protections:
            if indexPath.row == 0 {
                let recommended = PrivacyRecommendedViewController()
                recommended.onRequestRebuildWebViews = { [weak self] in
                    self?.onRequestRebuildWebViews?()
                }
                navigationController?.pushViewController(recommended, animated: true)
            } else if indexPath.row == 5 {
                presentFilterUpdateAlert()
            }
        case .data:
            if indexPath.row == 2 {
                navigationController?.pushViewController(ClearOptionSettingsViewController(), animated: true)
            } else if indexPath.row == 3 {
                presentEraseBrowsingData()
            }
        case .access:
            if indexPath.row == 0 {
                let location = LocationSettingsViewController()
                location.onChanged = { [weak self] in
                    self?.onRequestRebuildWebViews?()
                    self?.tableView.reloadData()
                }
                navigationController?.pushViewController(location, animated: true)
            } else if indexPath.row == 1 {
                navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
            } else if DefaultBrowserFeature.isEnabled {
                presentDefaultBrowserHelp()
            }
        case .learn:
            if indexPath.row == 0 {
                navigationController?.pushViewController(PrivacyInfoViewController(), animated: true)
            } else {
                navigationController?.pushViewController(WhatWeCollectViewController(), animated: true)
            }
        }
    }

    // MARK: - Actions

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
                if let self {
                    Toast.show(ok ? "Filters updated" : "Using cached / bundled filters", from: self)
                }
            }
        })
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func tpChanged(_ sw: UISwitch) {
        AppSettings.trackerProtectionEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "tracker_protection", enabled: sw.isOn)
        if !sw.isOn, AppSettings.accurateBlockCountEnabled {
            AppSettings.accurateBlockCountEnabled = false
        }
        tableView.reloadSections(IndexSet(integer: Section.protections.rawValue), with: .none)
        Toast.show(sw.isOn ? "Ads & trackers blocked" : "Ads & trackers allowed", from: self)
    }

    @objc private func accurateBlockCountChanged(_ sw: UISwitch) {
        AppSettings.accurateBlockCountEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "accurate_block_count", enabled: sw.isOn)
        Toast.show(sw.isOn ? "Accurate block count on" : "Accurate block count off", from: self)
    }

    @objc private func noImagesChanged(_ sw: UISwitch) {
        AppSettings.noImagesEnabled = sw.isOn
        AppAnalytics.logSettingsToggle(setting: "no_images", enabled: sw.isOn)
        tableView.reloadSections(IndexSet(integer: Section.data.rawValue), with: .none)
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

    private func dequeue(_ tableView: UITableView) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }

    private func makeSwitch(on: Bool, action: Selector) -> UISwitch {
        let sw = UISwitch()
        sw.isOn = on
        sw.addTarget(self, action: action, for: .valueChanged)
        return sw
    }
}
