import UIKit
import SnapKit

final class PageCleanerRulesViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [(host: String, rules: [PageCleanerRule])] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Webpage Cleaner"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 152
        tableView.register(PageCleanerRuleCell.self, forCellReuseIdentifier: PageCleanerRuleCell.reuseID)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadData),
            name: .pageCleanerRulesChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeChanged),
            name: .themeDidChange,
            object: nil
        )
        reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
    }

    @objc private func themeChanged() {
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
    }

    @objc private func reloadData() {
        sections = PageCleanerStore.shared.groupedByHost()
        tableView.reloadData()
        navigationItem.rightBarButtonItem = sections.isEmpty
            ? nil
            : UIBarButtonItem(title: "Clear All", style: .plain, target: self, action: #selector(clearAll))
    }

    @objc private func clearAll() {
        let alert = UIAlertController(
            title: "Clear all cleaner rules?",
            message: "Hidden elements will show again after pages reload.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            PageCleanerStore.shared.removeAll()
        })
        present(alert, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        max(sections.count, 1)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if sections.isEmpty { return 1 }
        return sections[section].rules.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if sections.isEmpty { return nil }
        return sections[section].host
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sections.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "empty")
                ?? UITableViewCell(style: .subtitle, reuseIdentifier: "empty")
            BrowserTheme.styleListCell(cell)
            cell.selectionStyle = .none
            cell.accessoryType = .none
            cell.imageView?.image = nil
            cell.textLabel?.numberOfLines = 0
            cell.textLabel?.text = "No rules yet"
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.text = "Tap the wand icon, then pick This site or This page"
            return cell
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: PageCleanerRuleCell.reuseID,
            for: indexPath
        ) as! PageCleanerRuleCell
        cell.apply(rule: sections[indexPath.section].rules[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !sections.isEmpty else { return }
        let rule = sections[indexPath.section].rules[indexPath.row]
        guard let image = rule.previewImage else { return }
        let preview = PageCleanerPreviewViewController(image: image, titleText: rule.label)
        let nav = UINavigationController(rootViewController: preview)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        !sections.isEmpty
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, !sections.isEmpty else { return }
        let rule = sections[indexPath.section].rules[indexPath.row]
        PageCleanerStore.shared.remove(id: rule.id)
    }
}

private final class PageCleanerRuleCell: UITableViewCell {
    static let reuseID = "PageCleanerRuleCell"

    private let previewView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let placeholderIcon = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        backgroundColor = BrowserTheme.card

        previewView.contentMode = .scaleAspectFit
        previewView.clipsToBounds = true
        previewView.layer.cornerRadius = 10
        previewView.backgroundColor = BrowserTheme.secondaryCard

        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.tintColor = BrowserTheme.textSecondary
        placeholderIcon.image = UIImage(systemName: "eye.slash")

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 2

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = BrowserTheme.textSecondary
        detailLabel.numberOfLines = 2

        contentView.addSubview(previewView)
        previewView.addSubview(placeholderIcon)
        contentView.addSubview(titleLabel)
        contentView.addSubview(detailLabel)

        // Phone-viewport thumbnail: show the full screenshot without cropping.
        previewView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
            make.width.equalTo(72)
            make.height.equalTo(128)
        }
        placeholderIcon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(28)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(previewView.snp.trailing).offset(12)
            make.trailing.equalToSuperview().offset(-14)
            make.top.equalTo(previewView.snp.top).offset(6)
        }
        detailLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.bottom.lessThanOrEqualTo(previewView.snp.bottom).offset(-2)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(rule: PageCleanerRule) {
        backgroundColor = BrowserTheme.card
        titleLabel.textColor = BrowserTheme.textPrimary
        detailLabel.textColor = BrowserTheme.textSecondary
        previewView.backgroundColor = BrowserTheme.secondaryCard
        placeholderIcon.tintColor = BrowserTheme.textSecondary

        titleLabel.text = rule.label
        if let urlString = rule.urlString {
            detailLabel.text = "This page · \(urlString)"
        } else {
            detailLabel.text = "Entire site"
        }

        if let image = rule.previewImage {
            previewView.image = image
            placeholderIcon.isHidden = true
            accessoryType = .disclosureIndicator
            selectionStyle = .default
        } else {
            previewView.image = nil
            placeholderIcon.isHidden = false
            accessoryType = .none
            selectionStyle = .none
        }
    }
}

private final class PageCleanerPreviewViewController: UIViewController {
    private let image: UIImage
    private let titleText: String
    private let imageView = UIImageView()

    init(image: UIImage, titleText: String) {
        self.image = image
        self.titleText = titleText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = titleText
        BrowserTheme.applyScreenChrome(to: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 12
        imageView.clipsToBounds = true
        scroll.addSubview(imageView)

        let caption = UILabel()
        caption.text = "Red mark shows the element that was hidden."
        caption.textColor = BrowserTheme.textSecondary
        caption.font = .systemFont(ofSize: 13)
        caption.textAlignment = .center
        caption.numberOfLines = 0
        scroll.addSubview(caption)

        let ratio = image.size.height / max(image.size.width, 1)
        imageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.leading.trailing.equalTo(scroll.frameLayoutGuide).inset(16)
            make.width.equalTo(scroll.frameLayoutGuide).offset(-32)
            make.height.equalTo(imageView.snp.width).multipliedBy(ratio)
        }
        caption.snp.makeConstraints { make in
            make.top.equalTo(imageView.snp.bottom).offset(12)
            make.leading.trailing.equalTo(imageView)
            make.bottom.equalToSuperview().offset(-24)
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
