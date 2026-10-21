import UIKit
import SnapKit

protocol AccountHubViewControllerDelegate: AnyObject {
    func accountHubDidRequestClose(_ hub: AccountHubViewController)
    func accountHubDidRequestSettings(_ hub: AccountHubViewController)
    func accountHubDidRequestManageAccounts(_ hub: AccountHubViewController)
    func accountHubDidRequestPremium(_ hub: AccountHubViewController)
    func accountHub(_ hub: AccountHubViewController, didSelectTabID tabID: UUID, accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestNewTabInAccount accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestOpenURL url: URL, accountID: UUID)
    func accountHub(_ hub: AccountHubViewController, didRequestMenuAction action: MenuAction)
    /// User swiped / tapped dots to another Space on the home hub.
    func accountHub(_ hub: AccountHubViewController, didSwitchToAccount accountID: UUID)
}

/// Simple home: Favorites grid. Also used as a fullscreen overlay from Tabs / Space.
/// Horizontal paging follows the finger to switch Spaces.
final class AccountHubViewController: UIViewController, UIScrollViewDelegate {
    weak var delegate: AccountHubViewControllerDelegate?

    private(set) var isOverlay = false

    private weak var tabManager: TabManager?
    private(set) var previewAccountID: UUID?

    private let pagingScrollView = UIScrollView()
    private let pagesContainer = UIView()
    private let premiumButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private var pageViews: [SpaceHomePageView] = []
    private var isEditingFavorites = false
    private var isProgrammaticPageScroll = false
    private var lastCommittedPageIndex: Int = 0
    private var spaceTintColor: UIColor?

    convenience init(tabManager: TabManager, previewAccountID: UUID?, isOverlay: Bool) {
        self.init(nibName: nil, bundle: nil)
        self.tabManager = tabManager
        self.previewAccountID = previewAccountID ?? tabManager.selectedTab?.containerID ?? tabManager.defaultContainer.id
        self.isOverlay = isOverlay
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        setupChrome()
        rebuildPages(scrollToCurrent: true, animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(directoryChanged), name: .navigationDirectoryChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(homeSettingsChanged), name: .homeSettingsChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPagesIfNeeded()
    }

    func updatePreviewAccount(_ id: UUID) {
        previewAccountID = id
        isEditingFavorites = false
        rebuildPages(scrollToCurrent: true, animated: false)
    }

    func reloadFromExternalChange() {
        guard isViewLoaded else { return }
        rebuildPages(scrollToCurrent: true, animated: false)
    }

    func applySpaceChrome(spaceColor: UIColor?) {
        spaceTintColor = spaceColor
        guard isViewLoaded else { return }
        view.backgroundColor = BrowserTheme.spaceHomeColor(spaceColor: spaceColor)
        pageViews.forEach { $0.applyAccent(spaceColor ?? BrowserTheme.chromeBlue) }
    }

    @objc private func themeChanged() {
        applyResolvedSpaceChrome()
        rebuildPages(scrollToCurrent: true, animated: false)
    }

    @objc private func directoryChanged() {
        pageViews.forEach { $0.reloadFavorites(editing: isEditingFavorites) }
    }

    @objc private func homeSettingsChanged() {
        applyResolvedSpaceChrome()
        rebuildPages(scrollToCurrent: true, animated: false)
    }

    private func applyResolvedSpaceChrome() {
        let color = spaceTintColor ?? {
            let id = resolvedPreviewID()
            guard let container = tabManager?.container(id: id) else { return nil as UIColor? }
            return AccountColor.color(for: container)
        }()
        applySpaceChrome(spaceColor: color)
    }

    // MARK: - Layout

    private func setupChrome() {
        pagingScrollView.isPagingEnabled = true
        pagingScrollView.isDirectionalLockEnabled = true
        pagingScrollView.showsHorizontalScrollIndicator = false
        pagingScrollView.showsVerticalScrollIndicator = false
        pagingScrollView.alwaysBounceHorizontal = true
        pagingScrollView.alwaysBounceVertical = false
        pagingScrollView.bounces = true
        pagingScrollView.delegate = self
        pagingScrollView.contentInsetAdjustmentBehavior = .never
        pagingScrollView.delaysContentTouches = false
        pagingScrollView.decelerationRate = .fast

        view.addSubview(pagingScrollView)
        pagingScrollView.addSubview(pagesContainer)

        pagingScrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }
        pagesContainer.snp.makeConstraints { make in
            make.edges.equalTo(pagingScrollView.contentLayoutGuide)
            make.height.equalTo(pagingScrollView.frameLayoutGuide)
        }

        configurePremiumButton()
        view.addSubview(premiumButton)
        premiumButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(isOverlay ? 56 : 16)
            make.size.equalTo(32)
        }

