import UIKit
import SnapKit

/// Shield sheet for the current page. Counts are only shown when the app actually measured them.
final class PrivacyReportViewController: UIViewController {
    var onBlockingSettings: (() -> Void)?
    var onErase: (() -> Void)?
    var onClearSite: (() -> Void)?
    var onTurnOnBlocking: (() -> Void)?
    var onPageBlockingChanged: ((Bool) -> Void)?

    private let protectionOn: Bool
    private let blockedCount: Int?
    private let countIsMeasured: Bool
    private let pageHost: String?
    private let pageBlockingOn: Bool

    init(protectionOn: Bool, blockedCount: Int?, countIsMeasured: Bool, pageHost: String?, pageBlockingOn: Bool) {
        self.protectionOn = protectionOn
        self.blockedCount = blockedCount
        self.countIsMeasured = countIsMeasured
        self.pageHost = pageHost
        self.pageBlockingOn = pageBlockingOn
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy report"
        BrowserTheme.applyScreenChrome(to: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))

        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        view.addSubview(scroll)
        scroll.addSubview(stack)
        scroll.snp.makeConstraints { $0.edges.equalTo(view.safeAreaLayoutGuide) }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 20, bottom: 24, right: 20))
            make.width.equalTo(scroll).offset(-40)
        }

        let subtitle = UILabel()
        subtitle.numberOfLines = 0
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = BrowserTheme.textSecondary
        subtitle.text = protectionOn
            ? "What XBrowser blocked on this page"
            : "Blocking is off for this page. Turn it on to reduce trackers and ads."
        stack.addArrangedSubview(subtitle)

        if protectionOn {
            stack.addArrangedSubview(statCard())
            if let blockedCount, countIsMeasured, blockedCount > 0 {
                stack.addArrangedSubview(categoryCard(count: blockedCount))
            }
        } else {
            stack.addArrangedSubview(linkButton("Turn on blocking", action: #selector(turnOnTapped)))
        }

        if pageHost != nil {
            stack.addArrangedSubview(toggleCard())
        }
        stack.addArrangedSubview(linkButton("Blocking settings", action: #selector(settingsTapped)))
        stack.addArrangedSubview(linkButton("Erase browsing data…", action: #selector(eraseTapped)))
        if pageHost != nil {
            stack.addArrangedSubview(linkButton("Clear data for this site", action: #selector(clearSiteTapped)))
        }

        let footer = UILabel()
        footer.numberOfLines = 0
        footer.font = .systemFont(ofSize: 13)
        footer.textColor = BrowserTheme.textSecondary
        footer.text = "Blocking reduces many ads and trackers. It does not change your IP or make you anonymous."
        stack.addArrangedSubview(footer)
    }

    private func statCard() -> UIView {
        let value: String
        let detail: String
        if countIsMeasured, let blockedCount {
            value = "\(blockedCount)"
            detail = "Hidden page elements"
        } else {
            value = "—"
            detail = "Network blocks aren’t counted on this page"
        }
        return labeledCard(title: "Blocked requests", value: value, detail: detail)
    }

    private func categoryCard(count: Int) -> UIView {
        labeledCard(title: "Categories", value: "Ads \(count)", detail: nil)
    }

    private func labeledCard(title: String, value: String, detail: String?) -> UIView {
        let box = UIView()
        box.backgroundColor = BrowserTheme.card
        box.layer.cornerRadius = 14
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textSecondary
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = BrowserTheme.textPrimary
        valueLabel.numberOfLines = 0
        box.addSubview(titleLabel)
        box.addSubview(valueLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }
        if let detail {
            let detailLabel = UILabel()
            detailLabel.text = detail
            detailLabel.font = .systemFont(ofSize: 13)
            detailLabel.textColor = BrowserTheme.textSecondary
            detailLabel.numberOfLines = 0
            box.addSubview(detailLabel)
            valueLabel.snp.makeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(4)
                make.leading.trailing.equalToSuperview().inset(16)
            }
            detailLabel.snp.makeConstraints { make in
                make.top.equalTo(valueLabel.snp.bottom).offset(2)
                make.leading.trailing.bottom.equalToSuperview().inset(16)
            }
        } else {
            valueLabel.snp.makeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(4)
                make.leading.trailing.bottom.equalToSuperview().inset(16)
            }
        }
        return box
    }

    private func toggleCard() -> UIView {
        let box = UIView()
        box.backgroundColor = BrowserTheme.card
        box.layer.cornerRadius = 14
        let label = UILabel()
        label.text = "Block ads & trackers on this page"
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = BrowserTheme.textPrimary
        label.numberOfLines = 0
        let toggle = UISwitch()
        toggle.isOn = pageBlockingOn
        toggle.addTarget(self, action: #selector(pageToggleChanged(_:)), for: .valueChanged)
        box.addSubview(label)
        box.addSubview(toggle)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.trailing.lessThanOrEqualTo(toggle.snp.leading).offset(-12)
            make.top.bottom.equalToSuperview().inset(14)
        }
        toggle.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }
        return box
    }

    private func linkButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        button.snp.makeConstraints { $0.height.equalTo(44) }
        return button
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func settingsTapped() {
        let open = onBlockingSettings
        dismiss(animated: true) { open?() }
    }

    @objc private func eraseTapped() {
        let open = onErase
        dismiss(animated: true) { open?() }
    }

    @objc private func clearSiteTapped() {
        let open = onClearSite
        dismiss(animated: true) { open?() }
    }

    @objc private func turnOnTapped() {
        let open = onTurnOnBlocking
        dismiss(animated: true) { open?() }
    }

    @objc private func pageToggleChanged(_ toggle: UISwitch) {
        onPageBlockingChanged?(toggle.isOn)
    }
}
