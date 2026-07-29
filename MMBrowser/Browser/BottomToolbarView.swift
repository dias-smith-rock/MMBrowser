import UIKit
import SnapKit

protocol BottomToolbarViewDelegate: AnyObject {
    func toolbarDidTapBack()
    func toolbarDidTapForward()
    func toolbarDidTapNewTab()
    func toolbarDidTapTabs()
    func toolbarDidTapMenu()
}

final class BottomToolbarView: UIView {
    weak var delegate: BottomToolbarViewDelegate?

    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private let tabsButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let tabsBadgeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BrowserTheme.background

        configure(backButton, systemName: "chevron.left", action: #selector(backTapped))
        configure(forwardButton, systemName: "chevron.right", action: #selector(forwardTapped))
        configure(plusButton, systemName: "plus", action: #selector(plusTapped))
        configure(menuButton, systemName: "ellipsis", action: #selector(menuTapped))

        tabsButton.tintColor = BrowserTheme.textPrimary
        tabsButton.addTarget(self, action: #selector(tabsTapped), for: .touchUpInside)
        tabsBadgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        tabsBadgeLabel.textColor = BrowserTheme.textPrimary
        tabsBadgeLabel.textAlignment = .center
        tabsBadgeLabel.layer.borderColor = BrowserTheme.textPrimary.cgColor
        tabsBadgeLabel.layer.borderWidth = 1.5
        tabsBadgeLabel.layer.cornerRadius = 4
        tabsBadgeLabel.clipsToBounds = true
        tabsButton.addSubview(tabsBadgeLabel)

        let stack = UIStackView(arrangedSubviews: [backButton, forwardButton, plusButton, tabsButton, menuButton])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .center
        addSubview(stack)

        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview()
            make.height.equalTo(BrowserTheme.toolbarHeight)
        }
        tabsBadgeLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.greaterThanOrEqualTo(20)
            make.height.equalTo(18)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(canGoBack: Bool, canGoForward: Bool, tabCount: Int, isPrivate: Bool = false) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        backButton.alpha = canGoBack ? 1 : 0.35
        forwardButton.alpha = canGoForward ? 1 : 0.35
        tabsBadgeLabel.text = "\(min(tabCount, 99))"
        let width = tabCount >= 10 ? 26 : 20
        tabsBadgeLabel.snp.updateConstraints { make in
            make.width.greaterThanOrEqualTo(width)
        }
        setPrivateMode(isPrivate)
    }

    func setPrivateMode(_ isPrivate: Bool) {
        backgroundColor = isPrivate ? BrowserTheme.privateBackground : BrowserTheme.background
        let tint = isPrivate ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        [backButton, forwardButton, plusButton, tabsButton, menuButton].forEach { $0.tintColor = tint }
        tabsBadgeLabel.textColor = tint
        tabsBadgeLabel.layer.borderColor = tint.cgColor
    }

    private func configure(_ button: UIButton, systemName: String, action: Selector) {
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = BrowserTheme.textPrimary
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func backTapped() { delegate?.toolbarDidTapBack() }
    @objc private func forwardTapped() { delegate?.toolbarDidTapForward() }
    @objc private func plusTapped() { delegate?.toolbarDidTapNewTab() }
    @objc private func tabsTapped() { delegate?.toolbarDidTapTabs() }
    @objc private func menuTapped() { delegate?.toolbarDidTapMenu() }
}
