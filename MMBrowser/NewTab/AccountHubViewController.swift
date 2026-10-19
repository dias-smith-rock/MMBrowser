import UIKit
import SnapKit

protocol AccountHubViewControllerDelegate: AnyObject {
    func accountHubDidRequestClose(_ hub: AccountHubViewController)
    func accountHubDidRequestSettings(_ hub: AccountHubViewController)
    func accountHubDidRequestManageAccounts(_ hub: AccountHubViewController)
    func accountHub(_ hub: AccountHubViewController, didSelectTabID tabID: UUID, accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestNewTabInAccount accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestOpenURL url: URL, accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestMenuAction action: MenuAction)
}

/// Simple home: Favorites grid + library shortcuts. Also used as a fullscreen overlay from Tabs / Space.
final class AccountHubViewController: UIViewController {
    weak var delegate: AccountHubViewControllerDelegate?

    private(set) var isOverlay = false

    private weak var tabManager: TabManager?
    private(set) var previewAccountID: UUID?

    private let spaceNameLabel = UILabel()
    private let scrollView = UIScrollView()
    private let scrollContentView = UIView()
    private let favoritesStack = UIStackView()
    private let titleBandGuide = UILayoutGuide()
    private let closeButton = UIButton(type: .system)
    private let favoritesHeader = UIView()
    private let favoritesTitle = UILabel()
    private let favoritesDoneButton = UIButton(type: .system)
    private let shortcutsGrid = UIStackView()
    private let libraryBar = UIStackView()

    private var isEditingFavorites = false

    private struct FavoriteEntry {
        let site: NavigationSite
        let categoryID: UUID
    }

    convenience init(tabManager: TabManager, previewAccountID: UUID?, isOverlay: Bool) {
        self.init(nibName: nil, bundle: nil)
        self.tabManager = tabManager
        self.previewAccountID = previewAccountID ?? tabManager.selectedTab?.containerID ?? tabManager.defaultContainer.id
        self.isOverlay = isOverlay
    }

    private var spaceTintColor: UIColor?

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        setupChrome()
        reloadAll()
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(directoryChanged), name: .navigationDirectoryChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(homeSettingsChanged), name: .homeSettingsChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func updatePreviewAccount(_ id: UUID) {
        previewAccountID = id
        isEditingFavorites = false
        reloadAll()
    }

    func reloadFromExternalChange() {
        guard isViewLoaded else { return }
        reloadAll()
    }

    func applySpaceChrome(spaceColor: UIColor?) {
        spaceTintColor = spaceColor
        guard isViewLoaded else { return }
        view.backgroundColor = BrowserTheme.spaceHomeColor(spaceColor: spaceColor)
    }

    @objc private func themeChanged() {
        applyResolvedSpaceChrome()
        reloadAll()
    }

    @objc private func directoryChanged() { reloadShortcuts() }
    @objc private func homeSettingsChanged() {
        applyResolvedSpaceChrome()
        reloadAll()
    }

    private func applyResolvedSpaceChrome() {
        let color = spaceTintColor ?? {
            let id = resolvedPreviewID()
            guard let container = tabManager?.container(id: id) else { return nil as UIColor? }
            return AccountColor.color(for: container)
        }()
        spaceTintColor = color
        view.backgroundColor = BrowserTheme.spaceHomeColor(spaceColor: color)
    }

    // MARK: - Layout

