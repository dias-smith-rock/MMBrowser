import UIKit
import SnapKit

protocol NewTabViewControllerDelegate: AnyObject {
    func newTabDidRequestIncognito()
    func newTabDidOpenURL(_ url: URL)
    func newTabDidTapSeeMoreContinue()
    func newTabDidRequestEditShortcuts()
    func newTabDidRequestSettings()
    func newTabDidRequestAccountSwitch()
    func newTabDidRequestAddAccount()
}

/// NTP: brand header + editable navigation directory. Search uses the bottom address bar.
final class NewTabViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: NewTabViewControllerDelegate?

    private(set) var containerID: UUID?
    private var accountName = ""
    private var accountColor: UIColor = BrowserTheme.chromeBlue
    private var accountCount = 1
    private var pinnedSites: [NavigationSite] = []
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let logoView = GoogleLogoView()
    private let editButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let accountHero = UIView()
    private let accountHeroAccent = UIView()
    private let accountHeroDot = UIView()
    private let accountHeroTitle = UILabel()
    private let accountHeroSubtitle = UILabel()
    private let accountHeroButton = UIButton(type: .system)
    private let accountHeroTextStack = UIStackView()
    private let directoryStack = UIStackView()
    private var isEditingDirectory = false
    /// Suppresses rebuild while a site icon is mid-drag.
    private var isDraggingSite = false
    private var siteDragSnapshot: UIView?
    private var siteDragSiteID: UUID?
    private var siteDragCategoryID: UUID?
    private var siteDragFingerOffset: CGPoint = .zero
    private lazy var siteDragGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSiteDrag(_:)))
        gesture.minimumPressDuration = 0.22
        gesture.allowableMovement = 28
        gesture.delegate = self
        return gesture
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        buildDirectory()
        applyHomeSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(applyHomeSettings), name: .homeSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyHomeSettings), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(directoryChanged), name: .navigationDirectoryChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func applyHomeSettings() {
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        styleHeaderChip(editButton)
        styleHeaderChip(settingsButton)
        logoView.applyTheme()
        refreshAccountHeroAppearance()
        buildDirectory()
    }

    @objc private func directoryChanged() {
        guard !isDraggingSite else { return }
        buildDirectory()
    }

    /// Kept for BrowserViewController call sites.
    func reloadContinue(from tabs: [BrowserTab] = []) {
        _ = tabs
    }

    func configure(
        containerID: UUID,
        accountName: String,
        accountColor: UIColor,
        accountCount: Int,
        pinnedSites: [NavigationSite]
    ) {
        self.containerID = containerID
        self.accountName = accountName
        self.accountColor = accountColor
        self.accountCount = max(1, accountCount)
        self.pinnedSites = pinnedSites
        refreshAccountHeroAppearance()
        buildDirectory()
    }

    private var resolvedContainerID: UUID {
        ContainerScope.resolveContainerID(containerID)
    }

    private var navCategories: [NavigationCategory] {
        NavigationStore.shared.categories(for: resolvedContainerID)
    }
    func reloadShortcuts() {
        buildDirectory()
    }

    private func styleHeaderChip(_ button: UIButton) {
        button.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        button.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.45).cgColor
    }

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
        scrollView.addGestureRecognizer(siteDragGesture)

        configureChip(editButton, title: "Edit")
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        configureChip(settingsButton, title: "Settings")
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        setupAccountHero()

        directoryStack.axis = .vertical
        directoryStack.spacing = 28
        directoryStack.alignment = .fill

        [logoView, editButton, settingsButton, accountHero, directoryStack].forEach {
            contentView.addSubview($0)
        }

        logoView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.equalToSuperview().offset(16)
        }
        settingsButton.snp.makeConstraints { make in
            make.centerY.equalTo(logoView)
            make.trailing.equalToSuperview().offset(-16)
        }
        editButton.snp.makeConstraints { make in
            make.centerY.equalTo(logoView)
            make.trailing.equalTo(settingsButton.snp.leading).offset(-8)
            make.leading.greaterThanOrEqualTo(logoView.snp.trailing).offset(8)
        }
        accountHero.snp.makeConstraints { make in
            make.top.equalTo(logoView.snp.bottom).offset(18)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
        }
        directoryStack.snp.makeConstraints { make in
            make.top.equalTo(accountHero.snp.bottom).offset(22)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-32)
        }
    }

    private func setupAccountHero() {
        accountHero.layer.cornerRadius = 14
        accountHero.clipsToBounds = true
        accountHero.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(accountHeroTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        accountHero.addGestureRecognizer(tap)

        accountHeroAccent.layer.cornerRadius = 2
        accountHeroDot.layer.cornerRadius = 6
        accountHeroDot.clipsToBounds = true

        accountHeroTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        accountHeroTitle.textColor = BrowserTheme.textPrimary
        accountHeroTitle.numberOfLines = 1

        accountHeroSubtitle.font = .systemFont(ofSize: 13, weight: .regular)
        accountHeroSubtitle.textColor = BrowserTheme.textSecondary
        accountHeroSubtitle.numberOfLines = 2
        accountHeroSubtitle.text = "Separate cookies & logins per space"

        accountHeroTextStack.axis = .vertical
        accountHeroTextStack.alignment = .leading
        accountHeroTextStack.spacing = 2
        accountHeroTextStack.addArrangedSubview(accountHeroTitle)
        accountHeroTextStack.addArrangedSubview(accountHeroSubtitle)

        accountHeroButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        accountHeroButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        accountHeroButton.layer.cornerRadius = 16
        accountHeroButton.layer.borderWidth = 1
        accountHeroButton.addTarget(self, action: #selector(accountHeroTapped), for: .touchUpInside)
        accountHeroButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        [accountHeroAccent, accountHeroDot, accountHeroTextStack, accountHeroButton].forEach {
            accountHero.addSubview($0)
        }

        accountHeroAccent.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.width.equalTo(4)
            make.height.equalTo(28)
        }
        accountHeroDot.snp.makeConstraints { make in
            make.leading.equalTo(accountHeroAccent.snp.trailing).offset(10)
            make.centerY.equalToSuperview()
            make.size.equalTo(12)
        }
        accountHeroButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
        }
        accountHeroTextStack.snp.makeConstraints { make in
            make.leading.equalTo(accountHeroDot.snp.trailing).offset(10)
            make.trailing.lessThanOrEqualTo(accountHeroButton.snp.leading).offset(-10)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
        }

        refreshAccountHeroAppearance()
    }

    private func refreshAccountHeroAppearance() {
        let color = accountColor
        accountHero.backgroundColor = BrowserTheme.elevated.withAlphaComponent(0.92)
        accountHero.layer.borderWidth = 1
        accountHero.layer.borderColor = color.withAlphaComponent(0.35).cgColor
        accountHeroAccent.backgroundColor = color
        accountHeroDot.backgroundColor = color
        accountHeroTitle.text = "Browsing as \(accountName.isEmpty ? "Personal" : accountName)"
        accountHeroTitle.textColor = BrowserTheme.textPrimary
        accountHeroSubtitle.textColor = BrowserTheme.textSecondary
        accountHeroSubtitle.isHidden = !AppSettings.showsNewTabAccountHeroSubtitle

        let canSwitch = accountCount > 1
        accountHeroButton.setTitle(canSwitch ? "Switch" : "Add Space", for: .normal)
        accountHeroButton.setTitleColor(color, for: .normal)
        accountHeroButton.backgroundColor = color.withAlphaComponent(0.14)
        accountHeroButton.layer.borderColor = color.withAlphaComponent(0.45).cgColor
        accountHeroButton.accessibilityLabel = canSwitch ? "Switch space" : "Add space"
        accountHero.accessibilityLabel = accountHeroTitle.text
        accountHero.accessibilityHint = canSwitch
            ? "Opens space switcher"
            : "Create another space to keep logins separate"
    }

    @objc private func accountHeroTapped() {
        if accountCount > 1 {
            delegate?.newTabDidRequestAccountSwitch()
        } else {
            delegate?.newTabDidRequestAddAccount()
        }
    }

    private func configureChip(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        styleHeaderChip(button)
    }

    private func buildDirectory() {
        directoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        directoryStack.spacing = isEditingDirectory ? 24 : 16

        if isEditingDirectory {
            for (index, category) in navCategories.enumerated() {
                directoryStack.addArrangedSubview(makeCategorySection(category, categoryIndex: index))
            }
            return
        }

        // One deduped card grid — never stack account pins + nav catalog.
        var seen = Set<String>()
        var tiles: [UIView] = []

        func take(_ urlString: String) -> Bool {
            let key = Self.normalizeShortcutKey(urlString)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }

        for site in pinnedSites where take(site.urlString) {
            tiles.append(makePinnedSiteTile(site))
        }
        for category in navCategories {
            for (siteIndex, site) in category.sites.enumerated() where take(site.urlString) {
                tiles.append(makeSiteTile(site, category: category, siteIndex: siteIndex))
            }
        }
        if !tiles.isEmpty {
            directoryStack.addArrangedSubview(makeCardGrid(tiles: tiles))
        }
    }

    private static func normalizeShortcutKey(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.host?.hasPrefix("www.") == true {
            components.host = String(components.host!.dropFirst(4))
        }
        components.fragment = nil
        if components.path.count > 1, components.path.hasSuffix("/") {
            components.path = String(components.path.dropLast())
        }
        return (components.string ?? urlString).lowercased()
    }

    private func makeCategorySection(_ category: NavigationCategory, categoryIndex: Int) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 14
        section.alignment = .fill

        // Edit mode keeps a compact header for reorder / restore only.
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        if !category.isHome {
            let up = makeIconButton(systemName: "chevron.up", categoryID: category.id, tag: categoryIndex)
            up.addTarget(self, action: #selector(moveCategoryUp(_:)), for: .touchUpInside)
            up.isEnabled = categoryIndex > 1
            let down = makeIconButton(systemName: "chevron.down", categoryID: category.id, tag: categoryIndex)
            down.addTarget(self, action: #selector(moveCategoryDown(_:)), for: .touchUpInside)
            down.isEnabled = categoryIndex < navCategories.count - 1
            header.addArrangedSubview(up)
            header.addArrangedSubview(down)
        }

        let title = UILabel()
        title.text = category.title
        title.textColor = BrowserTheme.textPrimary
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())

        if category.isHome {
            let restore = makeIconButton(systemName: "arrow.counterclockwise", categoryID: category.id, tag: categoryIndex)
            restore.accessibilityLabel = "Restore Defaults"
            restore.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                NavigationStore.shared.restoreDefaults(containerID: resolvedContainerID)
                self.buildDirectory()
                Toast.show("Defaults restored", from: self)
            }, for: .touchUpInside)
            header.addArrangedSubview(restore)
        }

        section.addArrangedSubview(header)
        section.addArrangedSubview(makeSitesGrid(
            sites: category.sites,
            categoryID: category.id,
            appendAddTile: true
        ))
        return section
    }

    private func makeSitesGrid(
        sites: [NavigationSite],
        categoryID: UUID?,
        appendAddTile: Bool
    ) -> UIView {
        var tiles: [UIView] = []
        if let categoryID, let category = navCategories.first(where: { $0.id == categoryID }) {
            for (siteIndex, site) in sites.enumerated() {
                tiles.append(makeSiteTile(site, category: category, siteIndex: siteIndex))
            }
            if appendAddTile, isEditingDirectory {
                tiles.append(makeAddSiteTile(categoryID: categoryID))
            }
        } else {
            for site in sites {
                tiles.append(makePinnedSiteTile(site))
            }
        }
        let grid = makeCardGrid(tiles: tiles)
        if let categoryID {
            grid.accessibilityIdentifier = categoryID.uuidString
        }
        return grid
    }

    private func makeCardGrid(tiles: [UIView]) -> UIStackView {
        let columns = 3
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        grid.alignment = .fill

        var row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 10

        for (i, tile) in tiles.enumerated() {
            if i > 0, i % columns == 0 {
                while row.arrangedSubviews.count < columns {
                    row.addArrangedSubview(UIView())
                }
                grid.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.alignment = .fill
                row.distribution = .fillEqually
                row.spacing = 10
            }
            row.addArrangedSubview(tile)
        }
        while row.arrangedSubviews.count < columns {
            row.addArrangedSubview(UIView())
        }
        if !row.arrangedSubviews.isEmpty {
            grid.addArrangedSubview(row)
        }
        return grid
    }

    private func styleShortcutCard(_ card: UIView) {
        card.backgroundColor = BrowserTheme.elevated
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1
        card.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.18).cgColor
        card.clipsToBounds = true
    }

    private func makePinnedSiteTile(_ site: NavigationSite) -> UIView {
        let card = UIView()
        styleShortcutCard(card)

        let iconWell = UIView()
        iconWell.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        iconWell.layer.cornerRadius = 14
        iconWell.clipsToBounds = true

        let icon = FaviconImageView()
        icon.contentMode = .scaleAspectFit
        icon.clipsToBounds = true
        icon.setLogo(assetName: site.logoAssetName, urlString: site.urlString, fallbackTitle: site.title)

        let label = UILabel()
        label.text = site.title
        label.textColor = BrowserTheme.textPrimary
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        let button = UIButton(type: .system)
        button.accessibilityLabel = site.title
        button.addAction(UIAction { [weak self] _ in
            guard let url = site.url else { return }
            self?.delegate?.newTabDidOpenURL(url)
        }, for: .touchUpInside)

        card.addSubview(iconWell)
        iconWell.addSubview(icon)
        card.addSubview(label)
        card.addSubview(button)

        iconWell.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.centerX.equalToSuperview()
            make.size.equalTo(44)
        }
        icon.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(6)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().offset(-14)
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return card
    }

    private func makeIconButton(systemName: String, categoryID: UUID, tag: Int) -> CategoryActionButton {
        let button = CategoryActionButton(categoryID: categoryID)
        button.tag = tag
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = BrowserTheme.chromeBlue
        button.snp.makeConstraints { $0.size.equalTo(28) }
        return button
    }

    private func makeSiteTile(_ site: NavigationSite, category: NavigationCategory, siteIndex: Int) -> UIView {
        let card = SiteTileView()
        card.categoryID = category.id
        card.siteID = site.id
        card.siteIndex = siteIndex
        styleShortcutCard(card)

        let iconWell = UIView()
        iconWell.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        iconWell.layer.cornerRadius = 14
        iconWell.clipsToBounds = true

        let icon = FaviconImageView()
        icon.contentMode = .scaleAspectFit
        icon.clipsToBounds = true
        icon.setLogo(assetName: site.logoAssetName, urlString: site.urlString, fallbackTitle: site.title)

        let label = UILabel()
        label.text = site.title
        label.textColor = BrowserTheme.textPrimary
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        let button = NavigationSiteButton(site: site, categoryID: category.id, siteIndex: siteIndex)
        button.addTarget(self, action: #selector(siteTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = site.title

        card.addSubview(iconWell)
        iconWell.addSubview(icon)
        card.addSubview(label)
        card.addSubview(button)

        iconWell.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.centerX.equalToSuperview()
            make.size.equalTo(44)
        }
        icon.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(6)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().offset(-14)
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }

        if isEditingDirectory {
            let delete = UIButton(type: .system)
            delete.setImage(UIImage(systemName: "minus.circle.fill"), for: .normal)
            delete.tintColor = .systemRed
            delete.accessibilityLabel = "Delete"
            let siteID = site.id
            let categoryID = category.id
            delete.addAction(UIAction { [weak self] _ in
                NavigationStore.shared.removeSite(categoryID: categoryID, siteID: siteID, containerID: self?.resolvedContainerID ?? ContainerScope.resolveContainerID(nil))
                self?.buildDirectory()
            }, for: .touchUpInside)
            card.addSubview(delete)
            delete.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(6)
                make.trailing.equalToSuperview().offset(-6)
                make.size.equalTo(22)
            }

            if siteDragSiteID == site.id {
                card.alpha = 0.25
            }
        }

        return card
    }

    private func makeAddSiteTile(categoryID: UUID) -> UIView {
        let card = UIView()
        styleShortcutCard(card)
        card.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor

        let iconWell = UIView()
        iconWell.backgroundColor = BrowserTheme.card
        iconWell.layer.cornerRadius = 14
        iconWell.layer.borderWidth = 1
        iconWell.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor

        let plus = UIImageView(image: UIImage(systemName: "plus"))
        plus.tintColor = BrowserTheme.chromeBlue
        plus.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Add"
        label.textColor = BrowserTheme.textPrimary
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center

        let button = UIButton(type: .system)
        button.accessibilityLabel = "Add Site"
        button.addAction(UIAction { [weak self] _ in
            self?.presentAddSite(categoryID: categoryID)
        }, for: .touchUpInside)

        card.addSubview(iconWell)
        iconWell.addSubview(plus)
        card.addSubview(label)
        card.addSubview(button)

        iconWell.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.centerX.equalToSuperview()
            make.size.equalTo(44)
        }
        plus.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(20)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(8)
            make.bottom.equalToSuperview().offset(-14)
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return card
    }

    private func presentAddSite(categoryID: UUID) {
        let alert = UIAlertController(title: "Add Site", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Title"
            field.autocapitalizationType = .words
        }
        alert.addTextField { field in
            field.placeholder = "URL"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            let title = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return }
            let url = URLInputResolver.resolve(raw)
            let displayTitle = title.isEmpty ? (url.host ?? "Site") : title
            NavigationStore.shared.addSite(
                toCategoryID: categoryID,
                containerID: self?.resolvedContainerID ?? ContainerScope.resolveContainerID(nil),
                title: displayTitle,
                urlString: url.absoluteString
            )
            self?.buildDirectory()
        })
        present(alert, animated: true)
    }

    @objc private func editTapped() {
        isEditingDirectory.toggle()
        editButton.setTitle(isEditingDirectory ? "Done" : "Edit", for: .normal)
        if !isEditingDirectory {
            cancelSiteDrag(animated: false)
        }
        buildDirectory()
    }

    @objc private func settingsTapped() {
        delegate?.newTabDidRequestSettings()
    }

    @objc private func siteTapped(_ sender: NavigationSiteButton) {
        if isEditingDirectory {
            presentSiteEditMenu(sender)
            return
        }
        guard let url = sender.site.url else { return }
        delegate?.newTabDidOpenURL(url)
    }

    private func presentSiteEditMenu(_ sender: NavigationSiteButton) {
        let sheet = UIAlertController(title: sender.site.title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            NavigationStore.shared.removeSite(categoryID: sender.categoryID, siteID: sender.site.id, containerID: self?.resolvedContainerID ?? ContainerScope.resolveContainerID(nil))
            self?.buildDirectory()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sender
            pop.sourceRect = sender.bounds
        }
        present(sheet, animated: true)
    }

    // MARK: - Site drag reorder

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === siteDragGesture else { return true }
        guard isEditingDirectory, !isDraggingSite else { return false }
        let location = gestureRecognizer.location(in: contentView)
        return siteTile(at: location) != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer !== siteDragGesture {
            // Account hero strip tap — let the Switch / Add Space button handle itself.
            if let touched = touch.view,
               touched === accountHeroButton || touched.isDescendant(of: accountHeroButton) {
                return false
            }
            return true
        }
        // Let the red minus control handle its own taps.
        if touch.view is UIButton, !(touch.view is NavigationSiteButton) {
            return false
        }
        return isEditingDirectory
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    @objc private func handleSiteDrag(_ gesture: UILongPressGestureRecognizer) {
        let locationInView = gesture.location(in: view)
        let locationInContent = gesture.location(in: contentView)

        switch gesture.state {
        case .began:
            guard let tile = siteTile(at: locationInContent) else { return }
            beginSiteDrag(tile, fingerInView: locationInView)

        case .changed:
            guard isDraggingSite, let snapshot = siteDragSnapshot else { return }
            snapshot.center = CGPoint(
                x: locationInView.x - siteDragFingerOffset.x,
                y: locationInView.y - siteDragFingerOffset.y
            )
            reorderIfNeeded(fingerInContent: locationInContent)

        case .ended, .cancelled, .failed:
            endSiteDrag()

        default:
            break
        }
    }

    private func beginSiteDrag(_ tile: SiteTileView, fingerInView: CGPoint) {
        isDraggingSite = true
        siteDragCategoryID = tile.categoryID
        siteDragSiteID = tile.siteID
        scrollView.isScrollEnabled = false

        let frameInView = tile.convert(tile.bounds, to: view)
        let snapshot = tile.snapshotView(afterScreenUpdates: true) ?? UIView(frame: frameInView)
        snapshot.frame = frameInView
        snapshot.layer.shadowColor = UIColor.black.cgColor
        snapshot.layer.shadowOpacity = 0.35
        snapshot.layer.shadowRadius = 10
        snapshot.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.addSubview(snapshot)
        siteDragSnapshot = snapshot
        siteDragFingerOffset = CGPoint(x: fingerInView.x - snapshot.center.x, y: fingerInView.y - snapshot.center.y)

        tile.alpha = 0.25
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.15) {
            snapshot.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        }
    }

    private func reorderIfNeeded(fingerInContent: CGPoint) {
        guard let categoryID = siteDragCategoryID, let siteID = siteDragSiteID else { return }
        guard let target = siteTile(at: fingerInContent), target.categoryID == categoryID, target.siteID != siteID else {
            return
        }
        guard let category = navCategories.first(where: { $0.id == categoryID }),
              let from = category.sites.firstIndex(where: { $0.id == siteID }) else { return }
        let to = target.siteIndex
        guard from != to else { return }

        NavigationStore.shared.moveSite(categoryID: categoryID, containerID: resolvedContainerID, from: from, to: to, notify: false)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        buildDirectory()
        view.layoutIfNeeded()
        if let placeholder = siteTile(withSiteID: siteID) {
            placeholder.alpha = 0.25
        }
        if let snapshot = siteDragSnapshot {
            view.bringSubviewToFront(snapshot)
        }
    }

    private func endSiteDrag() {
        guard isDraggingSite else { return }
        let siteID = siteDragSiteID
        let snapshot = siteDragSnapshot

        if let siteID, let placeholder = siteTile(withSiteID: siteID), let snapshot {
            let targetFrame = placeholder.convert(placeholder.bounds, to: view)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                snapshot.transform = .identity
                snapshot.frame = targetFrame
            } completion: { _ in
                snapshot.removeFromSuperview()
                placeholder.alpha = 1
                self.finishSiteDragCleanup()
            }
        } else {
            snapshot?.removeFromSuperview()
            finishSiteDragCleanup()
        }
    }

    private func cancelSiteDrag(animated: Bool) {
        siteDragSnapshot?.removeFromSuperview()
        finishSiteDragCleanup(rebuild: animated)
    }

    private func finishSiteDragCleanup(rebuild: Bool = true) {
        isDraggingSite = false
        siteDragSnapshot = nil
        siteDragSiteID = nil
        siteDragCategoryID = nil
        siteDragFingerOffset = .zero
        scrollView.isScrollEnabled = true
        if rebuild {
            buildDirectory()
        }
    }

    private func siteTile(at pointInContent: CGPoint) -> SiteTileView? {
        findSiteTile(in: directoryStack, pointInContent: pointInContent)
    }

    private func findSiteTile(in root: UIView, pointInContent: CGPoint) -> SiteTileView? {
        for sub in root.subviews {
            if let tile = sub as? SiteTileView {
                let frame = tile.convert(tile.bounds, to: contentView)
                if frame.insetBy(dx: -4, dy: -4).contains(pointInContent) {
                    return tile
                }
            }
            if let found = findSiteTile(in: sub, pointInContent: pointInContent) {
                return found
            }
        }
        return nil
    }

    private func siteTile(withSiteID siteID: UUID) -> SiteTileView? {
        findSiteTile(in: directoryStack) { $0.siteID == siteID }
    }

    private func findSiteTile(in root: UIView, where predicate: (SiteTileView) -> Bool) -> SiteTileView? {
        for sub in root.subviews {
            if let tile = sub as? SiteTileView, predicate(tile) { return tile }
            if let found = findSiteTile(in: sub, where: predicate) { return found }
        }
        return nil
    }

    @objc private func moveCategoryUp(_ sender: CategoryActionButton) {
        let from = sender.tag
        NavigationStore.shared.moveCategory(containerID: resolvedContainerID, from: from, to: from - 1)
        buildDirectory()
    }

    @objc private func moveCategoryDown(_ sender: CategoryActionButton) {
        let from = sender.tag
        NavigationStore.shared.moveCategory(containerID: resolvedContainerID, from: from, to: from + 1)
        buildDirectory()
    }
}

private final class SiteTileView: UIView {
    var categoryID: UUID = UUID()
    var siteID: UUID = UUID()
    var siteIndex: Int = 0
}

private final class NavigationSiteButton: UIButton {
    let site: NavigationSite
    let categoryID: UUID
    let siteIndex: Int

    init(site: NavigationSite, categoryID: UUID, siteIndex: Int) {
        self.site = site
        self.categoryID = categoryID
        self.siteIndex = siteIndex
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class CategoryActionButton: UIButton {
    let categoryID: UUID
    init(categoryID: UUID) {
        self.categoryID = categoryID
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
}
