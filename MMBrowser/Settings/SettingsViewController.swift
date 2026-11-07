import UIKit
import SnapKit
import SafariServices

/// Root Settings — Brave-style VIP card + categorized hubs.
final class SettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable {
        case premium
        case features
        case general
        case display
        case spaces
        case support
        case about
    }

    private enum FeatureRow: Int, CaseIterable {
        case privacy, playback, webEditor
    }

    private enum GeneralRow: Int, CaseIterable {
        case search, appLock, location, clearOption, defaultBrowser

        static var visible: [GeneralRow] {
            allCases.filter { $0 != .defaultBrowser || DefaultBrowserFeature.isEnabled }
        }
    }

    private enum DisplayRow: Int, CaseIterable {
        case appearance
    }

    private enum SpacesRow: Int, CaseIterable {
        case manage, isolated
    }

    private enum SupportRow: Int, CaseIterable {
        case whatsNew, rateUs, contact
    }

    private enum AboutRow: Int, CaseIterable {
        case version, filters, privacyPolicy, terms
    }

    private enum Legal {
        static let privacy = URL(string: "https://xxxxxbrowser.cc/privacy.html")!
        static let terms = URL(string: "https://xxxxxbrowser.cc/terms.html")!
        static let rateUs = URL(string: "https://apps.apple.com/app/id6804914972?action=write-review")!
        static let contactUs = URL(string: "mailto:gaowei85714@gmail.com")!
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

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
        tableView.register(SettingsPremiumCardCell.self, forCellReuseIdentifier: SettingsPremiumCardCell.reuseID)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 0)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(homeChanged), name: .homeSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(searchChanged), name: .searchEngineChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(premiumChanged), name: .premiumStatusDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(filterStatusChanged), name: .filterStatusChanged, object: nil)
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

    @objc private func homeChanged() { tableView.reloadData() }
    @objc private func searchChanged() { tableView.reloadData() }
    @objc private func premiumChanged() { tableView.reloadData() }
    @objc private func filterStatusChanged() { tableView.reloadData() }

    private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        tableView.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .premium: return 1
        case .features: return FeatureRow.allCases.count
        case .general: return GeneralRow.visible.count
        case .display: return DisplayRow.allCases.count
        case .spaces: return SpacesRow.allCases.count
        case .support: return SupportRow.allCases.count
        case .about: return AboutRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .premium: return nil
        case .features: return "Features"
        case .general: return "General"
        case .display: return "Display"
        case .spaces: return "Spaces"
        case .support: return "Support"
        case .about: return "About"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        Section(rawValue: indexPath.section) == .premium ? UITableView.automaticDimension : 52
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        Section(rawValue: indexPath.section) == .premium ? 168 : 52
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .premium:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsPremiumCardCell.reuseID, for: indexPath) as! SettingsPremiumCardCell
            cell.configure(isActive: PremiumStore.shared.isPremiumActive) { [weak self] in
                guard let self else { return }
                PremiumCoordinator.presentPaywall(from: self, source: "settings")
            }
            return cell
        case .features:
            switch FeatureRow(rawValue: indexPath.row)! {
            case .privacy:
                return hubCell(tableView, title: "Privacy & Security", detail: privacySummary, symbol: "shield.lefthalf.filled")
            case .playback:
                return hubCell(tableView, title: "Playback & Focus", detail: playbackSummary, symbol: "play.rectangle.on.rectangle")
            case .webEditor:
                return hubCell(tableView, title: "Web Editor", detail: "Hide page elements", symbol: "wand.and.stars")
            }
        case .general:
            switch GeneralRow.visible[indexPath.row] {
            case .search:
                return hubCell(tableView, title: "Search Engine", detail: SearchEngineManager.current.name, symbol: "magnifyingglass")
            case .appLock:
                return hubCell(
                    tableView,
                    title: "App Lock",
                    detail: AppLockSettings.isEnabled ? "On" : "Off",
                    symbol: "lock.fill"
                )
            case .location:
                return hubCell(tableView, title: "Location", detail: AppSettings.locationSummary, symbol: "location.fill")
            case .clearOption:
                return hubCell(tableView, title: "Clear Option", detail: AppSettings.clearOptionSummary, symbol: "trash")
            case .defaultBrowser:
                return hubCell(tableView, title: "Default Browser", detail: "System settings", symbol: "compass.drawing")
            }
        case .display:
            return hubCell(tableView, title: "Appearance", detail: appearanceSummary, symbol: "paintpalette.fill")
        case .spaces:
            switch SpacesRow(rawValue: indexPath.row)! {
            case .manage:
                let count = tabManager?.visibleContainers.count ?? 0
                let detail = count == 1 ? "1 Space" : "\(count) Spaces"
                return hubCell(tableView, title: "Manage Spaces", detail: detail, symbol: "person.2.fill")
            case .isolated:
                return hubCell(tableView, title: "Isolated vs Shared", detail: "What stays per Space", symbol: "square.split.2x1")
            }
        case .support:
            switch SupportRow(rawValue: indexPath.row)! {
            case .whatsNew:
                return hubCell(tableView, title: "What's New", detail: nil, symbol: "sparkles")
            case .rateUs:
                return hubCell(tableView, title: "Rate Us", detail: nil, symbol: "star.fill")
            case .contact:
                return hubCell(tableView, title: "Contact Us", detail: nil, symbol: "envelope.fill")
            }
        case .about:
            switch AboutRow(rawValue: indexPath.row)! {
            case .version:
                return hubCell(tableView, title: "XBrowser", detail: "1.0", symbol: "info.circle", disclosure: false)
            case .filters:
                return hubCell(tableView, title: "Filters", detail: FilterUpdateManager.shared.statusSummary, symbol: "line.3.horizontal.decrease.circle")
            case .privacyPolicy:
                return hubCell(tableView, title: "Privacy Policy", detail: nil, symbol: "hand.raised.fill")
            case .terms:
                return hubCell(tableView, title: "Terms of Use", detail: nil, symbol: "doc.text")
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .premium:
            PremiumCoordinator.presentPaywall(from: self, source: "settings")
        case .features:
            switch FeatureRow(rawValue: indexPath.row)! {
            case .privacy:
                let privacy = PrivacySettingsViewController()
                privacy.onRequestRebuildWebViews = { [weak self] in self?.onRequestRebuildWebViews?() }
                privacy.tabManager = tabManager
                navigationController?.pushViewController(privacy, animated: true)
            case .playback:
                navigationController?.pushViewController(PlaybackFocusSettingsViewController(), animated: true)
            case .webEditor:
                navigationController?.pushViewController(PageCleanerRulesViewController(), animated: true)
            }
        case .general:
            switch GeneralRow.visible[indexPath.row] {
            case .search:
                navigationController?.pushViewController(SearchEngineSettingsViewController(), animated: true)
            case .appLock:
                navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
            case .location:
                let location = LocationSettingsViewController()
                location.onChanged = { [weak self] in
                    self?.onRequestRebuildWebViews?()
                    self?.tableView.reloadData()
                }
                navigationController?.pushViewController(location, animated: true)
            case .clearOption:
                navigationController?.pushViewController(ClearOptionSettingsViewController(), animated: true)
            case .defaultBrowser:
                presentDefaultBrowserHelp()
            }
        case .display:
            navigationController?.pushViewController(AppearanceSettingsViewController(), animated: true)
        case .spaces:
            switch SpacesRow(rawValue: indexPath.row)! {
            case .manage:
                guard let tabManager else { return }
                let manage = ContainerManageViewController(tabManager: tabManager)
                manage.showsDoneButton = false
                manage.onChanged = { [weak self] in
                    self?.onAccountsChanged?()
                    self?.tableView.reloadData()
                }
                navigationController?.pushViewController(manage, animated: true)
            case .isolated:
                navigationController?.pushViewController(IsolatedVsSharedViewController(), animated: true)
            }
        case .support:
            switch SupportRow(rawValue: indexPath.row)! {
            case .whatsNew:
                let alert = UIAlertController(
                    title: "What's New",
                    message: "Private by default and isolated by Space. Ads and trackers are blocked, HTTPS First and Global Privacy Control are on, and each Space keeps its own cookies and logins. Not a VPN. YouTube video ads stay best-effort.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            case .rateUs:
                UIApplication.shared.open(Legal.rateUs)
            case .contact:
                UIApplication.shared.open(Legal.contactUs)
            }
        case .about:
            switch AboutRow(rawValue: indexPath.row)! {
            case .version:
                break
            case .filters:
                presentFilterUpdateAlert()
            case .privacyPolicy:
                openLegalURL(Legal.privacy)
            case .terms:
                openLegalURL(Legal.terms)
            }
        }
    }

    // MARK: - Helpers

    private func hubCell(
        _ tableView: UITableView,
        title: String,
        detail: String?,
        symbol: String,
        disclosure: Bool = true
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.text = title
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.accessoryView = nil
        cell.accessoryType = disclosure ? .disclosureIndicator : .none
        cell.selectionStyle = disclosure ? .default : .none
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        cell.imageView?.image = UIImage(systemName: symbol, withConfiguration: config)
        cell.imageView?.tintColor = BrowserTheme.chromeBlue
        return cell
    }

    private var privacySummary: String {
        var parts: [String] = []
        if AppSettings.trackerProtectionEnabled { parts.append("Trackers") }
        if AppSettings.httpsOnly { parts.append("HTTPS") }
        if AppSettings.globalPrivacyControlEnabled { parts.append("GPC") }
        return parts.isEmpty ? "Off" : parts.joined(separator: " · ")
    }

    private var appearanceSummary: String {
        let theme = ThemeManager.shared.current.name
        if HomeWallpaper.selected == .default { return theme }
        return "\(theme) · \(HomeWallpaper.selected.title)"
    }

    private var playbackSummary: String {
        var parts: [String] = []
        if AppSettings.hideShortsEnabled { parts.append("Shorts") }
        if AppSettings.backgroundAudioEnabled { parts.append("Audio") }
        if AppSettings.pictureInPictureEnabled { parts.append("PiP") }
        return parts.isEmpty ? "Off" : parts.joined(separator: " · ")
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

    private func openLegalURL(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = BrowserTheme.chromeBlue
        present(safari, animated: true)
    }

    @objc private func close() { dismiss(animated: true) }
}

