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

/// Simple home: Favorites grid. Also used as a fullscreen overlay from Tabs / Space.
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
    private var defaultBrowserPromo: UIView?

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

        view.addSubview(scrollView)
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

        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
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

        if DefaultBrowserFeature.isEnabled {
            let promo = DefaultBrowserPromoUI.makeBanner { [weak self] in
                guard let self else { return }
                self.delegate?.accountHub(self, didRequestMenuAction: .setDefaultBrowser)
            }
            defaultBrowserPromo = promo
            scrollContentView.addSubview(promo)
            promo.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(20)
                make.top.greaterThanOrEqualTo(favoritesStack.snp.bottom).offset(28)
                make.bottom.equalToSuperview().inset(24)
            }
        }
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
        let size = Self.favoriteIconSize

        // Complete circular badge (same language as Facebook’s bundled mark).
        let icon = UIImageView(image: FavoriteBrandStyle.badgeImage(
            urlString: site.urlString,
            assetName: site.logoAssetName,
            fallbackTitle: site.title
        ))
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = size / 2
        icon.backgroundColor = .clear

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

        wrap.addSubview(icon)
        wrap.addSubview(label)
        wrap.addSubview(button)
        icon.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(size)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(icon.snp.bottom).offset(6)
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
                make.top.equalTo(icon).offset(-4)
                make.trailing.equalTo(icon).offset(4)
                make.size.equalTo(18)
            }
        }

        return wrap
    }

    private func makeAddFavoriteTile() -> UIView {
        let wrap = UIView()
        let size = Self.favoriteIconSize

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128))
        let badge = renderer.image { _ in
            let bounds = CGRect(x: 0, y: 0, width: 128, height: 128)
            UIColor(white: 0.18, alpha: 1).setFill()
            UIBezierPath(ovalIn: bounds).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .medium)
            if let plus = UIImage(systemName: "plus", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let side: CGFloat = 52
                plus.draw(in: CGRect(x: (128 - side) / 2, y: (128 - side) / 2, width: side, height: side))
            }
        }

        let icon = UIImageView(image: badge)
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = size / 2

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

        wrap.addSubview(icon)
        wrap.addSubview(label)
        wrap.addSubview(button)
        icon.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.size.equalTo(size)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(icon.snp.bottom).offset(6)
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
