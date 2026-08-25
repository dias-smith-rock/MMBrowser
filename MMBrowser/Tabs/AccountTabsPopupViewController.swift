import UIKit
import SnapKit

protocol AccountTabsPopupDelegate: AnyObject {
    func accountTabsPopupDidRequestClose()
    func accountTabsPopupDidSelectTab()
    func accountTabsPopupDidRequestNewTab(containerID: UUID)
    func accountTabsPopupDidChangeAccounts()
}

/// Modal sheet showing tabs for a single account (Work / Personal / …).
final class AccountTabsPopupViewController: UIViewController {
    weak var delegate: AccountTabsPopupDelegate?

    private let tabManager: TabManager
    private let containerID: UUID

    private let header = UIView()
    private let dot = UIView()
    private let titleLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var collectionView: UICollectionView!
    private let addButton = UIButton(type: .system)

    init(tabManager: TabManager, containerID: UUID) {
        self.tabManager = tabManager
        self.containerID = containerID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var displayedTabs: [BrowserTab] {
        tabManager.normalTabs.filter { $0.containerID == containerID }
    }

    private var accountColor: UIColor {
        tabManager.accountColor(forContainer: containerID)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        setupHeader()
        setupCollection()
        setupAdd()
        reload()
    }

    func reloadPreviews() {
        guard isViewLoaded else { return }
        collectionView.reloadData()
    }

    private func setupHeader() {
        header.backgroundColor = BrowserTheme.card
        header.layer.cornerRadius = 18
        header.clipsToBounds = true

        dot.layer.cornerRadius = 5
        dot.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = BrowserTheme.textPrimary
        moreButton.accessibilityLabel = "More"
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = BrowserTheme.textSecondary
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        view.addSubview(header)
        header.addSubview(dot)
        header.addSubview(titleLabel)
        header.addSubview(moreButton)
        header.addSubview(closeButton)

        header.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(12)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.height.equalTo(56)
        }
        dot.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(10)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(dot.snp.trailing).offset(10)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-8)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
        moreButton.snp.makeConstraints { make in
            make.trailing.equalTo(closeButton.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
            make.size.equalTo(32)
        }
    }