        if isOverlay {
            configureCloseButton()
            view.addSubview(closeButton)
            closeButton.snp.makeConstraints { make in
                make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
                make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            }
        }
    }

    private func configurePremiumButton() {
        premiumButton.setImage(
            UIImage(systemName: "crown.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)),
            for: .normal
        )
        premiumButton.tintColor = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1)
        premiumButton.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        premiumButton.layer.cornerRadius = 16
        premiumButton.accessibilityLabel = "XBrowser Premium"
        premiumButton.addTarget(self, action: #selector(premiumTapped), for: .touchUpInside)
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

    // MARK: - Pages

    private func spaces() -> [BrowserContainer] {
        tabManager?.sortedContainers ?? []
    }

    private func resolvedPreviewID() -> UUID {
        if let previewAccountID, tabManager?.container(id: previewAccountID) != nil {
            return previewAccountID
        }
        return tabManager?.selectedTab?.containerID
            ?? tabManager?.defaultContainer.id
            ?? UUID()
    }

    private func rebuildPages(scrollToCurrent: Bool, animated: Bool) {
        let list = spaces()
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll()

        for container in list {
            let page = SpaceHomePageView(
                container: container,
                showsDefaultBrowserPromo: DefaultBrowserFeature.isEnabled
            )
            page.onOpenURL = { [weak self] url, accountID in
                guard let self else { return }
                self.delegate?.accountHub(self, didRequestOpenURL: url, accountID: accountID)
            }
            page.onAddFavorite = { [weak self] accountID in
                self?.presentAddFavorite(for: accountID)
            }
            page.onBeginEditing = { [weak self] in
                guard let self, !self.isEditingFavorites else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.isEditingFavorites = true
                self.pageViews.forEach { $0.reloadFavorites(editing: true) }
            }
            page.onEndEditing = { [weak self] in
                guard let self else { return }
                self.isEditingFavorites = false
                self.pageViews.forEach { $0.reloadFavorites(editing: false) }
            }
            page.onDefaultBrowser = { [weak self] in
                guard let self else { return }
                self.delegate?.accountHub(self, didRequestMenuAction: .setDefaultBrowser)
            }
            page.onSelectPageIndex = { [weak self] index in
                guard let self else { return }
                self.scrollToPage(index, animated: true, commit: true)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            pagesContainer.addSubview(page)
            pageViews.append(page)
            page.reloadFavorites(editing: isEditingFavorites)
        }

        let pageCount = max(list.count, 1)
        for (index, page) in pageViews.enumerated() {
            page.configurePager(pageCount: pageCount, currentPage: index)
        }

        let accent: UIColor = {
            if let c = tabManager?.container(id: resolvedPreviewID()) {
                return AccountColor.color(for: c)
            }
            return BrowserTheme.chromeBlue
        }()
        applySpaceChrome(spaceColor: accent)
        closeButton.backgroundColor = accent

        view.setNeedsLayout()
        view.layoutIfNeeded()
        layoutPagesIfNeeded()

        if scrollToCurrent {
            let idx = list.firstIndex(where: { $0.id == resolvedPreviewID() }) ?? 0
            lastCommittedPageIndex = idx
            scrollToPage(idx, animated: animated, commit: false)
        }
    }

    private func layoutPagesIfNeeded() {
        let width = pagingScrollView.bounds.width
        let height = pagingScrollView.bounds.height
        guard width > 0, height > 0, !pageViews.isEmpty else { return }

        pagesContainer.snp.remakeConstraints { make in
            make.edges.equalTo(pagingScrollView.contentLayoutGuide)
            make.height.equalTo(pagingScrollView.frameLayoutGuide)
            make.width.equalTo(pagingScrollView.frameLayoutGuide).multipliedBy(pageViews.count)
        }

        for (index, page) in pageViews.enumerated() {
            page.snp.remakeConstraints { make in
                make.top.bottom.equalToSuperview()
                make.width.equalTo(pagingScrollView.frameLayoutGuide)
                make.height.equalTo(pagingScrollView.frameLayoutGuide)
                if index == 0 {
                    make.leading.equalToSuperview()
                } else {
                    make.leading.equalTo(pageViews[index - 1].snp.trailing)
                }
                if index == pageViews.count - 1 {
                    make.trailing.equalToSuperview()
                }
            }
        }
    }

    private func scrollToPage(_ index: Int, animated: Bool, commit: Bool) {
        guard pageViews.indices.contains(index) else { return }
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return }
        isProgrammaticPageScroll = true
        pagingScrollView.setContentOffset(CGPoint(x: CGFloat(index) * width, y: 0), animated: animated)
        if !animated {
            isProgrammaticPageScroll = false
            if commit { commitPageIfNeeded(index) }
        } else if commit {
            // commit after animation ends via scrollViewDidEndScrollingAnimation
            pendingCommitAfterAnimation = true
        }
    }

    private var pendingCommitAfterAnimation = false

    private func currentPageIndex() -> Int {
        let width = pagingScrollView.bounds.width
        guard width > 0 else { return 0 }
        let raw = Int(round(pagingScrollView.contentOffset.x / width))
        return min(max(raw, 0), max(pageViews.count - 1, 0))
    }

    private func commitPageIfNeeded(_ index: Int) {
        guard pageViews.indices.contains(index) else { return }
        let container = pageViews[index].container
        guard container.id != previewAccountID || index != lastCommittedPageIndex else { return }
        previewAccountID = container.id
        lastCommittedPageIndex = index
        applySpaceChrome(spaceColor: AccountColor.color(for: container))
        closeButton.backgroundColor = AccountColor.color(for: container)
        delegate?.accountHub(self, didSwitchToAccount: container.id)
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView, !pageViews.isEmpty else { return }
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let progress = scrollView.contentOffset.x / width
        // Blend background while dragging for a continuous feel.
        let left = min(max(Int(floor(progress)), 0), pageViews.count - 1)
        let right = min(left + 1, pageViews.count - 1)
        let t = progress - CGFloat(left)
        let c0 = AccountColor.color(for: pageViews[left].container)
        let c1 = AccountColor.color(for: pageViews[right].container)
        let blended = blend(c0, c1, t: t)
        view.backgroundColor = BrowserTheme.spaceHomeColor(spaceColor: blended)
        pageViews.forEach { $0.applyAccent(blended) }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        isProgrammaticPageScroll = false
        if isEditingFavorites {
            isEditingFavorites = false
            pageViews.forEach { $0.reloadFavorites(editing: false) }
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        commitPageIfNeeded(currentPageIndex())
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pagingScrollView, !decelerate else { return }
        commitPageIfNeeded(currentPageIndex())
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView else { return }
        isProgrammaticPageScroll = false
        if pendingCommitAfterAnimation {
            pendingCommitAfterAnimation = false
            commitPageIfNeeded(currentPageIndex())
        }
    }

    private func blend(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let u = min(max(t, 0), 1)
        return UIColor(
            red: ar + (br - ar) * u,
            green: ag + (bg - ag) * u,
            blue: ab + (bb - ab) * u,
            alpha: aa + (ba - aa) * u
        )
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        delegate?.accountHubDidRequestClose(self)
    }

    @objc private func premiumTapped() {
        delegate?.accountHubDidRequestPremium(self)
    }

    private func presentAddFavorite(for accountID: UUID) {
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
                containerID: accountID
            )
            if !ok {
                Toast.show("Already in Favorites", from: self)
            }
            self.pageViews.first(where: { $0.container.id == accountID })?
                .reloadFavorites(editing: self.isEditingFavorites)
        })
        present(alert, animated: true)
    }
}