// MARK: - Premium VIP card

private final class SettingsPremiumCardCell: UITableViewCell {
    static let reuseID = "SettingsPremiumCardCell"

    private let card = UIView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let ctaButton = UIButton(type: .system)
    private var onTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary

        bodyLabel.font = .systemFont(ofSize: 14, weight: .regular)
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.numberOfLines = 0

        ctaButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.backgroundColor = BrowserTheme.chromeBlue
        ctaButton.layer.cornerRadius = 22
        ctaButton.layer.cornerCurve = .continuous
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)

        contentView.addSubview(card)
        card.addSubview(titleLabel)
        card.addSubview(bodyLabel)
        card.addSubview(ctaButton)

        card.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
        }
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(18)
        }
        bodyLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(18)
        }
        ctaButton.snp.makeConstraints { make in
            make.top.equalTo(bodyLabel.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(18)
            make.bottom.equalToSuperview().inset(18)
            make.height.equalTo(44)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(isActive: Bool, onTap: @escaping () -> Void) {
        self.onTap = onTap
        card.backgroundColor = BrowserTheme.card
        titleLabel.textColor = BrowserTheme.textPrimary
        bodyLabel.textColor = BrowserTheme.textSecondary
        ctaButton.backgroundColor = BrowserTheme.chromeBlue

        if isActive {
            titleLabel.text = "XBrowser Premium"
            bodyLabel.text = "Unlimited Spaces and Space Lock are unlocked on this device."
            ctaButton.setTitle("Manage Subscription", for: .normal)
        } else {
            titleLabel.text = "XBrowser Premium"
            bodyLabel.text = "Unlock unlimited Spaces and Space Lock. Free includes \(PremiumStore.freeSpaceLimit) Spaces."
            ctaButton.setTitle("View Plans", for: .normal)
        }
    }

    @objc private func ctaTapped() { onTap?() }
}
