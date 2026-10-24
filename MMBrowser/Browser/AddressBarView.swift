import UIKit
import SnapKit

protocol AddressBarViewDelegate: AnyObject {
    func addressBarDidSubmit(_ text: String)
    func addressBarDidBeginEditing()
    func addressBarDidEndEditing()
    func addressBarTextDidChange(_ text: String)
    func addressBarDidTapReload()
    func addressBarDidTapBack()
    func addressBarDidTapForward()
    func addressBarDidTapRichMenu()
    func addressBarCanSwipeToPreviousTab() -> Bool
    func addressBarCanSwipeToNextTab() -> Bool
    func addressBarTitleForAdjacentTab(offset: Int) -> String?
    /// Interactive tab switch: `offset` matches address-field drag (points in address-bar space).
    func addressBarSwipeDidUpdate(offset: CGFloat, width: CGFloat)
    func addressBarDidSwipeToPreviousTab()
    func addressBarDidSwipeToNextTab()
    func addressBarDidChoosePageCleaner(urlOnly: Bool)
    func addressBarDidExitPageCleaner()
    /// Open the saved Web Editor rules list (manage / delete).
    func addressBarDidRequestWebEditorRules()
    func addressBarDidTapShield(blockCount: Int)
    /// Compact bottom pill was tapped — expand the full chrome again.
    func addressBarDidTapCompactExpand()
    /// Cleaner mode bar visibility changed — host should grow/shrink chrome height.
    func addressBarDidChangeCleanerMenuVisible(_ visible: Bool, extraHeight: CGFloat)
}

final class AddressBarView: UIView, UITextFieldDelegate, UIGestureRecognizerDelegate {
    weak var delegate: AddressBarViewDelegate?

    private let container = UIView()
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private let richMenuButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let shieldButton = UIButton(type: .custom)
    private var containerLeadingConstraint: Constraint?
    private var navigationVisible = false
    private var canGoBack = false
    private var canGoForward = false
    private let shieldBadge = UILabel()
    private let privateBadge = UILabel()
    let textField = UITextField()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var isPrivateMode = false
    private var isPageCleanerActive = false
    /// `nil` when inactive; `false` = this site; `true` = this page only.
    private var cleanerURLOnly: Bool?
    private var blockCount = 0
    private var focusActive = false

    private let cleanerMenuContainer = UIView()
    private let cleanerTitleButton = UIButton(type: .system)
    private let cleanerSiteChip = UIButton(type: .system)
    private let cleanerPageChip = UIButton(type: .system)
    private let cleanerExitChip = UIButton(type: .system)
    private var cleanerMenuVisible = false
    /// Extra height the host chrome should add while the cleaner bar is open.
    private(set) var cleanerMenuExtraHeight: CGFloat = 0
    private var containerCenterYConstraint: Constraint?
    private var dismissTap: UITapGestureRecognizer?
    private static let cleanerMenuOccupiedHeight: CGFloat = 58
    private var tabSwipe: UIPanGestureRecognizer?
    private let swipeClip = UIView()
    private let peekLabel = UILabel()
    private let hostLabel = UILabel()
    private var shortcutAccessoryView: UIView?
    private var shortcutButtons: [UIButton] = []
    private let keyboardDismissButton = UIButton(type: .system)
    /// Skip expanding to the live page URL on the next begin-editing (used after clear).
    private var suppressNextEditingURLExpand = false
    private var isCompact = false
    private var compactExpandTap: UITapGestureRecognizer?

    /// Common URL fragments for the keyboard accessory above the address field.
    private static let addressShortcuts = [
        "https://", "www.", ".", "/", ".com", ".net", ".org", ".io", "-"
    ]
    private static let chromeIconPointSize: CGFloat = 18
    private static let chromeIconButtonSize: CGFloat = 24

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = .clear

        // Recessed field inside the shared chrome card (card is lighter; field is darker).
        container.backgroundColor = BrowserTheme.background
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        addSubview(container)

