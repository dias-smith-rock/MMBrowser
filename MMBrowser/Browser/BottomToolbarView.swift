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
    private var isPrivateMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure(backButton, action: #selector(backTapped))
        configure(forwardButton, action: #selector(forwardTapped))
        configure(plusButton, action: #selector(plusTapped))
        configure(menuButton, action: #selector(menuTapped))

        tabsButton.addTarget(self, action: #selector(tabsTapped), for: .touchUpInside)
        tabsBadgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        tabsBadgeLabel.textAlignment = .center
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

        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

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
        isPrivateMode = isPrivate
        applyTheme()
    }

    @objc private func applyTheme() {
        backgroundColor = isPrivateMode ? BrowserTheme.privateBackground : BrowserTheme.background
        let tint = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        backButton.setImage(ThemeManager.shared.image(for: .toolbarBack), for: .normal)
        forwardButton.setImage(ThemeManager.shared.image(for: .toolbarForward), for: .normal)
        plusButton.setImage(ThemeManager.shared.image(for: .toolbarNewTab), for: .normal)
        menuButton.setImage(ThemeManager.shared.image(for: .toolbarMenu), for: .normal)
        [backButton, forwardButton, plusButton, tabsButton, menuButton].forEach { $0.tintColor = tint }
        tabsBadgeLabel.textColor = tint
        tabsBadgeLabel.layer.borderColor = tint.cgColor
    }

    private func configure(_ button: UIButton, action: Selector) {
        button.tintColor = BrowserTheme.textPrimary
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func backTapped() { delegate?.toolbarDidTapBack() }
    @objc private func forwardTapped() { delegate?.toolbarDidTapForward() }
    @objc private func plusTapped() { delegate?.toolbarDidTapNewTab() }
    @objc private func tabsTapped() { delegate?.toolbarDidTapTabs() }
    @objc private func menuTapped() { delegate?.toolbarDidTapMenu() }
}