    private func setupCollection() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 80, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.register(TabGridCell.self, forCellWithReuseIdentifier: TabGridCell.reuseID)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func setupAdd() {
        addButton.backgroundColor = BrowserTheme.chromeBlue
        addButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addButton.tintColor = .white
        addButton.layer.cornerRadius = 28
        addButton.accessibilityLabel = "New Tab"
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        view.addSubview(addButton)
        addButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-12)
            make.size.equalTo(56)
        }
    }

    private func reload() {
        if let container = tabManager.container(id: containerID) {
            titleLabel.text = container.name
            dot.backgroundColor = accountColor
            addButton.backgroundColor = accountColor
        }
        moreButton.menu = makeMoreMenu()
        collectionView.reloadData()
    }

    private func makeMoreMenu() -> UIMenu {
        let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.promptRename()
        }
        let manage = UIAction(title: "Manage Accounts", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
            self?.presentManageAccounts()
        }
        let closeAll = UIAction(
            title: "Close All",
            image: UIImage(systemName: "xmark.circle"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.closeAllTabs()
        }
        let deleteGroup = UIAction(
            title: "Delete Account",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDelete()
        }
        return UIMenu(title: "", children: [rename, manage, closeAll, deleteGroup])
    }

    @objc private func closeTapped() {
        delegate?.accountTabsPopupDidRequestClose()
    }

    @objc private func addTapped() {
        delegate?.accountTabsPopupDidRequestNewTab(containerID: containerID)
    }

    private func promptRename() {
        guard let container = tabManager.container(id: containerID) else { return }
        let alert = UIAlertController(title: "Rename Account", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = container.name; $0.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?.first?.text ?? ""
            if self.tabManager.renameContainer(id: container.id, to: name) {
                self.reload()
                self.delegate?.accountTabsPopupDidChangeAccounts()
            } else {
                let err = UIAlertController(
                    title: "Accounts",
                    message: "Couldn’t rename. Use a unique non-empty name.",
                    preferredStyle: .alert
                )
                err.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(err, animated: true)
            }
        }))
        present(alert, animated: true)
    }

    private func presentManageAccounts() {
        let vc = ContainerManageViewController(tabManager: tabManager)
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func closeAllTabs() {
        for tab in displayedTabs {
            tabManager.closeTab(id: tab.id)
        }
        reload()
        delegate?.accountTabsPopupDidChangeAccounts()
    }

    private func confirmDelete() {
        guard let container = tabManager.container(id: containerID) else { return }
        guard tabManager.containers.count > 1 else {
            let alert = UIAlertController(title: "Accounts", message: "Keep at least one account.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Delete Account?",
            message: "Tabs in “\(container.name)” will move to another account. Their login session for this account will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            _ = self.tabManager.deleteContainer(id: container.id)
            self.delegate?.accountTabsPopupDidChangeAccounts()
            self.delegate?.accountTabsPopupDidRequestClose()
        }))
        present(alert, animated: true)
    }

    private func promptMoveGroup(for tab: BrowserTab) {
        let alert = UIAlertController(title: "Move to Account", message: tab.title, preferredStyle: .actionSheet)
        for container in tabManager.sortedContainers {
            let title = container.id == tab.containerID ? "\(container.name) ✓" : container.name
            alert.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in
                self?.confirmMove(tab: tab, to: container)
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: 80, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func confirmMove(tab: BrowserTab, to container: BrowserContainer) {
        if tab.containerID == container.id { return }
        let alert = UIAlertController(
            title: "Move to “\(container.name)”?",
            message: "This tab will use that account’s cookies and login. It may look logged out of the previous account.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Move", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.tabManager.moveTab(tab.id, toContainer: container.id)
            self.reload()
            self.delegate?.accountTabsPopupDidChangeAccounts()
        }))
        present(alert, animated: true)
    }
}

extension AccountTabsPopupViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        displayedTabs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabGridCell.reuseID, for: indexPath) as! TabGridCell
        let tab = displayedTabs[indexPath.item]
        cell.configure(
            tab: tab,
            containerName: tabManager.containerName(for: tab),
            accountColor: tabManager.accountColor(for: tab),
            selected: tab.id == tabManager.selectedTab?.id
        )
        cell.onClose = { [weak self] in
            guard let self else { return }
            self.tabManager.closeTab(id: tab.id)
            self.reload()
            self.delegate?.accountTabsPopupDidChangeAccounts()
        }
        cell.onMoveGroup = { [weak self] in
            self?.promptMoveGroup(for: tab)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tab = displayedTabs[indexPath.item]
        tabManager.selectTab(id: tab.id)
        delegate?.accountTabsPopupDidSelectTab()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = (collectionView.bounds.width - 36) / 2
        return CGSize(width: width, height: width * 1.25)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let tab = displayedTabs[indexPath.item]
        return UIContextMenuConfiguration(identifier: tab.id.uuidString as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let moveChildren = self.tabManager.sortedContainers.map { container in
                let checked = container.id == tab.containerID
                return UIAction(
                    title: container.name,
                    image: UIImage(systemName: checked ? "checkmark.circle.fill" : "circle"),
                    state: checked ? .on : .off
                ) { [weak self] _ in
                    self?.confirmMove(tab: tab, to: container)
                }
            }
            return UIMenu(title: "", children: [
                UIMenu(title: "Move to Account", options: .displayInline, children: moveChildren)
            ])
        }
    }
}

extension AccountTabsPopupViewController: ContainerManageViewControllerDelegate {
    func containerManageDidChange() {
        if tabManager.container(id: containerID) == nil {
            delegate?.accountTabsPopupDidChangeAccounts()
            delegate?.accountTabsPopupDidRequestClose()
            return
        }
        reload()
        delegate?.accountTabsPopupDidChangeAccounts()
    }
}