        configureNavButton(backButton, action: #selector(backTapped), label: "Back")
        configureNavButton(forwardButton, action: #selector(forwardTapped), label: "Forward")
        backButton.isHidden = true
        forwardButton.isHidden = true
        backButton.isUserInteractionEnabled = false
        forwardButton.isUserInteractionEnabled = false

        reloadButton.accessibilityLabel = "Reload"
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)

        richMenuButton.isHidden = true
        richMenuButton.isUserInteractionEnabled = false
        richMenuButton.accessibilityElementsHidden = true

        let clearConfig = UIImage.SymbolConfiguration(pointSize: Self.chromeIconPointSize, weight: .regular)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: clearConfig), for: .normal)
        clearButton.tintColor = BrowserTheme.textSecondary
        clearButton.accessibilityLabel = "Clear address"
        clearButton.isHidden = true
        clearButton.addTarget(self, action: #selector(clearAddressTapped), for: .touchUpInside)

        let shieldConfig = UIImage.SymbolConfiguration(pointSize: Self.chromeIconPointSize, weight: .regular)
        shieldButton.setImage(UIImage(systemName: "shield.lefthalf.filled", withConfiguration: shieldConfig), for: .normal)
        shieldButton.tintColor = BrowserTheme.textSecondary
        shieldButton.accessibilityLabel = "Ads and trackers blocked"
        shieldButton.isHidden = true
        shieldButton.contentEdgeInsets = .zero
        shieldButton.imageView?.contentMode = .scaleAspectFit
        shieldButton.addTarget(self, action: #selector(shieldTapped), for: .touchUpInside)

        shieldBadge.font = .systemFont(ofSize: 9, weight: .bold)
        shieldBadge.textColor = .white
        shieldBadge.textAlignment = .center
        shieldBadge.backgroundColor = BrowserTheme.chromeBlue
        shieldBadge.layer.cornerRadius = 7
        shieldBadge.clipsToBounds = true
        shieldBadge.isHidden = true
        shieldBadge.isUserInteractionEnabled = false

        privateBadge.text = "Private"
        privateBadge.font = .systemFont(ofSize: 10, weight: .bold)
        privateBadge.textColor = BrowserTheme.privateAccent
        privateBadge.textAlignment = .center
        privateBadge.backgroundColor = BrowserTheme.privateAccent.withAlphaComponent(0.18)
        privateBadge.layer.cornerRadius = 8
        privateBadge.clipsToBounds = true
        privateBadge.isHidden = true

        textField.textColor = BrowserTheme.textPrimary
        textField.tintColor = BrowserTheme.chromeBlue
        textField.font = .systemFont(ofSize: 15, weight: .medium)
        textField.textAlignment = .center
        textField.returnKeyType = .go
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .webSearch
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        updateSearchPlaceholder()
        setupKeyboardShortcuts()

        progressView.progressTintColor = BrowserTheme.chromeBlue
        progressView.trackTintColor = .clear
        progressView.isHidden = true

        swipeClip.clipsToBounds = true
        swipeClip.isUserInteractionEnabled = true
        peekLabel.font = .systemFont(ofSize: 15, weight: .medium)
        peekLabel.textAlignment = .center
        peekLabel.isUserInteractionEnabled = false
        peekLabel.alpha = 0

        hostLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hostLabel.textColor = BrowserTheme.textPrimary
        hostLabel.textAlignment = .center
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.isHidden = true
        hostLabel.isUserInteractionEnabled = false

        addSubview(backButton)
        addSubview(forwardButton)
        container.addSubview(reloadButton)
        container.addSubview(privateBadge)
        container.addSubview(swipeClip)
        swipeClip.addSubview(textField)
        swipeClip.addSubview(peekLabel)
        container.addSubview(hostLabel)
        container.addSubview(clearButton)
        container.addSubview(shieldButton)
        container.addSubview(shieldBadge)
        container.addSubview(richMenuButton)
        addSubview(progressView)

        let expandTap = UITapGestureRecognizer(target: self, action: #selector(compactExpandTapped))
        expandTap.isEnabled = false
        container.addGestureRecognizer(expandTap)
        compactExpandTap = expandTap

        setupCleanerMenu()
        setupTabSwipe()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSearchPlaceholder), name: .searchEngineChanged, object: nil)

        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(2)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.chromeIconButtonSize)
        }
        forwardButton.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(2)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.chromeIconButtonSize)
        }
        container.snp.makeConstraints { make in
            containerLeadingConstraint = make.leading.equalToSuperview().offset(4).constraint
            make.trailing.equalToSuperview().offset(-4)
            containerCenterYConstraint = make.centerY.equalToSuperview().constraint
            make.height.equalTo(40)
        }
        hostLabel.snp.makeConstraints { make in
            make.leading.equalTo(shieldButton.snp.trailing).offset(6)
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        shieldButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.chromeIconButtonSize)
        }
        privateBadge.snp.makeConstraints { make in
            make.leading.equalTo(shieldButton.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
            make.width.equalTo(52)
        }
        richMenuButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.size.equalTo(0)
        }
        reloadButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.chromeIconButtonSize)
        }
        shieldBadge.snp.makeConstraints { make in
            make.top.equalTo(shieldButton).offset(-4)
            make.trailing.equalTo(shieldButton).offset(6)
            make.height.equalTo(14)
            make.width.greaterThanOrEqualTo(14)
        }
        // Trailing is owned exclusively by refreshTextFieldConstraints() so it can track the
        // reload button without fighting a second trailing constraint to richMenuButton.
        swipeClip.snp.makeConstraints { make in
            make.leading.equalTo(shieldButton.snp.trailing).offset(8)
            make.top.bottom.equalToSuperview()
        }
        textField.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        peekLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        refreshTextFieldConstraints()
        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(container.snp.top)
            make.height.equalTo(2)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        if cleanerMenuVisible, !cleanerMenuContainer.isHidden {
            let p = convert(point, to: cleanerMenuContainer)
            if cleanerMenuContainer.point(inside: p, with: event) { return true }
        }
        return false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        if cleanerMenuVisible, !cleanerMenuContainer.isHidden {
            let p = convert(point, to: cleanerMenuContainer)
            if let hit = cleanerMenuContainer.hitTest(p, with: event) {
                return hit
            }
        }
        if !clearButton.isHidden {
            let clearPoint = convert(point, to: clearButton)
            if clearButton.bounds.insetBy(dx: -6, dy: -6).contains(clearPoint) {
                return clearButton
            }
        }
        if !shieldButton.isHidden {
            let shieldPoint = convert(point, to: shieldButton)
            if shieldButton.bounds.insetBy(dx: -4, dy: -4).contains(shieldPoint) {
                return shieldButton
            }
        }
        return super.hitTest(point, with: event)
    }

    private func setupTabSwipe() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleTabSwipe(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        pan.maximumNumberOfTouches = 1
        container.addGestureRecognizer(pan)
        tabSwipe = pan
    }

    private func setupCleanerMenu() {
        styleBubbleContainer(cleanerMenuContainer)
        addSubview(cleanerMenuContainer)

        configureChip(cleanerSiteChip, title: "This site")
        configureChip(cleanerPageChip, title: "This page")
        configureExitChip()
        cleanerSiteChip.addTarget(self, action: #selector(cleanerSiteTapped), for: .touchUpInside)
        cleanerPageChip.addTarget(self, action: #selector(cleanerPageTapped), for: .touchUpInside)
        cleanerExitChip.addTarget(self, action: #selector(cleanerExitTapped), for: .touchUpInside)

        cleanerTitleButton.setTitle("Web Editor", for: .normal)
        cleanerTitleButton.setTitleColor(BrowserTheme.textSecondary, for: .normal)
        cleanerTitleButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        cleanerTitleButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
        cleanerTitleButton.setContentHuggingPriority(.required, for: .horizontal)
        cleanerTitleButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cleanerTitleButton.accessibilityLabel = "Web Editor rules"
        cleanerTitleButton.accessibilityHint = "Shows saved editor rules"
        cleanerTitleButton.addTarget(self, action: #selector(cleanerTitleTapped), for: .touchUpInside)

        let modeChips = UIStackView(arrangedSubviews: [cleanerSiteChip, cleanerPageChip])
        modeChips.axis = .horizontal
        modeChips.spacing = 6
        modeChips.alignment = .fill
        modeChips.distribution = .fillEqually

        let chips = UIStackView(arrangedSubviews: [modeChips, cleanerExitChip])
        chips.axis = .horizontal
        chips.spacing = 6
        chips.alignment = .center
        chips.distribution = .fill

        let stack = UIStackView(arrangedSubviews: [cleanerTitleButton, chips])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        cleanerMenuContainer.addSubview(stack)

        // Keep the bar inside AddressBarView bounds so chromeCard.clipsToBounds cannot cover it.
        cleanerMenuContainer.snp.makeConstraints { make in
            make.leading.equalTo(container.snp.leading)
            make.trailing.equalTo(container.snp.trailing)
            make.top.equalToSuperview()
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
        }
        cleanerSiteChip.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(34)
        }
        cleanerPageChip.snp.makeConstraints { make in
            make.height.equalTo(cleanerSiteChip)
        }
        cleanerExitChip.snp.makeConstraints { make in
            make.height.equalTo(34)
            make.width.equalTo(34)
        }
        cleanerExitChip.setContentHuggingPriority(.required, for: .horizontal)
        cleanerExitChip.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func styleBubbleContainer(_ view: UIView) {
        view.isHidden = true
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: 6)
        view.backgroundColor = BrowserTheme.elevated
        view.layer.cornerRadius = 14
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.35
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func configureChip(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = BrowserTheme.secondaryCard
        button.layer.cornerRadius = 10
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    }

    private func configureExitChip() {
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        cleanerExitChip.setTitle(nil, for: .normal)
        cleanerExitChip.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        cleanerExitChip.tintColor = BrowserTheme.textPrimary
        cleanerExitChip.backgroundColor = BrowserTheme.secondaryCard
        cleanerExitChip.layer.cornerRadius = 17
        cleanerExitChip.clipsToBounds = true
        cleanerExitChip.contentHorizontalAlignment = .center
        cleanerExitChip.contentVerticalAlignment = .center
        cleanerExitChip.contentEdgeInsets = .zero
        cleanerExitChip.accessibilityLabel = "Exit"
    }

    func setURLText(_ text: String) {
        // Don't clobber in-progress typing; apply once editing ends.
        guard !textField.isFirstResponder else { return }
        textField.text = text
        if isCompact {
            hostLabel.text = Self.compactHost(from: text)
        }
    }

    /// Updates the field even while editing (e.g. expand to the full URL on focus).
    func setURLTextForcing(_ text: String) {
        textField.text = text
        updateClearButtonVisibility()
        if isCompact {
            hostLabel.text = Self.compactHost(from: text)
        }
    }

    /// Shrinks to a domain pill (shield + host). Tap expands via `addressBarDidTapCompactExpand`.
    func setCompact(_ compact: Bool, host: String? = nil, pillWidth: CGFloat? = nil) {
        if let host {
            hostLabel.text = host
        } else if compact {
            hostLabel.text = Self.compactHost(from: textField.text)
        }
        let cleanerPinned = isPageCleanerActive
        guard compact != isCompact else {
            if compact {
                refreshTextFieldConstraints()
                applyCleanerMenuLayout(visible: cleanerPinned || cleanerMenuVisible, pillWidth: pillWidth)
            }
            return
        }
        isCompact = compact
        if compact {
            textField.resignFirstResponder()
            // Cleaner mode owns the capsule chrome — keep the chip bar visible.
            if !cleanerPinned {
                hideCleanerMenu()
            }
            // Domain pill always shows a leading shield for the compact look.
            shieldButton.isHidden = false
            shieldBadge.isHidden = true
        }
        hostLabel.isHidden = !compact
        swipeClip.isHidden = compact
        reloadButton.isHidden = compact
        clearButton.isHidden = true
        privateBadge.isHidden = compact || !isPrivateMode
        textField.isUserInteractionEnabled = !compact
        shieldButton.isUserInteractionEnabled = !compact
        tabSwipe?.isEnabled = !compact
        // While cleaner is active, pill tap must not expand chrome / dismiss mode.
        compactExpandTap?.isEnabled = compact && !cleanerPinned
        container.layer.cornerRadius = compact ? BrowserTheme.chromeCompactPillHeight / 2 : 18
        applyCleanerMenuLayout(
            visible: cleanerPinned || (!compact && cleanerMenuVisible),
            pillWidth: pillWidth
        )
        applyTheme()
        if !compact {
            updateShieldAppearance()
        } else {
            refreshTextFieldConstraints()
        }
    }

    private static func compactHost(from text: String?) -> String {
        let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Search" }
        if let url = URL(string: raw), let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if let url = URL(string: "https://\(raw)"), let host = url.host, !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return raw
    }

    @objc private func compactExpandTapped() {
        guard isCompact, !isPageCleanerActive else { return }
        delegate?.addressBarDidTapCompactExpand()
    }

    private var spaceTintColor: UIColor?

    func setPrivateMode(_ isPrivate: Bool) {
        isPrivateMode = isPrivate
        privateBadge.isHidden = !isPrivate
        refreshTextFieldConstraints()
        applyTheme()
    }

    /// Tints address-bar chrome with the active Space color (ignored in Private).
    func setSpaceChrome(_ color: UIColor?) {
        spaceTintColor = color
        applyTheme()
    }

    @objc private func applyTheme() {
        // Outer chrome card owns the elevated surface; this pill is the recessed field.
        // In compact mode the field *is* the floating pill.
        backgroundColor = .clear
        if isCompact {
            container.backgroundColor = isPrivateMode
                ? BrowserTheme.privateElevated
                : BrowserTheme.spaceElevatedColor(spaceColor: spaceTintColor)
            container.layer.borderWidth = 1
            container.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.28).cgColor
            container.layer.shadowColor = UIColor.black.cgColor
            container.layer.shadowOpacity = ThemeManager.shared.current.isLight ? 0.12 : 0.45
            container.layer.shadowRadius = 10
            container.layer.shadowOffset = CGSize(width: 0, height: 2)
            // Shadow needs to escape the pill bounds.
            container.clipsToBounds = false
            layer.masksToBounds = false
        } else {
            container.layer.borderWidth = 0
            container.layer.borderColor = UIColor.clear.cgColor
            container.layer.shadowOpacity = 0
            container.clipsToBounds = true
            if isPrivateMode {
                container.backgroundColor = BrowserTheme.privateBackground
            } else if ThemeManager.shared.current.isLight {
                container.backgroundColor = BrowserTheme.spaceSurfaceColor(spaceColor: spaceTintColor)
            } else {
                // Recessed field inside the Space-tinted chrome card.
                container.backgroundColor = BrowserTheme.spaceSurfaceColor(spaceColor: spaceTintColor)
            }
        }
        hostLabel.textColor = BrowserTheme.textPrimary
        let accent = isPrivateMode ? BrowserTheme.privateAccent : (spaceTintColor ?? BrowserTheme.chromeBlue)
        let iconConfig = UIImage.SymbolConfiguration(pointSize: Self.chromeIconPointSize, weight: .regular)
        let navTint = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        backButton.setImage(
            ThemeManager.shared.image(for: .toolbarBack, configuration: iconConfig, pointSize: Self.chromeIconPointSize),
            for: .normal
        )
        forwardButton.setImage(
            ThemeManager.shared.image(for: .toolbarForward, configuration: iconConfig, pointSize: Self.chromeIconPointSize),
            for: .normal
        )
        [backButton, forwardButton].forEach {
            $0.tintColor = navTint
            $0.setPreferredSymbolConfiguration(iconConfig, forImageIn: .normal)
        }
        applyNavigationEnabledState()
        reloadButton.setImage(
            ThemeManager.shared.image(for: .menuReload, configuration: iconConfig, pointSize: Self.chromeIconPointSize),
            for: .normal
        )
        reloadButton.tintColor = BrowserTheme.textSecondary
        reloadButton.setPreferredSymbolConfiguration(iconConfig, forImageIn: .normal)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: iconConfig), for: .normal)
        clearButton.tintColor = BrowserTheme.textSecondary
        clearButton.setPreferredSymbolConfiguration(iconConfig, forImageIn: .normal)
        shieldButton.setImage(UIImage(systemName: "shield.lefthalf.filled", withConfiguration: iconConfig), for: .normal)
        shieldButton.tintColor = BrowserTheme.textSecondary
        shieldButton.setPreferredSymbolConfiguration(iconConfig, forImageIn: .normal)
        shieldBadge.backgroundColor = accent
        privateBadge.textColor = BrowserTheme.privateAccent
        privateBadge.backgroundColor = BrowserTheme.privateAccent.withAlphaComponent(0.18)
        textField.textColor = BrowserTheme.textPrimary
        textField.tintColor = accent
        peekLabel.textColor = BrowserTheme.textSecondary
        progressView.progressTintColor = accent
        updateSearchPlaceholder()
        cleanerMenuContainer.backgroundColor = isPrivateMode
            ? BrowserTheme.privateElevated
            : BrowserTheme.spaceElevatedColor(spaceColor: spaceTintColor)
        cleanerTitleButton.setTitleColor(BrowserTheme.textSecondary, for: .normal)
        [cleanerSiteChip, cleanerPageChip].forEach {
            $0.setTitleColor(BrowserTheme.textPrimary, for: .normal)
            $0.backgroundColor = BrowserTheme.secondaryCard
        }
        cleanerExitChip.tintColor = BrowserTheme.textPrimary
        cleanerExitChip.backgroundColor = BrowserTheme.secondaryCard
        updateCleanerChipSelection()
        updateShieldAppearance()
        applyShortcutAccessoryTheme()
    }

    @objc private func updateSearchPlaceholder() {
        let name = SearchEngineManager.current.name
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search \(name) or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )
    }

    func setProgress(_ progress: Double, isLoading: Bool) {
        progressView.isHidden = !isLoading
        progressView.setProgress(Float(progress), animated: true)
        if !isLoading {
            progressView.setProgress(0, animated: false)
        }
    }

    func hideCleanerMenu() {
        // While cleaner mode is active, the bar stays until Exit.
        guard cleanerMenuVisible, !isPageCleanerActive else { return }
        setCleanerMenuVisible(false)
    }

    /// Opens the cleaner mode bar (used when Webpage Cleaner is chosen from the rich menu).
    func presentCleanerMenu() {
        textField.resignFirstResponder()
        setCleanerMenuVisible(true)
    }

    /// Enter cleaner mode with a preselected scope (`urlOnly: false` = This site).
    func enterCleanerMode(urlOnly: Bool) {
        textField.resignFirstResponder()
        cleanerURLOnly = urlOnly
        isPageCleanerActive = true
        compactExpandTap?.isEnabled = false
        updateCleanerChipSelection()
        setCleanerMenuVisible(true)
        removeDismissTap()
    }

    func setPageCleanerActive(_ active: Bool) {
        isPageCleanerActive = active
        if active {
            if cleanerURLOnly == nil {
                cleanerURLOnly = false
            }
            compactExpandTap?.isEnabled = false
            updateCleanerChipSelection()
            setCleanerMenuVisible(true)
            removeDismissTap()
        } else {
            cleanerURLOnly = nil
            updateCleanerChipSelection()
            compactExpandTap?.isEnabled = isCompact
            // Force-hide even though hideCleanerMenu() no-ops while active.
            if cleanerMenuVisible {
                setCleanerMenuVisible(false)
            }
        }
    }

    func setBlockCount(_ count: Int) {
        blockCount = max(0, count)
        updateShieldAppearance()
    }

    func setFocusIndicator(active: Bool) {
        focusActive = active
        updateShieldAppearance()
    }

    private func updateClearButtonVisibility() {
        let hasText = !(textField.text ?? "").isEmpty
        let show = textField.isFirstResponder && hasText
        let wasHidden = clearButton.isHidden
        clearButton.isHidden = !show
        if wasHidden != clearButton.isHidden {
            refreshTextFieldConstraints()
        }
    }

    private func updateShieldAppearance() {
        if isCompact {
            // Compact domain pill always keeps the leading shield.
            shieldButton.isHidden = false
            shieldBadge.isHidden = true
            let accent = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
            shieldButton.tintColor = AppSettings.trackerProtectionEnabled
                ? accent.withAlphaComponent(0.9)
                : BrowserTheme.textSecondary
            refreshTextFieldConstraints()
            return
        }

        let show = AppSettings.trackerProtectionEnabled || AppSettings.hideShortsEnabled || AppSettings.youtubeAdShieldEnabled
        guard show else {
            shieldButton.isHidden = true
            shieldBadge.isHidden = true
            refreshTextFieldConstraints()
            return
        }
        shieldButton.isHidden = false
        let accent = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        if blockCount > 0 {
            shieldButton.tintColor = accent
            shieldBadge.isHidden = false
            let text = blockCount > 99 ? "99+" : "\(blockCount)"
            shieldBadge.text = " \(text) "
            shieldBadge.backgroundColor = accent
            shieldButton.accessibilityValue = "\(blockCount) blocked"
        } else if focusActive {
            shieldBadge.isHidden = true
            shieldButton.tintColor = accent
            shieldButton.accessibilityValue = "Focus mode on"
        } else if AppSettings.trackerProtectionEnabled {
            shieldBadge.isHidden = true
            shieldButton.tintColor = accent.withAlphaComponent(0.85)
            shieldButton.accessibilityValue = "Protection on"
        } else {
            shieldBadge.isHidden = true
            shieldButton.tintColor = BrowserTheme.textSecondary
            shieldButton.accessibilityValue = nil
        }
        refreshTextFieldConstraints()
    }

    private func refreshTextFieldConstraints() {
        let trailingTarget = reloadButton.snp.leading

        // Collapse the leading shield when hidden so the field doesn't keep a gap.
        shieldButton.snp.remakeConstraints { make in
            make.leading.equalToSuperview().offset(shieldButton.isHidden ? 0 : (isCompact ? 12 : 10))
            make.centerY.equalToSuperview()
            if shieldButton.isHidden {
                make.size.equalTo(0)
            } else {
                make.size.equalTo(Self.chromeIconButtonSize)
            }
        }

        // Keep Private badge after the leading shield (or at the leading edge if shield is hidden).
        privateBadge.snp.remakeConstraints { make in
            if shieldButton.isHidden {
                make.leading.equalToSuperview().offset(10)
            } else {
                make.leading.equalTo(shieldButton.snp.trailing).offset(6)
            }
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
            make.width.equalTo(52)
        }

        clearButton.snp.remakeConstraints { make in
            make.trailing.equalTo(trailingTarget).offset(-4)
            make.centerY.equalToSuperview()
            make.size.equalTo(Self.chromeIconButtonSize)
        }

        hostLabel.snp.remakeConstraints { make in
            if shieldButton.isHidden {
                make.leading.equalToSuperview().offset(14)
            } else {
                make.leading.equalTo(shieldButton.snp.trailing).offset(6)
            }
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }

        swipeClip.snp.remakeConstraints { make in
            if isPrivateMode {
                make.leading.equalTo(privateBadge.snp.trailing).offset(6)
            } else if !shieldButton.isHidden {
                make.leading.equalTo(shieldButton.snp.trailing).offset(8)
            } else {
                make.leading.equalToSuperview().offset(12)
            }
            if clearButton.isHidden {
                make.trailing.equalTo(trailingTarget).offset(-6)
            } else {
                make.trailing.equalTo(clearButton.snp.leading).offset(-2)
            }
            make.top.bottom.equalToSuperview()
        }
        textField.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
        peekLabel.snp.remakeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        resetSwipeVisuals(animated: false)
        hideCleanerMenu()
        textField.textAlignment = .left
        let skipExpand = suppressNextEditingURLExpand
        suppressNextEditingURLExpand = false
        if !skipExpand {
            // Let the host expand to the full URL before selecting.
            delegate?.addressBarDidBeginEditing()
        }
        textField.selectAll(nil)
        updateClearButtonVisibility()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
        updateClearButtonVisibility()
        delegate?.addressBarDidEndEditing()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        hideCleanerMenu()
        delegate?.addressBarDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    @objc private func textFieldEditingChanged() {
        updateClearButtonVisibility()
        delegate?.addressBarTextDidChange(textField.text ?? "")
    }

    @objc private func clearAddressTapped() {
        // Window-level keyboard dismiss can resign the field before this runs; becoming
        // first responder again must not re-expand the live page URL into the field.
        if !textField.isFirstResponder {
            suppressNextEditingURLExpand = true
            textField.becomeFirstResponder()
        }
        // Clear via the editing API so any selection / marked text is removed reliably.
        if let range = textField.textRange(from: textField.beginningOfDocument, to: textField.endOfDocument) {
            textField.replace(range, withText: "")
        } else {
            textField.text = ""
        }
        updateClearButtonVisibility()
        delegate?.addressBarTextDidChange("")
    }

    private func setupKeyboardShortcuts() {
        let width = LayoutSupport.windowWidth(relativeTo: self)
        let bar = AddressKeyboardAccessoryView(frame: CGRect(x: 0, y: 0, width: width, height: 46))
        bar.autoresizingMask = .flexibleWidth
        bar.isUserInteractionEnabled = true

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        // Accessory chips must receive taps immediately; default delay eats short taps.
        scroll.delaysContentTouches = false
        scroll.canCancelContentTouches = false
        scroll.contentInset = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        scroll.isUserInteractionEnabled = true
        bar.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .fill
        scroll.addSubview(stack)

        shortcutButtons.removeAll()
        for token in Self.addressShortcuts {
            let button = UIButton(type: .system)
            button.setTitle(token, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            button.layer.cornerRadius = 8
            button.clipsToBounds = true
            button.accessibilityLabel = "Insert \(token)"
            button.addTarget(self, action: #selector(shortcutTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            shortcutButtons.append(button)
        }

        let dismissConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        keyboardDismissButton.setImage(
            UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: dismissConfig),
            for: .normal
        )
        keyboardDismissButton.accessibilityLabel = "Dismiss keyboard"
        keyboardDismissButton.layer.cornerRadius = 8
        keyboardDismissButton.clipsToBounds = true
        keyboardDismissButton.addTarget(self, action: #selector(dismissKeyboardTapped), for: .touchUpInside)
        bar.addSubview(keyboardDismissButton)

        keyboardDismissButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-8)
            make.centerY.equalToSuperview()
            make.width.equalTo(40)
            make.height.equalTo(32)
        }
        scroll.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.trailing.equalTo(keyboardDismissButton.snp.leading).offset(-4)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scroll.contentLayoutGuide).inset(UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 0))
            make.height.equalTo(scroll.frameLayoutGuide).offset(-10)
        }

        shortcutAccessoryView = bar
        textField.inputAccessoryView = bar
        applyShortcutAccessoryTheme()
    }

    private func applyShortcutAccessoryTheme() {
        shortcutAccessoryView?.backgroundColor = BrowserTheme.elevated
        for button in shortcutButtons {
            button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
            button.backgroundColor = BrowserTheme.secondaryCard
            button.tintColor = BrowserTheme.textPrimary
        }
        keyboardDismissButton.tintColor = BrowserTheme.textPrimary
        keyboardDismissButton.backgroundColor = BrowserTheme.secondaryCard
    }

    @objc private func shortcutTapped(_ sender: UIButton) {
        guard let token = sender.currentTitle ?? sender.title(for: .normal), !token.isEmpty else { return }
        if !textField.isFirstResponder {
            suppressNextEditingURLExpand = true
            textField.becomeFirstResponder()
        }
        // Prefer UITextInput.replace so a full-URL selection is swapped for the token.
        let range = textField.selectedTextRange
            ?? textField.textRange(from: textField.endOfDocument, to: textField.endOfDocument)
        if let range {
            textField.replace(range, withText: token)
        } else {
            textField.text = (textField.text ?? "") + token
        }
        textField.sendActions(for: .editingChanged)
        updateClearButtonVisibility()
        delegate?.addressBarTextDidChange(textField.text ?? "")
    }

    @objc private func dismissKeyboardTapped() {
        textField.resignFirstResponder()
    }

    @objc private func reloadTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        delegate?.addressBarDidTapReload()
    }

    /// Navigation lives in the bottom toolbar row; keep field chrome full-width.
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, visible: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        navigationVisible = false
        _ = visible
        backButton.isHidden = true
        forwardButton.isHidden = true
        containerLeadingConstraint?.update(offset: 4)
        applyNavigationEnabledState()
    }

    private func configureNavButton(_ button: UIButton, action: Selector, label: String) {
        button.accessibilityLabel = label
        button.tintColor = BrowserTheme.textPrimary
        let config = UIImage.SymbolConfiguration(pointSize: Self.chromeIconPointSize, weight: .regular)
        button.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func applyNavigationEnabledState() {
        guard navigationVisible else { return }
        backButton.isUserInteractionEnabled = canGoBack
        forwardButton.isUserInteractionEnabled = canGoForward
        let disabledAlpha: CGFloat = ThemeManager.shared.current.isLight ? 0.4 : 0.35
        backButton.alpha = canGoBack ? 1 : disabledAlpha
        forwardButton.alpha = canGoForward ? 1 : disabledAlpha
    }

    @objc private func backTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        delegate?.addressBarDidTapBack()
    }

    @objc private func forwardTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        delegate?.addressBarDidTapForward()
    }

    @objc private func richMenuTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        delegate?.addressBarDidTapRichMenu()
    }

    @objc private func shieldTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        delegate?.addressBarDidTapShield(blockCount: blockCount)
    }

    @objc private func cleanerSiteTapped() {
        cleanerURLOnly = false
        updateCleanerChipSelection()
        delegate?.addressBarDidChoosePageCleaner(urlOnly: false)
    }

    @objc private func cleanerPageTapped() {
        cleanerURLOnly = true
        updateCleanerChipSelection()
        delegate?.addressBarDidChoosePageCleaner(urlOnly: true)
    }

    @objc private func cleanerExitTapped() {
        cleanerURLOnly = nil
        updateCleanerChipSelection()
        delegate?.addressBarDidExitPageCleaner()
    }

    @objc private func cleanerTitleTapped() {
        delegate?.addressBarDidRequestWebEditorRules()
    }

    @objc private func handleTabSwipe(_ gesture: UIPanGestureRecognizer) {
        guard !textField.isFirstResponder else {
            resetSwipeVisuals(animated: true)
            return
        }

        let translation = gesture.translation(in: container)
        let velocity = gesture.velocity(in: container)
        let width = max(swipeClip.bounds.width, 1)

        switch gesture.state {
        case .began:
            hideCleanerMenu()
            peekLabel.textColor = BrowserTheme.textSecondary
            updateSwipeVisuals(dx: 0, width: width)

        case .changed:
            updateSwipeVisuals(dx: translation.x, width: width)

        case .ended, .cancelled, .failed:
            let dx = translation.x
            let canPrevious = delegate?.addressBarCanSwipeToPreviousTab() == true
            let canNext = delegate?.addressBarCanSwipeToNextTab() == true
            // Match tab-switcher left→right order: swipe left → next, swipe right → previous.
            let towardNext = dx < 0
            let canCommitDirection = towardNext ? canNext : canPrevious
            let distanceOK = abs(dx) > width * 0.28 || abs(velocity.x) > 520
            let mostlyHorizontal = abs(dx) > abs(translation.y) * 1.2
            let shouldCommit = gesture.state == .ended
                && canCommitDirection
                && mostlyHorizontal
                && distanceOK
                && abs(dx) > 8

            if shouldCommit {
                let target = towardNext ? -width : width
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.applySwipeOffset(target, width: width, peekAlpha: 1)
                } completion: { _ in
                    if towardNext {
                        self.delegate?.addressBarDidSwipeToNextTab()
                    } else {
                        self.delegate?.addressBarDidSwipeToPreviousTab()
                    }
                    self.resetSwipeVisuals(animated: false)
                    // Settle the new URL in from the opposite side.
                    let enterFrom = towardNext ? width * 0.35 : -width * 0.35
                    self.textField.transform = CGAffineTransform(translationX: enterFrom, y: 0)
                    self.textField.alpha = 0.35
                    UIView.animate(
                        withDuration: 0.22,
                        delay: 0,
                        usingSpringWithDamping: 0.88,
                        initialSpringVelocity: 0.4,
                        options: [.allowUserInteraction]
                    ) {
                        self.textField.transform = .identity
                        self.textField.alpha = 1
                    }
                }
            } else {
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.3,
                    options: [.allowUserInteraction]
                ) {
                    self.resetSwipeVisuals(animated: false)
                }
            }

        default:
            break
        }
    }

    private func updateSwipeVisuals(dx: CGFloat, width: CGFloat) {
        let canPrevious = delegate?.addressBarCanSwipeToPreviousTab() == true
        let canNext = delegate?.addressBarCanSwipeToNextTab() == true
        var offset = dx

        // offset < 0 (swipe left) peeks the next tab; offset > 0 peeks the previous.
        if offset < 0, !canNext {
            offset = rubberBand(offset, limit: width)
        } else if offset > 0, !canPrevious {
            offset = rubberBand(offset, limit: width)
        } else {
            // Soft clamp so it doesn't overshoot too far while dragging.
            let maxPull = width * 0.95
            offset = max(-maxPull, min(maxPull, offset))
        }

        let towardNext = offset < 0
        let canShowPeek = towardNext ? canNext : canPrevious
        if canShowPeek, abs(offset) > 1 {
            let adjacentOffset = towardNext ? 1 : -1
            peekLabel.text = delegate?.addressBarTitleForAdjacentTab(offset: adjacentOffset)
            let progress = min(1, abs(offset) / (width * 0.55))
            applySwipeOffset(offset, width: width, peekAlpha: progress)
        } else {
            peekLabel.text = nil
            applySwipeOffset(offset, width: width, peekAlpha: 0)
        }
    }

    private func applySwipeOffset(_ offset: CGFloat, width: CGFloat, peekAlpha: CGFloat) {
        textField.transform = CGAffineTransform(translationX: offset, y: 0)
        textField.alpha = max(0.25, 1 - abs(offset) / (width * 0.9))
        // Peek enters from the opposite edge of the drag.
        let peekStart = offset >= 0 ? -width : width
        peekLabel.transform = CGAffineTransform(translationX: peekStart + offset, y: 0)
        peekLabel.alpha = peekAlpha
        delegate?.addressBarSwipeDidUpdate(offset: offset, width: width)
    }

    private func rubberBand(_ dx: CGFloat, limit: CGFloat) -> CGFloat {
        let sign: CGFloat = dx < 0 ? -1 : 1
        let x = abs(dx)
        let dim = max(limit, 1)
        return sign * (1 - (1 / ((x * 0.55 / dim) + 1))) * dim * 0.35
    }

    private func resetSwipeVisuals(animated: Bool) {
        let updates = {
            self.textField.transform = .identity
            self.textField.alpha = 1
            self.peekLabel.transform = .identity
            self.peekLabel.alpha = 0
            self.peekLabel.text = nil
            self.delegate?.addressBarSwipeDidUpdate(offset: 0, width: max(self.swipeClip.bounds.width, 1))
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: updates)
        } else {
            updates()
        }
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        // Outside tap only dismisses before a mode is chosen.
        guard !isPageCleanerActive else { return }
        setCleanerMenuVisible(false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        if gestureRecognizer === dismissTap {
            if view === cleanerSiteChip || view === cleanerPageChip || view === cleanerExitChip
                || view.isDescendant(of: cleanerMenuContainer) {
                return false
            }
            return !isPageCleanerActive
        }
        if gestureRecognizer === tabSwipe {
            if view === backButton || view.isDescendant(of: backButton) { return false }
            if view === forwardButton || view.isDescendant(of: forwardButton) { return false }
            if view === reloadButton || view.isDescendant(of: reloadButton) { return false }
            if view === richMenuButton || view.isDescendant(of: richMenuButton) { return false }
            if view === clearButton || view.isDescendant(of: clearButton) { return false }
            if view === shieldButton || view.isDescendant(of: shieldButton) { return false }
            if view === textField || view.isDescendant(of: textField) { return !textField.isFirstResponder }
            return true
        }
        if view === cleanerSiteChip || view === cleanerPageChip || view === cleanerExitChip
            || view.isDescendant(of: cleanerMenuContainer) {
            return false
        }
        if view === backButton || view === forwardButton
            || view === reloadButton || view === richMenuButton
            || view === clearButton || view === shieldButton { return false }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === tabSwipe,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard !textField.isFirstResponder else { return false }
        let v = pan.velocity(in: container)
        let t = pan.translation(in: container)
        if abs(v.x) + abs(v.y) > 8 {
            return abs(v.x) > abs(v.y) * 1.15
        }
        return abs(t.x) > abs(t.y) * 1.15 && abs(t.x) > 2
    }

    private func updateCleanerChipSelection() {
        let accent = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        applyCleanerChipStyle(cleanerSiteChip, selected: isPageCleanerActive && cleanerURLOnly == false, accent: accent)
        applyCleanerChipStyle(cleanerPageChip, selected: isPageCleanerActive && cleanerURLOnly == true, accent: accent)
        applyCleanerChipStyle(cleanerExitChip, selected: false, accent: accent)
    }

    private func applyCleanerChipStyle(_ button: UIButton, selected: Bool, accent: UIColor) {
        let isIconOnly = button === cleanerExitChip
        if selected {
            if isIconOnly {
                button.tintColor = .white
            } else {
                button.setTitleColor(.white, for: .normal)
            }
            button.backgroundColor = accent
        } else {
            if isIconOnly {
                button.tintColor = BrowserTheme.textPrimary
            } else {
                button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
            }
            button.backgroundColor = BrowserTheme.secondaryCard
        }
    }

    private func setCleanerMenuVisible(_ visible: Bool) {
        let wasVisible = cleanerMenuVisible
        cleanerMenuVisible = visible
        cleanerMenuContainer.isHidden = false
        bringSubviewToFront(cleanerMenuContainer)
        applyCleanerMenuLayout(visible: visible)

        if visible {
            // Outside dismiss never ends an active cleaner session — only Exit does.
            if isPageCleanerActive {
                removeDismissTap()
            } else {
                installDismissTap()
            }
        } else {
            removeDismissTap()
        }

        let extra = visible ? Self.cleanerMenuOccupiedHeight : 0
        cleanerMenuExtraHeight = extra
        if wasVisible != visible {
            delegate?.addressBarDidChangeCleanerMenuVisible(visible, extraHeight: extra)
        }

        UIView.animate(withDuration: 0.18, animations: {
            self.cleanerMenuContainer.alpha = visible ? 1 : 0
            self.cleanerMenuContainer.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 6)
            self.superview?.layoutIfNeeded()
        }, completion: { _ in
            if !visible {
                self.cleanerMenuContainer.isHidden = true
                self.cleanerMenuContainer.transform = .identity
            }
        })
    }

    private func applyCleanerMenuLayout(visible: Bool, pillWidth: CGFloat? = nil) {
        let fieldHeight: CGFloat = isCompact ? BrowserTheme.chromeCompactPillHeight : 40
        cleanerMenuContainer.snp.remakeConstraints { make in
            if isCompact && visible {
                // Host card is already inset; chips span the address bar width.
                make.leading.trailing.equalToSuperview()
            } else {
                make.leading.equalToSuperview().offset(isCompact ? 0 : 4)
                make.trailing.equalToSuperview().offset(isCompact ? 0 : -4)
            }
            make.top.equalToSuperview()
        }
        container.snp.remakeConstraints { make in
            make.height.equalTo(fieldHeight)
            if visible {
                make.top.equalTo(cleanerMenuContainer.snp.bottom).offset(6)
                containerCenterYConstraint = nil
                if isCompact {
                    make.centerX.equalToSuperview()
                    let width = pillWidth ?? min(max(bounds.width - 72, 148), 280)
                    make.width.equalTo(width)
                    containerLeadingConstraint = nil
                } else {
                    containerLeadingConstraint = make.leading.equalToSuperview().offset(4).constraint
                    make.trailing.equalToSuperview().offset(-4)
                }
            } else if isCompact {
                containerLeadingConstraint = make.leading.equalToSuperview().offset(0).constraint
                make.trailing.equalToSuperview()
                containerCenterYConstraint = make.centerY.equalToSuperview().constraint
            } else {
                containerLeadingConstraint = make.leading.equalToSuperview().offset(4).constraint
                make.trailing.equalToSuperview().offset(-4)
                containerCenterYConstraint = make.centerY.equalToSuperview().constraint
            }
        }
    }

    private func installDismissTap() {
        guard dismissTap == nil, let window = window else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        dismissTap = tap
    }

    private func removeDismissTap() {
        if let tap = dismissTap {
            tap.view?.removeGestureRecognizer(tap)
        }
        dismissTap = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            removeDismissTap()
        }
    }
}