// MARK: - Per-space page

private final class SpaceHomePageView: UIView {
    let container: BrowserContainer

    var onOpenURL: ((URL, UUID) -> Void)?
    var onAddFavorite: ((UUID) -> Void)?
    var onBeginEditing: (() -> Void)?
    var onEndEditing: (() -> Void)?
    var onDefaultBrowser: (() -> Void)?
    var onSelectPageIndex: ((Int) -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let titleHeader = UIStackView()
    private let nameLabel = UILabel()
    private let pageControl = UIPageControl()
    private let favoritesStack = UIStackView()
    private let favoritesHeader = UIView()
    private let favoritesTitle = UILabel()
    private let favoritesDoneButton = UIButton(type: .system)
    private let shortcutsGrid = UIStackView()
    private let titleBandGuide = UILayoutGuide()
    private var promoView: UIView?
    private let showsDefaultBrowserPromo: Bool
    private var isEditing = false
    private var isUpdatingPager = false
    private var pageIndex = 0

    private static let favoriteColumns = 5
    private static let favoriteIconSize: CGFloat = 56
    private static let favoriteTileHeight: CGFloat = 82
    private static let favoriteRowSpacing: CGFloat = 12
    private static let favoriteColumnSpacing: CGFloat = 8

    init(container: BrowserContainer, showsDefaultBrowserPromo: Bool) {
        self.container = container
        self.showsDefaultBrowserPromo = showsDefaultBrowserPromo
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyAccent(_ accent: UIColor) {
        favoritesDoneButton.setTitleColor(accent, for: .normal)
        pageControl.currentPageIndicatorTintColor = accent
    }

    func configurePager(pageCount: Int, currentPage: Int) {
        pageIndex = min(max(currentPage, 0), max(pageCount - 1, 0))
        isUpdatingPager = true
        pageControl.numberOfPages = max(pageCount, 1)
        pageControl.currentPage = pageIndex
        pageControl.isHidden = pageCount <= 1
        isUpdatingPager = false
    }

    private func setup() {
        scrollView.alwaysBounceVertical = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        scrollView.delaysContentTouches = false

        nameLabel.text = {
            let n = container.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "Space" : n
        }()
        nameLabel.font = .systemFont(ofSize: 34, weight: .bold)
        nameLabel.textColor = BrowserTheme.textPrimary
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        nameLabel.accessibilityTraits = .header

        pageControl.hidesForSinglePage = true
        pageControl.pageIndicatorTintColor = BrowserTheme.textSecondary.withAlphaComponent(0.35)
        pageControl.currentPageIndicatorTintColor = BrowserTheme.textPrimary
        pageControl.accessibilityLabel = "Spaces"
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)

        titleHeader.axis = .vertical
        titleHeader.alignment = .center
        titleHeader.spacing = 6
        titleHeader.addArrangedSubview(nameLabel)
        titleHeader.addArrangedSubview(pageControl)
        nameLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
        }

        favoritesStack.axis = .vertical
        favoritesStack.spacing = 16
        favoritesStack.alignment = .fill

        favoritesTitle.text = "FAVORITES"
        favoritesTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        favoritesTitle.textColor = BrowserTheme.textSecondary

        favoritesDoneButton.setTitle("Done", for: .normal)
        favoritesDoneButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        favoritesDoneButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        favoritesDoneButton.addTarget(self, action: #selector(doneEditing), for: .touchUpInside)
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
        let headerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(headerLongPressed(_:)))
        headerLongPress.minimumPressDuration = 0.35
        favoritesHeader.addGestureRecognizer(headerLongPress)

        shortcutsGrid.axis = .vertical
        shortcutsGrid.spacing = Self.favoriteRowSpacing
        shortcutsGrid.alignment = .fill
        favoritesStack.addArrangedSubview(favoritesHeader)
        favoritesStack.addArrangedSubview(shortcutsGrid)

        addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(titleHeader)
        contentView.addSubview(favoritesStack)
        contentView.addLayoutGuide(titleBandGuide)

        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        contentView.snp.makeConstraints { make in
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
        titleBandGuide.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalTo(favoritesStack.snp.top)
            make.leading.trailing.equalToSuperview()
        }
        // Title + dots as a group, centered in the upper band (same vertical place as before).
        titleHeader.snp.makeConstraints { make in
            make.centerY.equalTo(titleBandGuide)
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.greaterThanOrEqualTo(titleBandGuide.snp.top).offset(4)
            make.bottom.lessThanOrEqualTo(titleBandGuide.snp.bottom).offset(-4)
        }

        if showsDefaultBrowserPromo {
            let promo = DefaultBrowserPromoUI.makeBanner { [weak self] in
                self?.onDefaultBrowser?()
            }
            promoView = promo
            contentView.addSubview(promo)
            promo.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(20)
                make.top.greaterThanOrEqualTo(favoritesStack.snp.bottom).offset(28)
                make.bottom.equalToSuperview().inset(24)
            }
        }
    }

    @objc private func pageControlChanged() {
        guard !isUpdatingPager else { return }
        let selected = pageControl.currentPage
        isUpdatingPager = true
        pageControl.currentPage = pageIndex
        isUpdatingPager = false
        guard selected != pageIndex else { return }
        onSelectPageIndex?(selected)
    }

    func reloadFavorites(editing: Bool) {
        isEditing = editing
        favoritesDoneButton.isHidden = !editing
        shortcutsGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var entries = favoriteEntries()
        if !editing {
            entries = Array(entries.prefix(24))
        }

        let columns = Self.favoriteColumns
        var tiles: [UIView] = entries.map { makeFavoriteTile($0, editing: editing) }
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

    private struct FavoriteEntry {
        let site: NavigationSite
        let categoryID: UUID
    }

    private func favoriteEntries() -> [FavoriteEntry] {
        var entries: [FavoriteEntry] = []
        var seen = Set<String>()
        for category in NavigationStore.shared.categories(for: container.id) {
            for site in category.sites {
                let key = site.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard seen.insert(key).inserted else { continue }
                entries.append(FavoriteEntry(site: site, categoryID: category.id))
            }
        }
        return entries
    }

    private func makeFavoriteTile(_ entry: FavoriteEntry, editing: Bool) -> UIView {
        let site = entry.site
        let wrap = UIView()
        let size = Self.favoriteIconSize

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
        let accountID = container.id
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if self.isEditing { return }
            guard let url = site.url else { return }
            self.onOpenURL?(url, accountID)
        }, for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tileLongPressed(_:)))
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

        if editing {
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
                    containerID: self.container.id
                )
                self.reloadFavorites(editing: true)
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
        let accountID = container.id
        button.addAction(UIAction { [weak self] _ in
            self?.onAddFavorite?(accountID)
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

    @objc private func headerLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isEditing else { return }
        onBeginEditing?()
    }

    @objc private func tileLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isEditing else { return }
        onBeginEditing?()
    }

    @objc private func doneEditing() {
        onEndEditing?()
    }
}
