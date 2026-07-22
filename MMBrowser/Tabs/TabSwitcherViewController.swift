import UIKit
import SnapKit

protocol TabSwitcherViewControllerDelegate: AnyObject {
    func tabSwitcherDidClose()
    func tabSwitcherDidRequestNewTab(incognito: Bool)
}

final class TabSwitcherViewController: UIViewController {
    weak var delegate: TabSwitcherViewControllerDelegate?

    private let tabManager: TabManager
    private var showingIncognito = false
    private var collectionView: UICollectionView!
    private let topBar = UIView()
    private let modeControl = UISegmentedControl(items: [" incognito ", " tabs ", " grid "])
    private let doneButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let searchField = UITextField()
    private var searchQuery = ""

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var displayedTabs: [BrowserTab] {
        tabManager.tabs(matching: searchQuery, incognito: showingIncognito)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        setupTop()
        setupCollection()
        setupBottom()
        modeControl.selectedSegmentIndex = 1
        reload()
    }

    private func setupTop() {
        view.addSubview(topBar)
        let search = UIButton(type: .system)
        search.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        search.tintColor = BrowserTheme.textPrimary
        search.addTarget(self, action: #selector(searchPlaceholder), for: .touchUpInside)

        modeControl.selectedSegmentTintColor = UIColor(white: 0.85, alpha: 1)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeControl.setTitleTextAttributes([.foregroundColor: BrowserTheme.textSecondary], for: .normal)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        // Update middle title to count
        modeControl.setTitle(" \(tabManager.tabs.count) ", forSegmentAt: 1)

        let more = UIButton(type: .system)
        more.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        more.tintColor = BrowserTheme.textPrimary

        topBar.addSubview(search)
        topBar.addSubview(modeControl)
        topBar.addSubview(more)
        topBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(48)
        }
        search.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        more.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }
        modeControl.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func setupCollection() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabGridCell.self, forCellWithReuseIdentifier: TabGridCell.reuseID)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-72)
        }
    }

    private func setupBottom() {
        addButton.backgroundColor = BrowserTheme.chromeBlue
        addButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addButton.tintColor = .white
        addButton.layer.cornerRadius = 28
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        doneButton.setTitle("Done", for: .normal)
        doneButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        view.addSubview(addButton)
        view.addSubview(doneButton)
        addButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-12)
            make.size.equalTo(56)
        }
        doneButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-24)
            make.centerY.equalTo(addButton)
        }
    }

    private func reload() {
        modeControl.setTitle(" \(displayedTabs.count) ", forSegmentAt: 1)
        collectionView.reloadData()
    }

    @objc private func modeChanged() {
        showingIncognito = modeControl.selectedSegmentIndex == 0
        reload()
    }

    @objc private func addTapped() {
        delegate?.tabSwitcherDidRequestNewTab(incognito: showingIncognito)
    }

    @objc private func doneTapped() {
        delegate?.tabSwitcherDidClose()
    }

    private func promptMoveGroup(for tab: BrowserTab) {
        let alert = UIAlertController(title: "Move to group", message: tab.title, preferredStyle: .actionSheet)
        for name in tabManager.groupNames {
            alert.addAction(UIAlertAction(title: name, style: .default, handler: { _ in
                self.tabManager.moveTab(tab.id, toGroup: name)
                self.reload()
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func searchPlaceholder() {
        let alert = UIAlertController(title: "Search tabs", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title, URL, or group"; $0.text = self.searchQuery }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Search", style: .default, handler: { _ in
            self.searchQuery = alert.textFields?.first?.text ?? ""
            self.reload()
        }))
        present(alert, animated: true)
    }
}

extension TabSwitcherViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        displayedTabs.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabGridCell.reuseID, for: indexPath) as! TabGridCell
        let tab = displayedTabs[indexPath.item]
        let selected = tab.id == tabManager.selectedTab?.id
        cell.configure(tab: tab, selected: selected)
        cell.onClose = { [weak self] in
            guard let self = self else { return }
            self.tabManager.closeTab(id: tab.id)
            self.reload()
            if self.tabManager.tabs.isEmpty {
                self.delegate?.tabSwitcherDidClose()
            }
        }
        cell.onMoveGroup = { [weak self] in
            self?.promptMoveGroup(for: tab)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tab = displayedTabs[indexPath.item]
        tabManager.selectTab(id: tab.id)
        delegate?.tabSwitcherDidClose()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.bounds.width - 36) / 2
        return CGSize(width: width, height: width * 1.25)
    }
}

final class TabGridCell: UICollectionViewCell {
    static let reuseID = "TabGridCell"
    var onClose: (() -> Void)?
    var onMoveGroup: (() -> Void)?

    private let card = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let preview = UIImageView()
    private let placeholder = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 14
        card.clipsToBounds = true

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = BrowserTheme.textPrimary

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = BrowserTheme.textSecondary
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.backgroundColor = BrowserTheme.elevated

        placeholder.text = "New Tab"
        placeholder.textColor = BrowserTheme.textSecondary
        placeholder.font = .systemFont(ofSize: 14, weight: .medium)
        placeholder.textAlignment = .center

        contentView.addSubview(card)
        card.addSubview(titleLabel)
        card.addSubview(closeButton)
        card.addSubview(preview)
        preview.addSubview(placeholder)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        contentView.addGestureRecognizer(long)

        card.snp.makeConstraints { make in make.edges.equalToSuperview() }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.top.equalToSuperview().offset(10)
            make.trailing.equalTo(closeButton.snp.leading).offset(-6)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-8)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(24)
        }
        preview.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholder.snp.makeConstraints { make in make.center.equalToSuperview() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(tab: BrowserTab, selected: Bool) {
        titleLabel.text = tab.groupName == "Default" ? tab.title : "[\(tab.groupName)] \(tab.title)"
        preview.image = tab.snapshot
        placeholder.isHidden = tab.snapshot != nil
        placeholder.text = tab.isNewTabPage ? "New Tab" : (tab.url?.host ?? "Page")
        card.layer.borderWidth = selected ? 3 : 0
        card.layer.borderColor = BrowserTheme.chromeBlue.cgColor
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { onMoveGroup?() }
    }
}
