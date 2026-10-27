import UIKit
import SnapKit

/// Readable shield report. Status sits on the trailing edge so labels do not wrap into the value.
final class PrivacyReportViewController: UIViewController {
    var onOpenSettings: (() -> Void)?
    var onOpenExplained: (() -> Void)?

    private let headline: String
    private let rows: [(title: String, detail: String?, value: String, on: Bool)]
    private let footnote: String

    init(headline: String, rows: [(title: String, detail: String?, value: String, on: Bool)], footnote: String) {
        self.headline = headline
        self.rows = rows
        self.footnote = footnote
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy Report"
        BrowserTheme.applyScreenChrome(to: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill

        let headlineLabel = UILabel()
        headlineLabel.text = headline
        headlineLabel.font = .systemFont(ofSize: 22, weight: .bold)
        headlineLabel.textColor = BrowserTheme.textPrimary
        headlineLabel.numberOfLines = 0

        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 14
        card.clipsToBounds = true
        for (index, row) in rows.enumerated() {
            card.addArrangedSubview(makeRow(row, showsSeparator: index < rows.count - 1))
        }

        let footnoteLabel = UILabel()
        footnoteLabel.text = footnote
        footnoteLabel.font = .systemFont(ofSize: 15)
        footnoteLabel.textColor = BrowserTheme.textSecondary
        footnoteLabel.numberOfLines = 0

        let settings = makeButton(title: "Settings", filled: true, action: #selector(settingsTapped))
        let explained = makeButton(title: "Privacy Explained", filled: false, action: #selector(explainedTapped))

        view.addSubview(scroll)
        scroll.addSubview(stack)
        stack.addArrangedSubview(headlineLabel)
        stack.addArrangedSubview(card)
        stack.addArrangedSubview(footnoteLabel)
        stack.addArrangedSubview(settings)
        stack.addArrangedSubview(explained)
        stack.setCustomSpacing(28, after: footnoteLabel)

        scroll.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 20, bottom: 24, right: 20))
            make.width.equalTo(scroll).offset(-40)
        }
        settings.snp.makeConstraints { $0.height.equalTo(48) }
        explained.snp.makeConstraints { $0.height.equalTo(48) }
    }

    private func makeRow(
        _ row: (title: String, detail: String?, value: String, on: Bool),
        showsSeparator: Bool
    ) -> UIView {
        let wrap = UIView()
        let title = UILabel()
        title.text = row.title
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = BrowserTheme.textPrimary
        title.numberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let value = UILabel()
        value.text = row.value
        value.font = .systemFont(ofSize: 17, weight: .semibold)
        value.textColor = row.on ? BrowserTheme.chromeBlue : BrowserTheme.textSecondary
        value.textAlignment = .right
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        value.setContentHuggingPriority(.required, for: .horizontal)

        wrap.addSubview(title)
        wrap.addSubview(value)

        if let detailText = row.detail, !detailText.isEmpty {
            let detail = UILabel()
            detail.text = detailText
            detail.font = .systemFont(ofSize: 13)
            detail.textColor = BrowserTheme.textSecondary
            detail.numberOfLines = 2
            wrap.addSubview(detail)
            title.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(12)
                make.leading.equalToSuperview().offset(16)
                make.trailing.lessThanOrEqualTo(value.snp.leading).offset(-12)
            }
            value.snp.makeConstraints { make in
                make.centerY.equalTo(title)
                make.trailing.equalToSuperview().offset(-16)
            }
            detail.snp.makeConstraints { make in
                make.top.equalTo(title.snp.bottom).offset(2)
                make.leading.equalTo(title)
                make.trailing.equalToSuperview().offset(-16)
                make.bottom.equalToSuperview().offset(-12)
            }
        } else {
            title.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview().inset(14)
                make.leading.equalToSuperview().offset(16)
                make.trailing.lessThanOrEqualTo(value.snp.leading).offset(-12)
            }
            value.snp.makeConstraints { make in
                make.centerY.equalToSuperview()
                make.trailing.equalToSuperview().offset(-16)
            }
        }

        if showsSeparator {
            let line = UIView()
            line.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.2)
            wrap.addSubview(line)
            line.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(16)
                make.trailing.bottom.equalToSuperview()
                make.height.equalTo(1.0 / UIScreen.main.scale)
            }
        }
        return wrap
    }

    private func makeButton(title: String, filled: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.layer.cornerRadius = 12
        if filled {
            button.backgroundColor = BrowserTheme.chromeBlue
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = BrowserTheme.card
            button.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        }
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func settingsTapped() {
        let open = onOpenSettings
        dismiss(animated: true) { open?() }
    }

    @objc private func explainedTapped() {
        let open = onOpenExplained
        dismiss(animated: true) { open?() }
    }
}
