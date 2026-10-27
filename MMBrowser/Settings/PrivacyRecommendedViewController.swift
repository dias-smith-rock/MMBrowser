import UIKit
import SnapKit

/// Checklist of private-friendly defaults. Does not wipe logins or turn on Clear Option.
final class PrivacyRecommendedViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onRequestRebuildWebViews: (() -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Row: Int, CaseIterable {
        case trackers
        case https
        case gpc
        case youtube
        case clearNote
        case appLock
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recommended for privacy"
        BrowserTheme.applyScreenChrome(to: self)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Row.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "These match a private-browser default. Clear Option stays off so site logins are not wiped when you leave the app."
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .none
        switch Row(rawValue: indexPath.row)! {
        case .trackers:
            cell.textLabel?.text = "Block Ads & Trackers"
            cell.detailTextLabel?.text = "On by default"
            cell.accessoryView = makeSwitch(on: AppSettings.trackerProtectionEnabled, action: #selector(tpChanged(_:)))
        case .https:
            cell.textLabel?.text = "HTTPS First"
            cell.detailTextLabel?.text = "Prefer secure connections"
            cell.accessoryView = makeSwitch(on: AppSettings.httpsOnly, action: #selector(httpsChanged(_:)))
        case .gpc:
            cell.textLabel?.text = "Global Privacy Control"
            cell.detailTextLabel?.text = "Tell sites you opt out of sale or sharing"
            cell.accessoryView = makeSwitch(on: AppSettings.globalPrivacyControlEnabled, action: #selector(gpcChanged(_:)))
        case .youtube:
            cell.textLabel?.text = "Fewer YouTube Video Ads"
            cell.detailTextLabel?.text = "Best-effort · may change with the site"
            cell.accessoryView = makeSwitch(on: AppSettings.youtubeAdShieldEnabled, action: #selector(ytChanged(_:)))
        case .clearNote:
            cell.textLabel?.text = "Clear Option"
            cell.detailTextLabel?.text = "Stays off so logins stay signed in. Choose what to wipe—nothing is cleared from this list."
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        case .appLock:
            cell.textLabel?.text = "App Lock"
            cell.detailTextLabel?.text = AppLockSettings.isEnabled ? "On" : "Set a PIN or pattern in Settings"
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        switch row {
        case .appLock:
            navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
        case .clearNote:
            navigationController?.pushViewController(ClearOptionSettingsViewController(), animated: true)
        default:
            break
        }
    }

    private func makeSwitch(on: Bool, action: Selector) -> UISwitch {
        let sw = UISwitch()
        sw.isOn = on
        sw.addTarget(self, action: action, for: .valueChanged)
        return sw
    }

    @objc private func tpChanged(_ sw: UISwitch) {
        AppSettings.trackerProtectionEnabled = sw.isOn
        if !sw.isOn, AppSettings.accurateBlockCountEnabled {
            AppSettings.accurateBlockCountEnabled = false
        }
        onRequestRebuildWebViews?()
    }

    @objc private func httpsChanged(_ sw: UISwitch) {
        AppSettings.httpsOnly = sw.isOn
    }

    @objc private func gpcChanged(_ sw: UISwitch) {
        AppSettings.globalPrivacyControlEnabled = sw.isOn
        onRequestRebuildWebViews?()
    }

    @objc private func ytChanged(_ sw: UISwitch) {
        AppSettings.youtubeAdShieldEnabled = sw.isOn
    }
}
