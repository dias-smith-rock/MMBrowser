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

/// Simple home: Favorites grid + Bookmarks. Also used as a fullscreen overlay from Tabs / Space.
final class AccountHubViewController: UIViewController {
    weak var delegate: AccountHubViewControllerDelegate?

    private(set) var isOverlay = false

    private weak var tabManager: TabManager?
    private(set) var previewAccountID: UUID?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let favoritesHeader = UIView()
    private let favoritesTitle = UILabel()
    private let favoritesDoneButton = UIButton(type: .system)
    private let shortcutsGrid = UIStackView()
    private let bookmarksHeader = HubSectionHeaderButton()
    private let bookmarksBody = UIStackView()

    private var bookmarksExpanded = true
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
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

    @objc private func themeChanged() {
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        reloadAll()
    }

    @objc private func directoryChanged() { reloadShortcuts() }
    @objc private func homeSettingsChanged() {
        view.backgroundColor = BrowserTheme.homeWallpaperColor()
        reloadAll()
    }

    // MARK: - Layout

    private func setupChrome() {
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)

        scrollView.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(isOverlay ? 8 : 20)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-28)
            make.width.equalTo(scrollView).offset(-32)
        }

        if isOverlay {
            configureCloseButton()
            contentStack.addArrangedSubview(makeOverlayHeader())
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

        bookmarksBody.axis = .vertical
        bookmarksBody.spacing = 0
        bookmarksHeader.addTarget(self, action: #selector(toggleBookmarks), for: .touchUpInside)

        contentStack.addArrangedSubview(favoritesHeader)
        contentStack.addArrangedSubview(shortcutsGrid)
        contentStack.setCustomSpacing(28, after: shortcutsGrid)
        contentStack.addArrangedSubview(bookmarksHeader)
        contentStack.setCustomSpacing(10, after: bookmarksHeader)
        contentStack.addArrangedSubview(bookmarksBody)
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

    private func makeOverlayHeader() -> UIView {
        let row = UIStackView(arrangedSubviews: [closeButton, UIView()])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    // MARK: - Reload

    private func reloadAll() {
        favoritesTitle.textColor = BrowserTheme.textSecondary
        favoritesDoneButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        closeButton.backgroundColor = BrowserTheme.chromeBlue
        reloadShortcuts()
        reloadBookmarks()
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

    private static let favoriteColumns = 6
    private static let favoriteIconSize: CGFloat = 44
    private static let favoriteTileHeight: CGFloat = 72
    private static let favoriteRowSpacing: CGFloat = 10
    private static let favoriteColumnSpacing: CGFloat = 6

    private func reloadShortcuts() {
        shortcutsGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        favoritesDoneButton.isHidden = !isEditingFavorites

        var entries = favoriteEntries()
        if !isEditingFavorites {
            entries = Array(entries.prefix(24))
        }

        let columns = Self.favoriteColumns
        var tiles: [UIView] = entries.map { makeFavoriteTile($0) }
        if isEditingFavorites || entries.isEmpty {
            tiles.append(makeAddFavoriteTile())
        }

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
        iconWell.backgroundColor = BrowserTheme.elevated
        iconWell.layer.cornerRadius = Self.favoriteIconSize / 2
        iconWell.clipsToBounds = true

        let icon = FaviconImageView()
        icon.clipsToBounds = true
        icon.layer.cornerRadius = (Self.favoriteIconSize - 8) / 2
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
        icon.snp.makeConstraints { $0.edges.equalToSuperview().inset(4) }
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
        iconWell.layer.cornerRadius = Self.favoriteIconSize / 2
        iconWell.clipsToBounds = true
        iconWell.layer.borderWidth = 1
        iconWell.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor

        let plus = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))
        plus.tintColor = BrowserTheme.chromeBlue
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

    private func reloadBookmarks() {
        let accountID = resolvedPreviewID()
        let all = BookmarkStore.shared.items(containerID: accountID)
        let items = Array(all.prefix(12))
        let hasItems = !all.isEmpty
        bookmarksHeader.isHidden = !hasItems
        bookmarksHeader.configure(title: "Bookmarks", count: all.count, expanded: bookmarksExpanded)
        bookmarksBody.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bookmarksBody.isHidden = !hasItems || !bookmarksExpanded
        guard hasItems, bookmarksExpanded else { return }
        bookmarksBody.addArrangedSubview(makeListCard(items.map { ($0.title, $0.url) }))
    }

    private func makeListCard(_ rows: [(String, URL?)]) -> UIView {
        let card = UIView()
        card.backgroundColor = BrowserTheme.elevated
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        card.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }

        for (index, row) in rows.enumerated() {
            var config = UIButton.Configuration.plain()
            config.title = row.0
            config.baseForegroundColor = BrowserTheme.textPrimary
            config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 16, weight: .regular)
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            if let url = row.1 {
                button.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.accountHub(self, didRequestOpenURL: url, accountID: self.resolvedPreviewID())
                }, for: .touchUpInside)
            }
            stack.addArrangedSubview(button)
            if index < rows.count - 1 {
                let line = UIView()
                line.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.14)
                line.snp.makeConstraints { $0.height.equalTo(1 / UIScreen.main.scale) }
                stack.addArrangedSubview(line)
            }
        }
        return card
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        delegate?.accountHubDidRequestClose(self)
    }

    @objc private func toggleBookmarks() {
        bookmarksExpanded.toggle()
        reloadBookmarks()
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

// MARK: - Section header

private final class HubSectionHeaderButton: UIButton {
    private let title = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = BrowserTheme.textPrimary
        chevron.tintColor = BrowserTheme.textSecondary
        chevron.contentMode = .scaleAspectFit
        addSubview(title)
        addSubview(chevron)
        title.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
        }
        chevron.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(14)
            make.leading.greaterThanOrEqualTo(title.snp.trailing).offset(8)
        }
        snp.makeConstraints { $0.height.equalTo(28) }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title text: String, count: Int, expanded: Bool) {
        title.text = "\(text) (\(count))"
        chevron.image = UIImage(systemName: expanded ? "chevron.up" : "chevron.down")
        title.textColor = BrowserTheme.textPrimary
        chevron.tintColor = BrowserTheme.textSecondary
    }
}
