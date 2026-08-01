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
    private var canGoBack = false
    private var canGoForward = false
    private var tabCount = 1

    private static let iconPointSize: CGFloat = 26
    private static let iconConfig = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)

    override init(frame: CGRect) {
        super.init(frame: frame)

        configure(backButton, action: #selector(backTapped), label: "Back")
        configure(forwardButton, action: #selector(forwardTapped), label: "Forward")
        configure(plusButton, action: #selector(plusTapped), label: "New Tab")
        configure(tabsButton, action: #selector(tabsTapped), label: "Tabs")
        configure(menuButton, action: #selector(menuTapped), label: "Menu")

        tabsBadgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        tabsBadgeLabel.textAlignment = .center
        tabsBadgeLabel.textColor = .white
        tabsBadgeLabel.backgroundColor = BrowserTheme.chromeBlue
        tabsBadgeLabel.layer.cornerRadius = 7
        tabsBadgeLabel.clipsToBounds = true
        tabsBadgeLabel.isUserInteractionEnabled = false
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
            make.centerX.equalTo(tabsButton.snp.centerX).offset(10)
            make.centerY.equalTo(tabsButton.snp.centerY).offset(-10)
            make.height.equalTo(14)
            make.width.greaterThanOrEqualTo(14)
        }

        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    required init?(coder: NSCoder) { fatalError() }

    func update(canGoBack: Bool, canGoForward: Bool, tabCount: Int, isPrivate: Bool = false) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.tabCount = max(tabCount, 1)
        tabsBadgeLabel.text = " \(min(self.tabCount, 99)) "
        tabsBadgeLabel.snp.updateConstraints { make in
            make.width.greaterThanOrEqualTo(self.tabCount >= 10 ? 20 : 14)
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
        let config = Self.iconConfig
        let size = Self.iconPointSize

        backButton.setImage(ThemeManager.shared.image(for: .toolbarBack, configuration: config, pointSize: size), for: .normal)
        forwardButton.setImage(ThemeManager.shared.image(for: .toolbarForward, configuration: config, pointSize: size), for: .normal)
        plusButton.setImage(ThemeManager.shared.image(for: .toolbarNewTab, configuration: config, pointSize: size), for: .normal)
        tabsButton.setImage(ThemeManager.shared.image(for: .toolbarTabs, configuration: config, pointSize: size), for: .normal)
        menuButton.setImage(ThemeManager.shared.image(for: .toolbarMenu, configuration: config, pointSize: size), for: .normal)

        [backButton, forwardButton, plusButton, tabsButton, menuButton].forEach { button in
            button.tintColor = tint
            button.imageView?.contentMode = .scaleAspectFit
            button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        }

        tabsBadgeLabel.backgroundColor = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        tabsBadgeLabel.textColor = isPrivateMode ? BrowserTheme.privateBackground : .black
        tabsBadgeLabel.isHidden = false
        applyNavigationEnabledState()
    }

    /// Soften unavailable back/forward without UIButton's disabled gray (keeps theme tint).
    private func applyNavigationEnabledState() {
        backButton.isEnabled = true
        forwardButton.isEnabled = true
        backButton.isUserInteractionEnabled = canGoBack
        forwardButton.isUserInteractionEnabled = canGoForward
        let disabledAlpha: CGFloat = ThemeManager.shared.current.isLight ? 0.4 : 0.35
        backButton.alpha = canGoBack ? 1 : disabledAlpha
        forwardButton.alpha = canGoForward ? 1 : disabledAlpha
    }

    private func configure(_ button: UIButton, action: Selector, label: String) {
        button.tintColor = BrowserTheme.textPrimary
        button.accessibilityLabel = label
        button.setPreferredSymbolConfiguration(Self.iconConfig, forImageIn: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func backTapped() { delegate?.toolbarDidTapBack() }
    @objc private func forwardTapped() { delegate?.toolbarDidTapForward() }
    @objc private func plusTapped() { delegate?.toolbarDidTapNewTab() }
    @objc private func tabsTapped() { delegate?.toolbarDidTapTabs() }
    @objc private func menuTapped() { delegate?.toolbarDidTapMenu() }
}
