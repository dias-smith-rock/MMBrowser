import UIKit
import SnapKit

protocol NewTabViewControllerDelegate: AnyObject {
    func newTabDidRequestIncognito()
    func newTabDidOpenURL(_ url: URL)
    func newTabDidTapSeeMoreContinue()
    func newTabDidRequestEditShortcuts()
    func newTabDidRequestSettings()
}

/// NTP: brand header + editable navigation directory. Search uses the bottom address bar.
final class NewTabViewController: UIViewController {
    weak var delegate: NewTabViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let logoView = GoogleLogoView()
    private let editButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let directoryStack = UIStackView()
    private var isEditingDirectory = false

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
        buildDirectory()
    }

    @objc private func directoryChanged() {
        buildDirectory()
    }

    /// Kept for BrowserViewController call sites.
    func reloadContinue(from tabs: [BrowserTab] = []) {
        _ = tabs
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

        configureChip(editButton, title: "Edit")
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        configureChip(settingsButton, title: "Settings")
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        directoryStack.axis = .vertical
        directoryStack.spacing = 28
        directoryStack.alignment = .fill

        [logoView, editButton, settingsButton, directoryStack].forEach {
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
        directoryStack.snp.makeConstraints { make in
            make.top.equalTo(logoView.snp.bottom).offset(28)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-32)
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
        let categories = NavigationStore.shared.categories
        for (index, category) in categories.enumerated() {
            if !isEditingDirectory, category.isHome, category.sites.isEmpty {
                continue
            }
            directoryStack.addArrangedSubview(makeCategorySection(category, categoryIndex: index))
        }
    }

    private func makeCategorySection(_ category: NavigationCategory, categoryIndex: Int) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 14
        section.alignment = .fill

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        if isEditingDirectory, !category.isHome {
            let up = makeIconButton(systemName: "chevron.up", categoryID: category.id, tag: categoryIndex)
            up.addTarget(self, action: #selector(moveCategoryUp(_:)), for: .touchUpInside)
            up.isEnabled = categoryIndex > 1
            let down = makeIconButton(systemName: "chevron.down", categoryID: category.id, tag: categoryIndex)
            down.addTarget(self, action: #selector(moveCategoryDown(_:)), for: .touchUpInside)
            down.isEnabled = categoryIndex < NavigationStore.shared.categories.count - 1
            header.addArrangedSubview(up)
            header.addArrangedSubview(down)
        }

        let title = UILabel()
        title.text = category.title
        title.textColor = BrowserTheme.textPrimary
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())

        if isEditingDirectory {
            if !category.isHome {
                let addHome = makeIconButton(systemName: "plus.app", categoryID: category.id, tag: categoryIndex)
                addHome.accessibilityLabel = "Add Group to Home"
                addHome.addAction(UIAction { [weak self] _ in
                    guard let self else { return }
                    let added = NavigationStore.shared.addGroupToHome(categoryID: category.id)
                    Toast.show(added > 0 ? "Added to Home" : "Already on Home", from: self)
                    self.buildDirectory()
                }, for: .touchUpInside)
                header.addArrangedSubview(addHome)

                let trash = makeIconButton(systemName: "trash", categoryID: category.id, tag: categoryIndex)
                trash.tintColor = .systemRed
                trash.accessibilityLabel = "Delete Group"
                trash.addAction(UIAction { [weak self] _ in
                    self?.confirmDeleteCategory(category)
                }, for: .touchUpInside)
                header.addArrangedSubview(trash)
            }
            let restore = makeIconButton(systemName: "arrow.counterclockwise", categoryID: category.id, tag: categoryIndex)
            restore.accessibilityLabel = "Restore Defaults"
            restore.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                NavigationStore.shared.restoreDefaults()
                self.buildDirectory()
                Toast.show("Defaults restored", from: self)
            }, for: .touchUpInside)
            // Only show Restore once on the Home row to avoid repeating on every group.
            if category.isHome {
                header.addArrangedSubview(restore)
            }
        }

        section.addArrangedSubview(header)

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        grid.alignment = .fill

        var tiles: [UIView] = []
        let columns = 5
        if isEditingDirectory {
            for (siteIndex, site) in category.sites.enumerated() {
                tiles.append(makeSiteTile(site, category: category, siteIndex: siteIndex))
            }
            tiles.append(makeAddSiteTile(categoryID: category.id))
        } else if category.isHome {
            // Home: show sites only — no "+" edit entry.
            for (siteIndex, site) in category.sites.enumerated() {
                tiles.append(makeSiteTile(site, category: category, siteIndex: siteIndex))
            }
        } else {
            // Show all sites; "+" is always the last tile (wraps to next row when count > 4).
            for (siteIndex, site) in category.sites.enumerated() {
                tiles.append(makeSiteTile(site, category: category, siteIndex: siteIndex))
            }
            if category.sites.count < columns - 1 {
                while tiles.count < columns - 1 {
                    tiles.append(UIView())
                }
            }
            tiles.append(makeEnterEditTile())
        }

        var row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 4

        for (i, tile) in tiles.enumerated() {
            if i > 0, i % columns == 0 {
                while row.arrangedSubviews.count < columns {
                    row.addArrangedSubview(UIView())
                }
                grid.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.alignment = .top
                row.distribution = .fillEqually
                row.spacing = 4
            }
            row.addArrangedSubview(tile)
        }
        while row.arrangedSubviews.count < columns {
            row.addArrangedSubview(UIView())
        }
        grid.addArrangedSubview(row)
        section.addArrangedSubview(grid)
        return section
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

        let button = NavigationSiteButton(site: site, categoryID: category.id, siteIndex: siteIndex)
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
        icon.layoutIfNeeded()
        let innerSide = iconSize - iconPadding * 2
        icon.layer.cornerRadius = innerSide / 2
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(2)
            make.bottom.equalToSuperview()
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
                NavigationStore.shared.removeSite(categoryID: categoryID, siteID: siteID)
                self?.buildDirectory()
            }, for: .touchUpInside)
            container.addSubview(delete)
            delete.snp.makeConstraints { make in
                make.top.equalTo(iconWell).offset(-4)
                make.trailing.equalTo(iconWell).offset(4)
                make.size.equalTo(22)
            }

            if siteIndex > 0 {
                let left = UIButton(type: .system)
                left.setImage(UIImage(systemName: "chevron.left.circle.fill"), for: .normal)
                left.tintColor = BrowserTheme.chromeBlue.withAlphaComponent(0.9)
                left.addAction(UIAction { [weak self] _ in
                    NavigationStore.shared.moveSite(categoryID: category.id, from: siteIndex, to: siteIndex - 1)
                    self?.buildDirectory()
                }, for: .touchUpInside)
                container.addSubview(left)
                left.snp.makeConstraints { make in
                    make.leading.equalTo(iconWell).offset(-6)
                    make.bottom.equalTo(iconWell).offset(2)
                    make.size.equalTo(18)
                }
            }
            if siteIndex < category.sites.count - 1 {
                let right = UIButton(type: .system)
                right.setImage(UIImage(systemName: "chevron.right.circle.fill"), for: .normal)
                right.tintColor = BrowserTheme.chromeBlue.withAlphaComponent(0.9)
                right.addAction(UIAction { [weak self] _ in
                    NavigationStore.shared.moveSite(categoryID: category.id, from: siteIndex, to: siteIndex + 1)
                    self?.buildDirectory()
                }, for: .touchUpInside)
                container.addSubview(right)
                right.snp.makeConstraints { make in
                    make.trailing.equalTo(iconWell).offset(6)
                    make.bottom.equalTo(iconWell).offset(2)
                    make.size.equalTo(18)
                }
            }
        }

        return container
    }

    private func makeEnterEditTile() -> UIView {
        let container = UIView()
        let iconSize: CGFloat = 48

        let iconWell = UIView()
        iconWell.backgroundColor = BrowserTheme.elevated
        iconWell.layer.cornerRadius = iconSize / 2
        iconWell.layer.borderWidth = 1
        iconWell.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.35).cgColor

        let plus = UIImageView(image: UIImage(systemName: "plus"))
        plus.tintColor = BrowserTheme.chromeBlue
        plus.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Edit"
        label.textColor = BrowserTheme.textSecondary
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center

        let button = UIButton(type: .system)
        button.accessibilityLabel = "Edit"
        button.addTarget(self, action: #selector(enterEditFromPlus), for: .touchUpInside)

        container.addSubview(iconWell)
        iconWell.addSubview(plus)
        container.addSubview(label)
        container.addSubview(button)

        iconWell.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(iconSize)
        }
        plus.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(2)
            make.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return container
    }

    private func makeAddSiteTile(categoryID: UUID) -> UIView {
        let container = UIView()
        let iconSize: CGFloat = 48

        let iconWell = UIView()
        iconWell.backgroundColor = BrowserTheme.elevated
        iconWell.layer.cornerRadius = iconSize / 2
        iconWell.layer.borderWidth = 1
        iconWell.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.35).cgColor

        let plus = UIImageView(image: UIImage(systemName: "plus"))
        plus.tintColor = BrowserTheme.chromeBlue
        plus.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Add"
        label.textColor = BrowserTheme.textSecondary
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center

        let button = UIButton(type: .system)
        button.accessibilityLabel = "Add Site"
        button.addAction(UIAction { [weak self] _ in
            self?.presentAddSite(categoryID: categoryID)
        }, for: .touchUpInside)

        container.addSubview(iconWell)
        iconWell.addSubview(plus)
        container.addSubview(label)
        container.addSubview(button)

        iconWell.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(iconSize)
        }
        plus.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(iconWell.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(2)
            make.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { $0.edges.equalToSuperview() }
        return container
    }

    private func confirmDeleteCategory(_ category: NavigationCategory) {
        let alert = UIAlertController(
            title: "Delete Group?",
            message: "Remove “\(category.title)” and its sites from Home.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            NavigationStore.shared.deleteCategory(id: category.id)
            self?.buildDirectory()
        })
        present(alert, animated: true)
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
                title: displayTitle,
                urlString: url.absoluteString
            )
            self?.buildDirectory()
        })
        present(alert, animated: true)
    }

    @objc private func enterEditFromPlus() {
        guard !isEditingDirectory else { return }
        isEditingDirectory = true
        editButton.setTitle("Done", for: .normal)
        buildDirectory()
    }

    @objc private func editTapped() {
        isEditingDirectory.toggle()
        editButton.setTitle(isEditingDirectory ? "Done" : "Edit", for: .normal)
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
        if sender.siteIndex > 0 {
            sheet.addAction(UIAlertAction(title: "Move Left", style: .default) { [weak self] _ in
                NavigationStore.shared.moveSite(
                    categoryID: sender.categoryID,
                    from: sender.siteIndex,
                    to: sender.siteIndex - 1
                )
                self?.buildDirectory()
            })
        }
        let count = NavigationStore.shared.categories.first(where: { $0.id == sender.categoryID })?.sites.count ?? 0
        if sender.siteIndex < count - 1 {
            sheet.addAction(UIAlertAction(title: "Move Right", style: .default) { [weak self] _ in
                NavigationStore.shared.moveSite(
                    categoryID: sender.categoryID,
                    from: sender.siteIndex,
                    to: sender.siteIndex + 1
                )
                self?.buildDirectory()
            })
        }
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            NavigationStore.shared.removeSite(categoryID: sender.categoryID, siteID: sender.site.id)
            self?.buildDirectory()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = sender
            pop.sourceRect = sender.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func moveCategoryUp(_ sender: CategoryActionButton) {
        let from = sender.tag
        NavigationStore.shared.moveCategory(from: from, to: from - 1)
        buildDirectory()
    }

    @objc private func moveCategoryDown(_ sender: CategoryActionButton) {
        let from = sender.tag
        NavigationStore.shared.moveCategory(from: from, to: from + 1)
        buildDirectory()
    }
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
