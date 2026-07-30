import UIKit
import SnapKit

protocol NewTabViewControllerDelegate: AnyObject {
    func newTabDidSubmit(_ text: String)
    func newTabDidRequestIncognito()
    func newTabDidOpenURL(_ url: URL)
    func newTabDidTapSeeMoreContinue()
    func newTabDidRequestEditShortcuts()
    func newTabDidRequestSettings()
}

/// Clean NTP: brand, search, curated navigation directory (non-editable).
final class NewTabViewController: UIViewController {
    weak var delegate: NewTabViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let settingsButton = UIButton(type: .system)
    private let logoView = GoogleLogoView()
    private let searchContainer = UIView()
    private let searchIcon = UIImageView()
    private let searchField = UITextField()
    private let directoryStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        buildDirectory()
        applyHomeSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(applyHomeSettings), name: .homeSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(engineChanged), name: .searchEngineChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyHomeSettings), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func applyHomeSettings() {
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        settingsButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        settingsButton.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.45).cgColor
        searchContainer.backgroundColor = BrowserTheme.elevated
        searchIcon.tintColor = BrowserTheme.chromeBlue
        searchField.textColor = BrowserTheme.textPrimary
        searchField.tintColor = BrowserTheme.chromeBlue
        logoView.applyTheme()
        buildDirectory()
        engineChanged()
    }

    @objc private func engineChanged() {
        let name = SearchEngineManager.current.name
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search \(name) or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )
    }

    /// Kept for BrowserViewController call sites.
    func reloadContinue(from tabs: [BrowserTab] = []) {
        _ = tabs
    }

    func reloadShortcuts() {}

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        scrollView.showsVerticalScrollIndicator = false

        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        settingsButton.setTitle("Settings", for: .normal)
        settingsButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        settingsButton.layer.cornerRadius = 16
        settingsButton.layer.borderWidth = 1
        settingsButton.layer.borderColor = UIColor(white: 0.35, alpha: 1).cgColor
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        searchContainer.backgroundColor = BrowserTheme.elevated
        searchContainer.layer.cornerRadius = 28

        searchIcon.image = UIImage(systemName: "magnifyingglass")
        searchIcon.tintColor = BrowserTheme.chromeBlue
        searchIcon.contentMode = .scaleAspectFit

        searchField.textColor = BrowserTheme.textPrimary
        searchField.tintColor = BrowserTheme.chromeBlue
        searchField.font = .systemFont(ofSize: 16)
        searchField.returnKeyType = .go
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.delegate = self
        searchField.clearButtonMode = .whileEditing

        searchContainer.addSubview(searchIcon)
        searchContainer.addSubview(searchField)

        directoryStack.axis = .vertical
        directoryStack.spacing = 28
        directoryStack.alignment = .fill

        [settingsButton, logoView, searchContainer, directoryStack].forEach {
            contentView.addSubview($0)
        }

        settingsButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().offset(-16)
        }
        logoView.snp.makeConstraints { make in
            make.top.equalTo(settingsButton.snp.bottom).offset(28)
            make.centerX.equalToSuperview()
            make.height.equalTo(52)
            make.width.equalTo(260)
        }
        searchContainer.snp.makeConstraints { make in
            make.top.equalTo(logoView.snp.bottom).offset(28)
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().offset(-20)
            make.height.equalTo(56)
        }
        searchIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        searchField.snp.makeConstraints { make in
            make.leading.equalTo(searchIcon.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }
        directoryStack.snp.makeConstraints { make in
            make.top.equalTo(searchContainer.snp.bottom).offset(36)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-32)
        }
    }

    private func buildDirectory() {
        directoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for category in NavigationDirectory.categories {
            directoryStack.addArrangedSubview(makeCategorySection(category))
        }
    }

    private func makeCategorySection(_ category: NavigationCategory) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 14
        section.alignment = .fill

        let title = UILabel()
        title.text = category.title
        title.textColor = BrowserTheme.textPrimary
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 4

        for site in category.sites.prefix(5) {
            row.addArrangedSubview(makeSiteTile(site))
        }
        // Pad to 5 columns if a category ever has fewer.
        while row.arrangedSubviews.count < 5 {
            row.addArrangedSubview(UIView())
        }

        section.addArrangedSubview(title)
        section.addArrangedSubview(row)
        return section
    }

    private func makeSiteTile(_ site: NavigationSite) -> UIView {
        let container = UIView()
        let iconSize: CGFloat = 48
        let iconPadding: CGFloat = 6

        let iconWell = UIView()
        iconWell.backgroundColor = BrowserTheme.elevated
        iconWell.layer.cornerRadius = iconSize / 2
        iconWell.clipsToBounds = true

        let icon = FaviconImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.setLogo(assetName: site.logoAssetName, fallbackTitle: site.title)

        let label = UILabel()
        label.text = site.title
        label.textColor = BrowserTheme.textSecondary
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

        let button = NavigationSiteButton(site: site)
        button.addTarget(self, action: #selector(siteTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = site.title

        container.addSubview(iconWell)
        iconWell.addSubview(icon)
        container.addSubview(label)
        container.addSubview(button)

        iconWell.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(iconSize)
        }
        icon.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(iconPadding)
        }
        // Inner logo also clipped to a circle after layout.
        icon.layoutIfNeeded()
        let innerSide = iconSize - iconPadding * 2
        icon.layer.cornerRadius = innerSide / 2
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(2)
            make.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }

        return container
    }

    @objc private func settingsTapped() {
        delegate?.newTabDidRequestSettings()
    }

    @objc private func siteTapped(_ sender: NavigationSiteButton) {
        guard let url = sender.site.url else { return }
        delegate?.newTabDidOpenURL(url)
    }
}

private final class NavigationSiteButton: UIButton {
    let site: NavigationSite
    init(site: NavigationSite) {
        self.site = site
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
}

extension NewTabViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.newTabDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}
