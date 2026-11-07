import UIKit
import SnapKit
import SafariServices

final class AboutSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum AboutLinks {
        static let privacy = URL(string: "https://xxxxxbrowser.cc/privacy.html")!
        static let terms = URL(string: "https://xxxxxbrowser.cc/terms.html")!
        static let rateUs = URL(string: "https://apps.apple.com/app/id6804914972?action=write-review")!
        static let contactUs = URL(string: "mailto:gaowei85714@gmail.com")!
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "About"
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

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 7 }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
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
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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

    private func openLegalURL(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = BrowserTheme.chromeBlue
        present(safari, animated: true)
    }
}
