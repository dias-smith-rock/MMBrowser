import UIKit
import SnapKit

protocol BottomToolbarViewDelegate: AnyObject {
    func toolbarDidTapBack()
    func toolbarDidTapForward()
    func toolbarDidTapHome()
    func toolbarDidTapNewTab()
    func toolbarDidTapTabs()
    func toolbarDidTapMenu()
    func toolbarDidTapDownloads()
    func toolbarDidTapAccount()
    func toolbarDidLongPressAccount()
}

/// Icon row under the address field — sits on the shared chrome card surface.
final class BottomToolbarView: UIView {
    weak var delegate: BottomToolbarViewDelegate?

    private let backButton = UIButton(type: .system)
    private let homeButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let downloadsButton = UIButton(type: .system)
    private let tabsButton = UIButton(type: .system)
    private let tabsGlyph = UIView()
    private let tabsCountLabel = UILabel()
    private let iconStack = UIStackView()
    private var isPrivateMode = false
    private var canGoBack = false
    private var tabCount = 1
    private var spaceTintColor: UIColor?

    private static let iconPointSize: CGFloat = 20
    private static let iconConfig = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: BrowserTheme.toolbarHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        configure(backButton, action: #selector(backTapped), label: "Back")
        configure(homeButton, action: #selector(homeTapped), label: "Home")
        configure(menuButton, action: #selector(menuTapped), label: "Menu")
        configure(downloadsButton, action: #selector(downloadsTapped), label: "Downloads")
        configure(tabsButton, action: #selector(tabsTapped), label: "Tabs")

        tabsGlyph.isUserInteractionEnabled = false
        tabsGlyph.layer.borderWidth = 1.6
        tabsGlyph.layer.cornerRadius = 5
        tabsGlyph.layer.cornerCurve = .continuous
        tabsCountLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        tabsCountLabel.textAlignment = .center
        tabsCountLabel.isUserInteractionEnabled = false
        tabsButton.addSubview(tabsGlyph)
        tabsGlyph.addSubview(tabsCountLabel)
        tabsGlyph.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(22)
            make.height.equalTo(20)
        }
        tabsCountLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconStack.axis = .horizontal
        iconStack.distribution = .fillEqually
        iconStack.alignment = .center
        [backButton, homeButton, menuButton, downloadsButton, tabsButton].forEach {
            iconStack.addArrangedSubview($0)
        }
        addSubview(iconStack)
        iconStack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(4)
            make.top.bottom.equalToSuperview()
        }

        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    required init?(coder: NSCoder) { fatalError() }

    func update(
        canGoBack: Bool,
        canGoForward: Bool,
        tabCount: Int,
        isPrivate: Bool = false,
        hidesNavigationButtons: Bool = false
    ) {
        _ = hidesNavigationButtons
        _ = canGoForward
        self.canGoBack = canGoBack
        self.tabCount = max(tabCount, 1)
        tabsCountLabel.text = "\(min(self.tabCount, 99))"
        setPrivateMode(isPrivate)
        applyNavigationEnabledState()
    }

    func setPrivateMode(_ isPrivate: Bool) {
        isPrivateMode = isPrivate
        applyTheme()
    }

    func setSpaceChrome(_ color: UIColor?) {
        spaceTintColor = color
        applyTheme()
    }

    func setAccount(name: String, color: UIColor, visible: Bool) {
        _ = name
        _ = visible
        spaceTintColor = isPrivateMode ? nil : color
        applyTheme()
    }

    func pulseAccountChip() {}

    @objc private func applyTheme() {
        backgroundColor = .clear
        let tint = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        let config = Self.iconConfig
        let size = Self.iconPointSize

        backButton.setImage(ThemeManager.shared.image(for: .toolbarBack, configuration: config, pointSize: size), for: .normal)
        homeButton.setImage(UIImage(systemName: "house", withConfiguration: config), for: .normal)
        menuButton.setImage(UIImage(systemName: "line.3.horizontal", withConfiguration: config), for: .normal)
        downloadsButton.setImage(UIImage(systemName: "arrow.down.to.line", withConfiguration: config), for: .normal)
        tabsButton.setImage(nil, for: .normal)

        [backButton, homeButton, menuButton, downloadsButton, tabsButton].forEach { button in
            button.tintColor = tint
            button.imageView?.contentMode = .scaleAspectFit
            button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        }

        tabsGlyph.layer.borderColor = tint.cgColor
        tabsCountLabel.textColor = tint
        applyNavigationEnabledState()
    }

    private func applyNavigationEnabledState() {
        backButton.isUserInteractionEnabled = canGoBack
        let disabledAlpha: CGFloat = ThemeManager.shared.current.isLight ? 0.4 : 0.35
        backButton.alpha = canGoBack ? 1 : disabledAlpha
    }

    private func configure(_ button: UIButton, action: Selector, label: String) {
        button.tintColor = BrowserTheme.textPrimary
        button.accessibilityLabel = label
        button.setPreferredSymbolConfiguration(Self.iconConfig, forImageIn: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func backTapped() { delegate?.toolbarDidTapBack() }
    @objc private func homeTapped() { delegate?.toolbarDidTapHome() }
    @objc private func menuTapped() { delegate?.toolbarDidTapMenu() }
    @objc private func downloadsTapped() { delegate?.toolbarDidTapDownloads() }
    @objc private func tabsTapped() { delegate?.toolbarDidTapTabs() }
}