/// Keyboard accessory sized via intrinsic content size so Auto Layout chips lay out correctly.
private final class AddressKeyboardAccessoryView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 46)
    }

    /// Let chip buttons win over the horizontal scroll view on short taps.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        guard self.point(inside: point, with: event) else { return nil }
        for subview in subviews.reversed() {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local, with: event) {
                return hit
            }
        }
        return self
    }
}

/// Forwards hits to children that draw outside the chrome bounds (e.g. cleaner menu).
final class BrowserChromeView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        for subview in subviews where !subview.isHidden && subview.alpha > 0.01 {
            if let stack = subview as? UIStackView {
                for arranged in stack.arrangedSubviews where !arranged.isHidden {
                    let p = convert(point, to: arranged)
                    if arranged.point(inside: p, with: event) { return true }
                }
            } else {
                let p = convert(point, to: subview)
                if subview.point(inside: p, with: event) { return true }
            }
        }
        return false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        guard self.point(inside: point, with: event) else { return nil }
        for subview in subviews.reversed() {
            if let hit = forwardHit(in: subview, from: self, point: point, event: event) {
                return hit
            }
        }
        return nil
    }

    private func forwardHit(in view: UIView, from parent: UIView, point: CGPoint, event: UIEvent?) -> UIView? {
        let local = parent.convert(point, to: view)
        if let stack = view as? UIStackView {
            for arranged in stack.arrangedSubviews.reversed() {
                if let hit = forwardHit(in: arranged, from: stack, point: local, event: event) {
                    return hit
                }
            }
            return nil
        }
        return view.hitTest(local, with: event)
    }
}
