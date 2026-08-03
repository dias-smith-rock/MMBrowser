import UIKit
import SnapKit

protocol AccountSwitcherViewControllerDelegate: AnyObject {
    func accountSwitcher(_ controller: AccountSwitcherViewController, didSelectAccount id: UUID)
    func accountSwitcherDidRequestManage(_ controller: AccountSwitcherViewController)
    func accountSwitcherDidRequestAdd(_ controller: AccountSwitcherViewController)
}

/// Medium sheet to switch / manage browsing accounts (containers).
final class AccountSwitcherViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: AccountSwitcherViewControllerDelegate?

    private let tabManager: TabManager
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var items: [BrowserContainer] = []

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Accounts"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let footer = UIStackView()
        footer.axis = .vertical
        footer.spacing = 8
        footer.isLayoutMarginsRelativeArrangement = true
        footer.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)

        let manage = makeFooterButton(title: "Manage Accounts", action: #selector(manageTapped))
        let add = makeFooterButton(title: "Add Account", action: #selector(addTapped))
        footer.addArrangedSubview(manage)
        footer.addArrangedSubview(add)
        let wrap = UIView()
        wrap.addSubview(footer)
        footer.snp.makeConstraints { $0.edges.equalToSuperview() }
        wrap.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 120)
        tableView.tableFooterView = wrap

        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        reload()
    }

    private func reload() {
        items = tabManager.sortedContainers
        tableView.reloadData()
    }

    private func makeFooterButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = BrowserTheme.card
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.snp.makeConstraints { $0.height.equalTo(48) }
        return button
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func manageTapped() {
        delegate?.accountSwitcherDidRequestManage(self)
    }

    @objc private func addTapped() {
        delegate?.accountSwitcherDidRequestAdd(self)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        BrowserTheme.styleListCell(cell)
        let item = items[indexPath.row]
        let count = tabManager.normalTabs.filter { $0.containerID == item.id }.count
        let tabsText = count == 0 ? "No tabs" : (count == 1 ? "1 tab" : "\(count) tabs")
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = "\(tabsText) · \(item.locationSummary)"

        let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        dot.backgroundColor = AccountColor.color(for: item)
        dot.layer.cornerRadius = 5
        let wrap = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        wrap.addSubview(dot)
        dot.center = CGPoint(x: 9, y: 9)
        cell.accessoryView = wrap

        let currentID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        if item.id == currentID {
            cell.backgroundColor = AccountColor.color(for: item).withAlphaComponent(0.12)
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = BrowserTheme.chromeBlue
            let checkWrap = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 22))
            check.frame = CGRect(x: 14, y: 2, width: 18, height: 18)
            checkWrap.addSubview(check)
            let stack = UIView(frame: CGRect(x: 0, y: 0, width: 56, height: 22))
            wrap.frame.origin = .zero
            checkWrap.frame.origin = CGPoint(x: 20, y: 0)
            stack.addSubview(wrap)
            stack.addSubview(checkWrap)
            cell.accessoryView = stack
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let id = items[indexPath.row].id
        delegate?.accountSwitcher(self, didSelectAccount: id)
    }
}
