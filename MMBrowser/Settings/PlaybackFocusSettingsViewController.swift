import UIKit
import SnapKit

/// Playback & Focus hub: Shorts, YouTube ads, background audio, PiP.
final class PlaybackFocusSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable {
        case focus, media
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Playback & Focus"
        applyChrome()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
        tableView.reloadData()
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
        case .focus: return 2
        case .media: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .focus: return "Focus & Video"
        case .media: return "Media"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .focus:
            return "Fewer YouTube interruptions is best-effort and may stop working when the site changes. Shorts Focus hides Shorts shelves and redirects Shorts links."
        case .media:
            return "Background audio keeps supported video sites playing when you leave the app. Picture in Picture requires system support."
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
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
        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .focus:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Hide Shorts"
                cell.detailTextLabel?.text = "Focus Mode — hide shelves and redirect Shorts"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.hideShortsEnabled, action: #selector(shortsChanged(_:)))
            } else {
                cell.textLabel?.text = "Fewer YouTube Video Ads"
                cell.detailTextLabel?.text = "Experimental · best-effort"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.youtubeAdShieldEnabled, action: #selector(ytShieldChanged(_:)))
            }
        case .media:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Background Audio"
                cell.detailTextLabel?.text = "Keep playing after leave / lock screen"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.backgroundAudioEnabled, action: #selector(bgAudioChanged(_:)))
            } else {
                cell.textLabel?.text = "Picture in Picture"
                cell.detailTextLabel?.text = "Floating system video window"
                cell.selectionStyle = .none
                cell.accessoryView = makeSwitch(on: AppSettings.pictureInPictureEnabled, action: #selector(pipChanged(_:)))
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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

    private func makeSwitch(on: Bool, action: Selector) -> UISwitch {
        let sw = UISwitch()
        sw.isOn = on
        sw.addTarget(self, action: action, for: .valueChanged)
        return sw
    }
}
