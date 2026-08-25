import UIKit
import SnapKit

protocol BottomToolbarViewDelegate: AnyObject {
    func toolbarDidTapBack()
    func toolbarDidTapForward()
    func toolbarDidTapNewTab()
    func toolbarDidTapTabs()
    func toolbarDidTapMenu()
    func toolbarDidTapAccount()
    func toolbarDidLongPressAccount()
}

final class BottomToolbarView: UIView {
    weak var delegate: BottomToolbarViewDelegate?

    private let accountChip = UIButton(type: .custom)
    private let accountTitle = UILabel()
    private let accountChevron = UIImageView()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let plusButton = UIButton(type: .system)
    private let tabsButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let tabsBadgeLabel = UILabel()
    private let iconStack = UIStackView()
    private var isPrivateMode = false
    private var canGoBack = false
    private var canGoForward = false
    private var tabCount = 1
    private var accountChipVisible = false
    private var hidesNavigationButtons = false
    private var accountName = ""
    private var accountColor: UIColor = BrowserTheme.chromeBlue
    private var iconStackWidthConstraint: Constraint?
    private var accountChipWidthConstraint: Constraint?

    private static let iconPointSize: CGFloat = 26
    private static let iconConfig = UIImage.SymbolConfiguration(pointSize: iconPointSize, weight: .regular)
    private static let leadingInset: CGFloat = 8
    private static let trailingInset: CGFloat = 4
    private static let chipIconSpacing: CGFloat = 4
    private static let chipMaxWidthCompact: CGFloat = 200
    private static let chipMinWidth: CGFloat = 56
    private static let chipHeight: CGFloat = 36
    private static let iconSlotCount = 5

