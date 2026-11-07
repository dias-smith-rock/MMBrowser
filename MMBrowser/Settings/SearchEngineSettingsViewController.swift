import UIKit
import SnapKit

/// Search engine picker (privacy-friendly + general).
final class SearchEngineSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable {
        case privacyFriendly, general
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Search Engine"
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
        case .privacyFriendly: return SearchEngine.privacyFriendly.count
        case .general: return SearchEngine.general.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .privacyFriendly: return "Privacy-friendly"
        case .general: return "General"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section) == .general ? "Used for address-bar search." : nil
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
        cell.detailTextLabel?.text = nil
        cell.accessoryView = nil
        let engines = Section(rawValue: indexPath.section) == .privacyFriendly
            ? SearchEngine.privacyFriendly
            : SearchEngine.general
        let engine = engines[indexPath.row]
        let recommended = engine.id == SearchEngine.duckDuckGo.id
        cell.textLabel?.text = recommended ? "\(engine.name) · Recommended" : engine.name
        cell.accessoryType = engine.id == AppSettings.searchEngineID ? .checkmark : .none
        cell.tintColor = BrowserTheme.chromeBlue
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let engines = Section(rawValue: indexPath.section) == .privacyFriendly
            ? SearchEngine.privacyFriendly
            : SearchEngine.general
        SearchEngineManager.setCurrent(engines[indexPath.row])
        tableView.reloadData()
    }
}