    private func setupChrome() {
        spaceNameLabel.font = .systemFont(ofSize: 34, weight: .bold)
        spaceNameLabel.textColor = BrowserTheme.textPrimary
        spaceNameLabel.textAlignment = .center
        spaceNameLabel.numberOfLines = 2
        spaceNameLabel.adjustsFontSizeToFitWidth = true
        spaceNameLabel.minimumScaleFactor = 0.7
        spaceNameLabel.accessibilityTraits = .header

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false

        favoritesStack.axis = .vertical
        favoritesStack.spacing = 16
        favoritesStack.alignment = .fill

        libraryBar.axis = .horizontal
        libraryBar.alignment = .fill
        libraryBar.distribution = .fillEqually
        libraryBar.spacing = 10
        [
            makeLibraryButton(title: "Bookmark", symbol: "bookmark", action: .bookmarks),
            makeLibraryButton(title: "History", symbol: "clock", action: .history),
            makeLibraryButton(title: "Watch Later", symbol: "clock.badge.checkmark", action: .watchLater)
        ].forEach { libraryBar.addArrangedSubview($0) }

        view.addSubview(scrollView)
        view.addSubview(libraryBar)
        scrollView.addSubview(scrollContentView)
        scrollContentView.addSubview(spaceNameLabel)
        scrollContentView.addSubview(favoritesStack)
        scrollContentView.addLayoutGuide(titleBandGuide)

        if isOverlay {
            configureCloseButton()
            view.addSubview(closeButton)
            closeButton.snp.makeConstraints { make in
                make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
                make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            }
        }

        // Parent raises additionalSafeAreaInsets so this sits flush above the floating chrome.
        libraryBar.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
            make.height.equalTo(72)
        }

        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(libraryBar.snp.top).offset(-10)
        }

        // Center favorites when short; allow scrolling when the grid grows.
        scrollContentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
            make.height.greaterThanOrEqualTo(scrollView.frameLayoutGuide)
        }
        favoritesStack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(8)
            make.bottom.lessThanOrEqualToSuperview().offset(-8)
        }

        // Space title sits midway between the top and Favorites (equal gaps).
        titleBandGuide.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalTo(favoritesStack.snp.top)
            make.leading.trailing.equalToSuperview()
        }
        spaceNameLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleBandGuide)
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.greaterThanOrEqualTo(titleBandGuide.snp.top).offset(4)
            make.bottom.lessThanOrEqualTo(titleBandGuide.snp.bottom).offset(-4)
        }

        favoritesTitle.text = "FAVORITES"
        favoritesTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        favoritesTitle.textColor = BrowserTheme.textSecondary

        favoritesDoneButton.setTitle("Done", for: .normal)
        favoritesDoneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        favoritesDoneButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        favoritesDoneButton.addTarget(self, action: #selector(doneEditingFavorites), for: .touchUpInside)
        favoritesDoneButton.isHidden = true

        favoritesHeader.addSubview(favoritesTitle)
        favoritesHeader.addSubview(favoritesDoneButton)
        favoritesTitle.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        favoritesDoneButton.snp.makeConstraints { make in
            make.trailing.centerY.equalToSuperview()
            make.leading.greaterThanOrEqualTo(favoritesTitle.snp.trailing).offset(8)
        }
        favoritesHeader.snp.makeConstraints { $0.height.equalTo(28) }
        let headerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(favoriteLongPressed(_:)))
        headerLongPress.minimumPressDuration = 0.35
        favoritesHeader.addGestureRecognizer(headerLongPress)

        shortcutsGrid.axis = .vertical
        shortcutsGrid.spacing = Self.favoriteRowSpacing
        shortcutsGrid.alignment = .fill

        favoritesStack.addArrangedSubview(favoritesHeader)
        favoritesStack.addArrangedSubview(shortcutsGrid)
    }

    private func makeLibraryButton(title: String, symbol: String, action: MenuAction) -> UIView {
        let container = UIView()
        container.backgroundColor = BrowserTheme.elevated
        container.layer.cornerRadius = 16
        container.clipsToBounds = true

        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = BrowserTheme.textPrimary
        image.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = BrowserTheme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 2

        let button = MenuActionButton(action: action)
        button.addTarget(self, action: #selector(libraryButtonTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = title

        container.addSubview(image)
        container.addSubview(label)
        container.addSubview(button)
        image.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.centerX.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(image.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(6)
            make.bottom.lessThanOrEqualToSuperview().offset(-10)
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return container
    }

    private func configureCloseButton() {
        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
            for: .normal
        )
        closeButton.tintColor = .black
        closeButton.backgroundColor = BrowserTheme.chromeBlue
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.snp.makeConstraints { $0.size.equalTo(32) }
    }

    // MARK: - Reload

    private func reloadAll() {
        applyResolvedSpaceChrome()
        let accent = spaceTintColor ?? BrowserTheme.chromeBlue
        spaceNameLabel.text = currentSpaceName()
        spaceNameLabel.textColor = BrowserTheme.textPrimary
        favoritesTitle.textColor = BrowserTheme.textSecondary
        favoritesDoneButton.setTitleColor(accent, for: .normal)
        closeButton.backgroundColor = accent
        reloadShortcuts()
        libraryBar.arrangedSubviews.forEach { tile in
            tile.backgroundColor = BrowserTheme.elevated
        }
    }

    private func currentSpaceName() -> String {
        let id = resolvedPreviewID()
        if let name = tabManager?.container(id: id)?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return "Space"
    }

    private func resolvedPreviewID() -> UUID {
        if let previewAccountID, tabManager?.container(id: previewAccountID) != nil {
            return previewAccountID
        }
        return tabManager?.selectedTab?.containerID
            ?? tabManager?.defaultContainer.id
            ?? UUID()
    }

    private func favoriteEntries() -> [FavoriteEntry] {
        let accountID = resolvedPreviewID()
        var entries: [FavoriteEntry] = []
        var seen = Set<String>()
        for category in NavigationStore.shared.categories(for: accountID) {
            for site in category.sites {
                let key = site.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard seen.insert(key).inserted else { continue }
                entries.append(FavoriteEntry(site: site, categoryID: category.id))
            }
        }
        return entries
    }

    private static let favoriteColumns = 5
    private static let favoriteIconSize: CGFloat = 56
    private static let favoriteCornerRadius: CGFloat = 14
    private static let favoriteTileHeight: CGFloat = 82
    private static let favoriteRowSpacing: CGFloat = 12
    private static let favoriteColumnSpacing: CGFloat = 8

    private func reloadShortcuts() {
        shortcutsGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        favoritesDoneButton.isHidden = !isEditingFavorites

        var entries = favoriteEntries()
        if !isEditingFavorites {
            entries = Array(entries.prefix(24))
        }

        let columns = Self.favoriteColumns
        var tiles: [UIView] = entries.map { makeFavoriteTile($0) }
        tiles.append(makeAddFavoriteTile())

        var row = UIStackView()
        row.axis = .horizontal
        row.spacing = Self.favoriteColumnSpacing
        row.distribution = .fillEqually
        row.alignment = .top

        for (index, tile) in tiles.enumerated() {
            if index > 0, index % columns == 0 {
                while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
                shortcutsGrid.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.spacing = Self.favoriteColumnSpacing
                row.distribution = .fillEqually
                row.alignment = .top
            }
            row.addArrangedSubview(tile)
        }
        while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
        if !row.arrangedSubviews.isEmpty {
            shortcutsGrid.addArrangedSubview(row)
        }
    }

    private func makeFavoriteTile(_ entry: FavoriteEntry) -> UIView {
        let site = entry.site
        let wrap = UIView()

        let iconWell = UIView()
        // White well so transparent logo corners don't read as a dark frame.
        iconWell.backgroundColor = .white
        iconWell.layer.cornerRadius = Self.favoriteCornerRadius
        iconWell.layer.cornerCurve = .continuous
        iconWell.clipsToBounds = true

        let icon = FaviconImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.backgroundColor = .white
        icon.setLogo(assetName: site.logoAssetName, urlString: site.urlString, fallbackTitle: site.title)

        let label = UILabel()
        label.text = site.title
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = BrowserTheme.textPrimary
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail

        let button = UIButton(type: .system)
        button.accessibilityLabel = site.title
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.isEditingFavorites { return }
            guard let url = site.url else { return }
            self.delegate?.accountHub(self, didRequestOpenURL: url, accountID: self.resolvedPreviewID())
        }, for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(favoriteLongPressed(_:)))
        longPress.minimumPressDuration = 0.35
        button.addGestureRecognizer(longPress)

        wrap.addSubview(iconWell)
        iconWell.addSubview(icon)
        wrap.addSubview(label)
        wrap.addSubview(button)
        iconWell.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(Self.favoriteIconSize)
        }
        icon.snp.makeConstraints { $0.edges.equalToSuperview() }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        wrap.snp.makeConstraints { $0.height.equalTo(Self.favoriteTileHeight) }

        if isEditingFavorites {
            let delete = UIButton(type: .system)
            delete.setImage(
                UIImage(systemName: "minus.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)),
                for: .normal
            )
            delete.tintColor = .systemRed
            delete.backgroundColor = BrowserTheme.background
            delete.layer.cornerRadius = 9
            delete.accessibilityLabel = "Delete \(site.title)"
            let categoryID = entry.categoryID
            let siteID = site.id
            delete.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                NavigationStore.shared.removeSite(
                    categoryID: categoryID,
                    siteID: siteID,
                    containerID: self.resolvedPreviewID()
                )
                self.reloadShortcuts()
            }, for: .touchUpInside)
            wrap.addSubview(delete)
            delete.snp.makeConstraints { make in
                make.top.equalTo(iconWell).offset(-4)
                make.trailing.equalTo(iconWell).offset(4)
                make.size.equalTo(18)
            }
        }

        return wrap
    }

    private func makeAddFavoriteTile() -> UIView {
        let wrap = UIView()

        let iconWell = UIView()
        iconWell.backgroundColor = BrowserTheme.elevated
        iconWell.layer.cornerRadius = Self.favoriteCornerRadius
        iconWell.layer.cornerCurve = .continuous
        iconWell.clipsToBounds = true
        iconWell.layer.borderWidth = 1
        iconWell.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor

        let plus = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        plus.tintColor = BrowserTheme.textSecondary
        plus.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Add"
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = BrowserTheme.textPrimary
        label.textAlignment = .center

        let button = UIButton(type: .system)
        button.accessibilityLabel = "Add Favorite"
        button.addAction(UIAction { [weak self] _ in
            self?.presentAddFavorite()
        }, for: .touchUpInside)

        wrap.addSubview(iconWell)
        iconWell.addSubview(plus)
        wrap.addSubview(label)
        wrap.addSubview(button)
        iconWell.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(Self.favoriteIconSize)
        }
        plus.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(18)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        wrap.snp.makeConstraints { $0.height.equalTo(Self.favoriteTileHeight) }
        return wrap
    }

    private func presentAddFavorite() {
        let alert = UIAlertController(title: "Add Favorite", message: nil, preferredStyle: .alert)
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
            guard let self else { return }
            let title = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return }
            let url = URLInputResolver.resolve(raw)
            let displayTitle = title.isEmpty ? (url.host ?? "Site") : title
            let ok = NavigationStore.shared.addToHome(
                title: displayTitle,
                url: url,
                containerID: self.resolvedPreviewID()
            )
            if !ok {
                Toast.show("Already in Favorites", from: self)
            }
            self.reloadShortcuts()
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        delegate?.accountHubDidRequestClose(self)
    }

    @objc private func libraryButtonTapped(_ sender: MenuActionButton) {
        delegate?.accountHub(self, didRequestMenuAction: sender.menuAction)
    }

    @objc private func favoriteLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isEditingFavorites else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isEditingFavorites = true
        reloadShortcuts()
    }

    @objc private func doneEditingFavorites() {
        isEditingFavorites = false
        reloadShortcuts()
    }
}