    override init(frame: CGRect) {
        super.init(frame: frame)

        accountTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        accountTitle.textColor = accountColor
        accountTitle.textAlignment = .center
        accountTitle.lineBreakMode = .byTruncatingTail
        accountTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accountChevron.contentMode = .scaleAspectFit
        accountChevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        accountChevron.image = UIImage(systemName: "chevron.up")
        accountChevron.tintColor = accountColor
        accountChevron.setContentHuggingPriority(.required, for: .horizontal)
        accountChevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        accountChip.addSubview(accountTitle)
        accountChip.addSubview(accountChevron)
        accountChip.layer.cornerRadius = Self.chipHeight / 2
        accountChip.clipsToBounds = true
        accountChip.isHidden = true
        accountChip.accessibilityLabel = "Account"
        accountChip.accessibilityHint = "Double tap to switch accounts. Long press to jump to the previous account."
        accountChip.addTarget(self, action: #selector(accountTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(accountLongPressed(_:)))
        accountChip.addGestureRecognizer(longPress)
        accountChevron.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 10, height: 10))
        }
        accountTitle.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalTo(accountChevron.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
        }

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

        iconStack.axis = .horizontal
        iconStack.distribution = .fillEqually
        iconStack.alignment = .center
        [backButton, forwardButton, plusButton, tabsButton, menuButton].forEach { iconStack.addArrangedSubview($0) }

        addSubview(accountChip)
        addSubview(iconStack)

        accountChip.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Self.leadingInset)
            make.centerY.equalToSuperview()
            make.height.equalTo(Self.chipHeight)
            accountChipWidthConstraint = make.width.equalTo(Self.chipMinWidth).constraint
        }
        // Trailing-aligned icon strip: width is N slots so +/tabs/menu keep the same
        // absolute positions when back/forward slots are absorbed by the chip.
        iconStack.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-Self.trailingInset)
            make.top.equalToSuperview()
            make.height.equalTo(BrowserTheme.toolbarHeight)
            iconStackWidthConstraint = make.width.equalTo(200).constraint
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

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSlotLayout()
    }

    func update(
        canGoBack: Bool,
        canGoForward: Bool,
        tabCount: Int,
        isPrivate: Bool = false,
        hidesNavigationButtons: Bool = false
    ) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.tabCount = max(tabCount, 1)
        self.hidesNavigationButtons = hidesNavigationButtons
        tabsBadgeLabel.text = " \(min(self.tabCount, 99)) "
        tabsBadgeLabel.snp.updateConstraints { make in
            make.width.greaterThanOrEqualTo(self.tabCount >= 10 ? 20 : 14)
        }
        rebuildIconStack()
        setPrivateMode(isPrivate)
        setNeedsLayout()
    }

    func setPrivateMode(_ isPrivate: Bool) {
        isPrivateMode = isPrivate
        accountChip.isHidden = isPrivate || !accountChipVisible
        applyTheme()
        setNeedsLayout()
    }

    func setAccount(name: String, color: UIColor, visible: Bool) {
        accountChipVisible = visible
        accountName = name
        accountColor = color
        let show = visible && !isPrivateMode
        accountChip.isHidden = !show
        accountTitle.text = accountName
        accountTitle.textColor = color
        accountChevron.tintColor = color
        accountChip.backgroundColor = color.withAlphaComponent(0.18)
        accountChip.accessibilityValue = name
        setNeedsLayout()
    }

    /// Keep + / tabs / menu in the same trailing slots as the 5-icon layout;
    /// when back/forward are removed, their slot width is absorbed by the account chip.
    private func updateSlotLayout() {
        let contentWidth = bounds.width - Self.leadingInset - Self.trailingInset
        guard contentWidth > 0 else { return }

        let chipShowing = accountChipVisible && !isPrivateMode && !accountChip.isHidden
        let compactChipWidth: CGFloat = {
            guard chipShowing else { return 0 }
            // Prefer fitting the full name; only truncate when width is truly tight.
            let adaptiveMax = min(Self.chipMaxWidthCompact, max(Self.chipMinWidth, contentWidth * 0.42))
            let titleWidth = ceil(accountTitle.intrinsicContentSize.width)
            let fitting = 12 + titleWidth + 4 + 10 + 10 // padding + title + gap + chevron + trailing
            return min(adaptiveMax, max(Self.chipMinWidth, fitting))
        }()

        let iconArea: CGFloat = {
            if chipShowing {
                return max(0, contentWidth - compactChipWidth - Self.chipIconSpacing)
            }
            return contentWidth
        }()
        let slotWidth = iconArea / CGFloat(Self.iconSlotCount)
        let visibleIconCount = hidesNavigationButtons ? 3 : Self.iconSlotCount
        let iconsWidth = slotWidth * CGFloat(visibleIconCount)

        let chipWidth: CGFloat = {
            guard chipShowing else { return 0 }
            if hidesNavigationButtons {
                return max(Self.chipMinWidth, contentWidth - Self.chipIconSpacing - iconsWidth)
            }
            return compactChipWidth
        }()

        accountChipWidthConstraint?.update(offset: chipWidth)
        iconStackWidthConstraint?.update(offset: max(iconsWidth, 1))
        accountChip.isHidden = !chipShowing
    }

    private func rebuildIconStack() {
        let icons: [UIView] = hidesNavigationButtons
            ? [plusButton, tabsButton, menuButton]
            : [backButton, forwardButton, plusButton, tabsButton, menuButton]
        let current = iconStack.arrangedSubviews
        if current == icons { return }
        current.forEach { iconStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        icons.forEach { iconStack.addArrangedSubview($0) }
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

        accountTitle.textColor = accountColor
        accountChevron.tintColor = accountColor
        tabsBadgeLabel.backgroundColor = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        tabsBadgeLabel.textColor = isPrivateMode ? BrowserTheme.privateBackground : .black
        tabsBadgeLabel.isHidden = false
        applyNavigationEnabledState()
    }

    /// Soften unavailable back/forward without UIButton's disabled gray (keeps theme tint).
    private func applyNavigationEnabledState() {
        guard !hidesNavigationButtons else {
            backButton.alpha = 1
            forwardButton.alpha = 1
            return
        }
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

    func pulseAccountChip() {
        guard !accountChip.isHidden else { return }
        UIView.animate(withDuration: 0.12, animations: {
            self.accountChip.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        }, completion: { _ in
            UIView.animate(withDuration: 0.18) {
                self.accountChip.transform = .identity
            }
        })
    }

    @objc private func accountTapped() { delegate?.toolbarDidTapAccount() }
    @objc private func accountLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        delegate?.toolbarDidLongPressAccount()
    }
    @objc private func backTapped() { delegate?.toolbarDidTapBack() }
    @objc private func forwardTapped() { delegate?.toolbarDidTapForward() }
    @objc private func plusTapped() { delegate?.toolbarDidTapNewTab() }
    @objc private func tabsTapped() { delegate?.toolbarDidTapTabs() }
    @objc private func menuTapped() { delegate?.toolbarDidTapMenu() }
}
