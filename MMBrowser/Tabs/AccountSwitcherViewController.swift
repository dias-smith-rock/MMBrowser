import UIKit
import SnapKit

protocol AccountSwitcherViewControllerDelegate: AnyObject {
    func accountSwitcher(_ controller: AccountSwitcherViewController, didSelectAccount id: UUID)
    func accountSwitcherDidRequestManage(_ controller: AccountSwitcherViewController)
    func accountSwitcherDidRequestAddCustom(_ controller: AccountSwitcherViewController)
    func accountSwitcher(_ controller: AccountSwitcherViewController, didRequestAddTemplate template: ContainerTemplate)
    func accountSwitcher(_ controller: AccountSwitcherViewController, didRequestCompare leftID: UUID, rightID: UUID)
}

/// Sheet to switch / manage browsing accounts (containers).
final class AccountSwitcherViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: AccountSwitcherViewControllerDelegate?

    private let tabManager: TabManager
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let actionBar = UIStackView()
    private var items: [BrowserContainer] = []
    private weak var splitViewButton: UIButton?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Accounts"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        configureSheetPresentation()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        // Keep the pinned action bar visible; list scrolls underneath.
        tableView.contentInsetAdjustmentBehavior = .automatic

        actionBar.axis = .vertical
        actionBar.spacing = 8
        actionBar.isLayoutMarginsRelativeArrangement = true
        actionBar.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 12, right: 16)
        actionBar.backgroundColor = BrowserTheme.background

        let topRule = UIView()
        topRule.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.2)
        actionBar.addSubview(topRule)
        topRule.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }

        view.addSubview(tableView)
        view.addSubview(actionBar)
        actionBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        tableView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(actionBar.snp.top)
        }

        rebuildActionBar()
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        reload()
        rebuildActionBar()
        configureSheetPresentation()
    }

    private func configureSheetPresentation() {
        // Presented inside a UINavigationController — configure the nav's sheet.
        let sheet = navigationController?.sheetPresentationController
            ?? sheetPresentationController
        guard let sheet else { return }
        sheet.detents = [.large()]
        sheet.selectedDetentIdentifier = .large
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 16
    }

    private func reload() {
        items = tabManager.sortedContainers
        tableView.reloadData()
        configureSheetPresentation()
    }

    private var comparableAccounts: [BrowserContainer] {
        tabManager.sortedContainers
    }

    private func rebuildActionBar() {
        actionBar.arrangedSubviews.forEach {
            actionBar.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let compare = makeFooterButton(
            title: "Split View",
            action: #selector(compareTapped),
            emphasized: true
        )
        compare.isEnabled = comparableAccounts.count >= 2
        compare.alpha = comparableAccounts.count >= 2 ? 1 : 0.45
        splitViewButton = compare
        actionBar.addArrangedSubview(compare)

        let quickLabel = UILabel()
        quickLabel.text = "Quick add messaging"
        quickLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        quickLabel.textColor = BrowserTheme.textSecondary
        actionBar.addArrangedSubview(quickLabel)

        let templates = ContainerTemplate.quickAddTemplates
        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.spacing = 8
        topRow.distribution = .fillEqually
        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8
        bottomRow.distribution = .fillEqually

        for (index, template) in templates.enumerated() {
            let button = makeFooterButton(
                title: template.displayName,
                action: #selector(quickAddTapped(_:)),
                emphasized: false
            )
            button.tag = template.quickAddTag
            button.accessibilityLabel = "Add \(template.displayName)"
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
            button.snp.remakeConstraints { $0.height.equalTo(44) }
            if index < 2 {
                topRow.addArrangedSubview(button)
            } else {
                bottomRow.addArrangedSubview(button)
            }
        }
        actionBar.addArrangedSubview(topRow)
        actionBar.addArrangedSubview(bottomRow)

        let manage = makeFooterButton(title: "Manage Accounts", action: #selector(manageTapped), emphasized: false)
        let addCustom = makeFooterButton(title: "Add Custom…", action: #selector(addCustomTapped), emphasized: false)
        actionBar.addArrangedSubview(manage)
        actionBar.addArrangedSubview(addCustom)
    }

    private func makeFooterButton(title: String, action: Selector, emphasized: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.snp.makeConstraints { $0.height.equalTo(48) }
        if emphasized {
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = BrowserTheme.chromeBlue
        } else {
            button.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
            button.backgroundColor = BrowserTheme.card
        }
        return button
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func manageTapped() {
        delegate?.accountSwitcherDidRequestManage(self)
    }

    @objc private func addCustomTapped() {
        delegate?.accountSwitcherDidRequestAddCustom(self)
    }

    @objc private func quickAddTapped(_ sender: UIButton) {
        guard let template = ContainerTemplate.fromQuickAddTag(sender.tag) else { return }
        delegate?.accountSwitcher(self, didRequestAddTemplate: template)
    }

    @objc private func compareTapped() {
        let accounts = comparableAccounts
        guard accounts.count >= 2 else { return }

        let currentID = tabManager.selectedTab.flatMap { $0.isIncognito ? nil : $0.containerID }
            ?? tabManager.resolvedLastActiveContainerID
        let left = accounts.first(where: { $0.id == currentID }) ?? accounts[0]
        let others = accounts.filter { $0.id != left.id }

        if others.count == 1 {
            delegate?.accountSwitcher(self, didRequestCompare: left.id, rightID: others[0].id)
            return
        }

        let sheet = UIAlertController(
            title: "Split with…",
            message: "Open “\(left.name)” above another account.",
            preferredStyle: .actionSheet
        )
        for other in others {
            sheet.addAction(UIAlertAction(title: other.name, style: .default) { [weak self] _ in
                guard let self else { return }
                self.delegate?.accountSwitcher(self, didRequestCompare: left.id, rightID: other.id)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = splitViewButton
            pop.sourceRect = splitViewButton?.bounds ?? .zero
        }
        present(sheet, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        comparableAccounts.count >= 2
            ? "Split View opens the current page in two accounts, one above the other."
            : "Add another account to enable Split View."
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
