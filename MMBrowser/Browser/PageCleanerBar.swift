import UIKit
import SnapKit

protocol PageCleanerBarDelegate: AnyObject {
    func pageCleanerBar(_ bar: PageCleanerBar, didChangeScopeToURLOnly urlOnly: Bool)
    func pageCleanerBarDidDismiss(_ bar: PageCleanerBar)
}

final class PageCleanerBar: UIView {
    weak var delegate: PageCleanerBarDelegate?

    /// `false` = domain-wide (default); `true` = current URL only.
    private(set) var urlOnly = false

    private let titleLabel = UILabel()
    private let scopeControl = UISegmentedControl(items: ["本站", "仅此页"])
    private let doneButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BrowserTheme.elevated

        titleLabel.text = "清理模式"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        scopeControl.selectedSegmentIndex = 0
        scopeControl.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        if #available(iOS 13.0, *) {
            scopeControl.selectedSegmentTintColor = BrowserTheme.chromeBlue
        }

        doneButton.setTitle("完成", for: .normal)
        doneButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, scopeControl, doneButton])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.distribution = .fill
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12))
        }
        scopeControl.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(140)
            make.height.equalTo(28)
        }
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        scopeControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func scopeChanged() {
        urlOnly = scopeControl.selectedSegmentIndex == 1
        delegate?.pageCleanerBar(self, didChangeScopeToURLOnly: urlOnly)
    }

    @objc private func doneTapped() {
        delegate?.pageCleanerBarDidDismiss(self)
    }
}
