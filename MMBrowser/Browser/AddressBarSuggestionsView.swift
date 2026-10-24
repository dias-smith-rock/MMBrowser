import UIKit
import SnapKit

protocol AddressBarSuggestionsViewDelegate: AnyObject {
    func addressBarSuggestions(_ view: AddressBarSuggestionsView, didSelect item: HistoryItem)
}

/// Floating list under the address bar for recent / matching visits.
final class AddressBarSuggestionsView: UIView, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: AddressBarSuggestionsViewDelegate?

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [HistoryItem] = []
    private var heightConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BrowserTheme.elevated
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor
        clipsToBounds = true
        isHidden = true

        tableView.backgroundColor = .clear
        tableView.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.22)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 52, bottom: 0, right: 12)
        tableView.rowHeight = 52
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .none
        tableView.register(SuggestionCell.self, forCellReuseIdentifier: SuggestionCell.reuseID)
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        snp.makeConstraints { make in
            heightConstraint = make.height.equalTo(0).constraint
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: .themeDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        backgroundColor = BrowserTheme.elevated
        layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor
        tableView.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.22)
        tableView.reloadData()
    }

    func show(_ suggestions: [HistoryItem]) {
        items = suggestions
        tableView.reloadData()
        let height = CGFloat(items.count) * tableView.rowHeight
        heightConstraint?.update(offset: height)
        isHidden = items.isEmpty
        alpha = items.isEmpty ? 0 : 1
    }

    func hide() {
        items = []
        tableView.reloadData()
        heightConstraint?.update(offset: 0)
        isHidden = true
        alpha = 0
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SuggestionCell.reuseID, for: indexPath) as! SuggestionCell
        cell.configure(items[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        delegate?.addressBarSuggestions(self, didSelect: items[indexPath.row])
    }
}

private final class SuggestionCell: UITableViewCell {
    static let reuseID = "AddressBarSuggestionCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = BrowserTheme.textSecondary

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = BrowserTheme.textSecondary
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        contentView.addSubview(iconView)
        contentView.addSubview(textStack)

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(12)
            make.trailing.equalToSuperview().inset(14)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: HistoryItem) {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = UIImage(systemName: "clock.arrow.circlepath", withConfiguration: config)
        titleLabel.text = item.title
        subtitleLabel.text = item.url?.host ?? item.urlString
        titleLabel.textColor = BrowserTheme.textPrimary
        subtitleLabel.textColor = BrowserTheme.textSecondary
        iconView.tintColor = BrowserTheme.textSecondary
        selectedBackgroundView = {
            let v = UIView()
            v.backgroundColor = BrowserTheme.secondaryCard
            return v
        }()
    }
}
