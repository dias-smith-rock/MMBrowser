import UIKit
import SnapKit

protocol AddressBarViewDelegate: AnyObject {
    func addressBarDidSubmit(_ text: String)
    func addressBarDidBeginEditing()
    func addressBarDidChoosePageCleaner(urlOnly: Bool)
    func addressBarDidExitPageCleaner()
    func addressBarDidRequestManualScreenshot()
    func addressBarDidRequestLongScreenshot()
}

final class AddressBarView: UIView, UITextFieldDelegate, UIGestureRecognizerDelegate {
    weak var delegate: AddressBarViewDelegate?

    private let container = UIView()
    private let screenshotEntry = UIControl()
    private let screenshotIcon = UIImageView()
    private let chevronIcon = UIImageView()
    private let pageCleanerButton = UIButton(type: .system)
    private let shieldButton = UIButton(type: .custom)
    private let shieldBadge = UILabel()
    private let privateBadge = UILabel()
    let textField = UITextField()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var isPrivateMode = false
    private var isPageCleanerActive = false
    /// `nil` when inactive; `false` = 本站; `true` = 仅此页.
    private var cleanerURLOnly: Bool?
    private var blockCount = 0
    private var focusActive = false

    private let chipsContainer = UIView()
    private let longShotChip = UIButton(type: .system)
    private let manualShotChip = UIButton(type: .system)
    private var chipsVisible = false

    private let cleanerMenuContainer = UIView()
    private let cleanerSiteChip = UIButton(type: .system)
    private let cleanerPageChip = UIButton(type: .system)
    private let cleanerExitChip = UIButton(type: .system)
    private var cleanerMenuVisible = false
    private var dismissTap: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = BrowserTheme.background

        container.backgroundColor = BrowserTheme.elevated
        container.layer.cornerRadius = 22
        addSubview(container)

        let shotConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        screenshotIcon.image = UIImage(systemName: "camera", withConfiguration: shotConfig)
        screenshotIcon.tintColor = BrowserTheme.textSecondary
        screenshotIcon.contentMode = .scaleAspectFit
        screenshotIcon.isUserInteractionEnabled = false

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        chevronIcon.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: chevronConfig)
        chevronIcon.tintColor = BrowserTheme.textSecondary
        chevronIcon.contentMode = .scaleAspectFit
        chevronIcon.isUserInteractionEnabled = false

        screenshotEntry.addSubview(screenshotIcon)
        screenshotEntry.addSubview(chevronIcon)
        screenshotEntry.addTarget(self, action: #selector(screenshotEntryTapped), for: .touchUpInside)
        screenshotEntry.accessibilityLabel = "Screenshot"

        pageCleanerButton.setImage(UIImage(systemName: "wand.and.stars"), for: .normal)
        pageCleanerButton.tintColor = BrowserTheme.textSecondary
        pageCleanerButton.accessibilityLabel = "Clean page"
        pageCleanerButton.addTarget(self, action: #selector(pageCleanerTapped), for: .touchUpInside)

        let shieldConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        shieldButton.setImage(UIImage(systemName: "shield.lefthalf.filled", withConfiguration: shieldConfig), for: .normal)
        shieldButton.tintColor = BrowserTheme.textSecondary
        shieldButton.accessibilityLabel = "Ads and trackers blocked"
        shieldButton.isHidden = true
        shieldButton.contentEdgeInsets = .zero
        shieldButton.imageView?.contentMode = .scaleAspectFit
        // Keep hit target close to the visible glyph (avoid default 44pt expansion).
        shieldButton.isPointerInteractionEnabled = false

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
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )

        progressView.progressTintColor = BrowserTheme.chromeBlue
        progressView.trackTintColor = .clear
        progressView.isHidden = true

        container.addSubview(screenshotEntry)
        container.addSubview(privateBadge)
        container.addSubview(textField)
        container.addSubview(shieldButton)
        container.addSubview(shieldBadge)
        container.addSubview(pageCleanerButton)
        addSubview(progressView)

        setupChips()
        setupCleanerMenu()
        updatePageCleanerAppearance()
        updateShieldAppearance()

        container.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.top.equalToSuperview().offset(4)
            make.height.equalTo(40)
        }
        screenshotEntry.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
            make.height.equalTo(32)
            make.width.equalTo(44)
        }
        privateBadge.snp.makeConstraints { make in
            make.leading.equalTo(screenshotEntry.snp.trailing).offset(4)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
            make.width.equalTo(52)
        }
        screenshotIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(4)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }
        chevronIcon.snp.makeConstraints { make in
            make.leading.equalTo(screenshotIcon.snp.trailing).offset(2)
            make.centerY.equalToSuperview()
            make.width.equalTo(12)
            make.height.equalTo(16)
        }
        pageCleanerButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        shieldButton.snp.makeConstraints { make in
            make.trailing.equalTo(pageCleanerButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        shieldBadge.snp.makeConstraints { make in
            make.top.equalTo(shieldButton).offset(-4)
            make.trailing.equalTo(shieldButton).offset(6)
            make.height.equalTo(14)
            make.width.greaterThanOrEqualTo(14)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(screenshotEntry.snp.trailing).offset(4)
            make.trailing.equalTo(shieldButton.snp.leading).offset(-6)
            make.centerY.equalToSuperview()
        }
        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(container.snp.top)
            make.height.equalTo(2)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Chips / cleaner bubble draw above our bounds; include them in hit testing.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        if chipsVisible, !chipsContainer.isHidden {
            let p = convert(point, to: chipsContainer)
            if chipsContainer.point(inside: p, with: event) { return true }
        }
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
        if chipsVisible, !chipsContainer.isHidden {
            let p = convert(point, to: chipsContainer)
            if let hit = chipsContainer.hitTest(p, with: event) {
                return hit
            }
        }
        // Prefer the compact shield hit box before the large text field swallows taps near the trailing edge.
        if !shieldButton.isHidden {
            let shieldPoint = convert(point, to: shieldButton)
            if shieldButton.bounds.insetBy(dx: -4, dy: -4).contains(shieldPoint) {
                return shieldButton
            }
        }
        return super.hitTest(point, with: event)
    }

    private func setupChips() {
        styleBubbleContainer(chipsContainer)
        addSubview(chipsContainer)

        configureChip(longShotChip, title: "长截屏")
        configureChip(manualShotChip, title: "手动截图")
        longShotChip.addTarget(self, action: #selector(longShotTapped), for: .touchUpInside)
        manualShotChip.addTarget(self, action: #selector(manualShotTapped), for: .touchUpInside)

        let title = makeBubbleTitleLabel("截屏模式")
        let stack = UIStackView(arrangedSubviews: [title, longShotChip, manualShotChip])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        chipsContainer.addSubview(stack)

        chipsContainer.snp.makeConstraints { make in
            make.leading.equalTo(container.snp.leading)
            make.bottom.equalTo(container.snp.top).offset(-8)
            make.width.greaterThanOrEqualTo(132)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
        }
    }

    private func setupCleanerMenu() {
        styleBubbleContainer(cleanerMenuContainer)
        addSubview(cleanerMenuContainer)

        configureChip(cleanerSiteChip, title: "本站")
        configureChip(cleanerPageChip, title: "仅此页")
        configureChip(cleanerExitChip, title: "退出")
        cleanerSiteChip.addTarget(self, action: #selector(cleanerSiteTapped), for: .touchUpInside)
        cleanerPageChip.addTarget(self, action: #selector(cleanerPageTapped), for: .touchUpInside)
        cleanerExitChip.addTarget(self, action: #selector(cleanerExitTapped), for: .touchUpInside)

        let title = makeBubbleTitleLabel("清理模式")
        let stack = UIStackView(arrangedSubviews: [title, cleanerSiteChip, cleanerPageChip, cleanerExitChip])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        cleanerMenuContainer.addSubview(stack)

        cleanerMenuContainer.snp.makeConstraints { make in
            make.trailing.equalTo(container.snp.trailing)
            make.bottom.equalTo(container.snp.top).offset(-8)
            make.width.greaterThanOrEqualTo(132)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10))
        }
    }

    private func styleBubbleContainer(_ view: UIView) {
        view.isHidden = true
        view.alpha = 0
        view.transform = CGAffineTransform(translationX: 0, y: 6)
        view.backgroundColor = BrowserTheme.elevated
        view.layer.cornerRadius = 16
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.35
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func makeBubbleTitleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = BrowserTheme.textSecondary
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textAlignment = .left
        return label
    }

    private func configureChip(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = BrowserTheme.secondaryCard
        button.layer.cornerRadius = 12
        button.contentHorizontalAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    }

    func setURLText(_ text: String) {
        textField.text = text
    }

    func setPrivateMode(_ isPrivate: Bool) {
        isPrivateMode = isPrivate
        backgroundColor = isPrivate ? BrowserTheme.privateBackground : BrowserTheme.background
        container.backgroundColor = isPrivate ? BrowserTheme.privateElevated : BrowserTheme.elevated
        privateBadge.isHidden = !isPrivate
        let accent = isPrivate ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        textField.tintColor = accent
        progressView.progressTintColor = accent
        textField.snp.remakeConstraints { make in
            if isPrivate {
                make.leading.equalTo(privateBadge.snp.trailing).offset(6)
            } else {
                make.leading.equalTo(screenshotEntry.snp.trailing).offset(4)
            }
            make.trailing.equalTo(rightmostTrailingAnchor()).offset(-6)
            make.centerY.equalToSuperview()
        }
        updatePageCleanerAppearance()
        updateCleanerChipSelection()
        updateShieldAppearance()
    }

    func setProgress(_ progress: Double, isLoading: Bool) {
        progressView.isHidden = !isLoading
        progressView.setProgress(Float(progress), animated: true)
        if !isLoading {
            progressView.setProgress(0, animated: false)
        }
    }

    func hideScreenshotChips() {
        guard chipsVisible else { return }
        setChipsVisible(false)
    }

    func hideCleanerMenu() {
        guard cleanerMenuVisible else { return }
        setCleanerMenuVisible(false)
    }

    func setPageCleanerActive(_ active: Bool) {
        isPageCleanerActive = active
        if !active {
            cleanerURLOnly = nil
            hideCleanerMenu()
        }
        updatePageCleanerAppearance()
        updateCleanerChipSelection()
    }

    func setBlockCount(_ count: Int) {
        blockCount = max(0, count)
        updateShieldAppearance()
    }

    func setFocusIndicator(active: Bool) {
        focusActive = active
        updateShieldAppearance()
    }

    private func rightmostTrailingAnchor() -> ConstraintItem {
        if !shieldButton.isHidden {
            return shieldButton.snp.leading
        }
        return pageCleanerButton.snp.leading
    }

    private func updateShieldAppearance() {
        let show = AppSettings.trackerProtectionEnabled || AppSettings.hideShortsEnabled || AppSettings.youtubeAdShieldEnabled
        guard show else {
            shieldButton.isHidden = true
            shieldBadge.isHidden = true
            refreshTextFieldTrailing()
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
        refreshTextFieldTrailing()
    }

    private func refreshTextFieldTrailing() {
        textField.snp.remakeConstraints { make in
            if isPrivateMode {
                make.leading.equalTo(privateBadge.snp.trailing).offset(6)
            } else {
                make.leading.equalTo(screenshotEntry.snp.trailing).offset(4)
            }
            make.trailing.equalTo(rightmostTrailingAnchor()).offset(-6)
            make.centerY.equalToSuperview()
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        hideScreenshotChips()
        hideCleanerMenu()
        textField.textAlignment = .left
        textField.selectAll(nil)
        delegate?.addressBarDidBeginEditing()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        hideScreenshotChips()
        hideCleanerMenu()
        delegate?.addressBarDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    @objc private func pageCleanerTapped() {
        textField.resignFirstResponder()
        hideScreenshotChips()
        setCleanerMenuVisible(!cleanerMenuVisible)
    }

    @objc private func cleanerSiteTapped() {
        cleanerURLOnly = false
        updateCleanerChipSelection()
        setCleanerMenuVisible(false)
        delegate?.addressBarDidChoosePageCleaner(urlOnly: false)
    }

    @objc private func cleanerPageTapped() {
        cleanerURLOnly = true
        updateCleanerChipSelection()
        setCleanerMenuVisible(false)
        delegate?.addressBarDidChoosePageCleaner(urlOnly: true)
    }

    @objc private func cleanerExitTapped() {
        cleanerURLOnly = nil
        updateCleanerChipSelection()
        setCleanerMenuVisible(false)
        delegate?.addressBarDidExitPageCleaner()
    }

    @objc private func screenshotEntryTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        setChipsVisible(!chipsVisible)
    }

    @objc private func longShotTapped() {
        setChipsVisible(false)
        // Defer so dismiss animation / gesture cleanup doesn't cancel presentation.
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.addressBarDidRequestLongScreenshot()
        }
    }

    @objc private func manualShotTapped() {
        setChipsVisible(false)
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.addressBarDidRequestManualScreenshot()
        }
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        setChipsVisible(false)
        setCleanerMenuVisible(false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        if view === longShotChip || view === manualShotChip || view.isDescendant(of: chipsContainer) {
            return false
        }
        if view === cleanerSiteChip || view === cleanerPageChip || view === cleanerExitChip
            || view.isDescendant(of: cleanerMenuContainer) {
            return false
        }
        if view === screenshotEntry || view.isDescendant(of: screenshotEntry) {
            return false
        }
        if view === pageCleanerButton || view.isDescendant(of: pageCleanerButton) {
            return false
        }
        return true
    }

    private func updatePageCleanerAppearance() {
        let accent = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        pageCleanerButton.tintColor = isPageCleanerActive ? accent : BrowserTheme.textSecondary
        pageCleanerButton.accessibilityLabel = isPageCleanerActive ? "Cleaning mode" : "Clean page"
    }

    private func updateCleanerChipSelection() {
        let accent = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        applyCleanerChipStyle(cleanerSiteChip, selected: isPageCleanerActive && cleanerURLOnly == false, accent: accent)
        applyCleanerChipStyle(cleanerPageChip, selected: isPageCleanerActive && cleanerURLOnly == true, accent: accent)
        applyCleanerChipStyle(cleanerExitChip, selected: false, accent: accent)
    }

    private func applyCleanerChipStyle(_ button: UIButton, selected: Bool, accent: UIColor) {
        if selected {
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = accent
        } else {
            button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
            button.backgroundColor = BrowserTheme.secondaryCard
        }
    }

    private func setCleanerMenuVisible(_ visible: Bool) {
        cleanerMenuVisible = visible
        cleanerMenuContainer.isHidden = false
        bringSubviewToFront(cleanerMenuContainer)
        updatePageCleanerAppearance()

        if visible || chipsVisible {
            installDismissTap()
        } else {
            removeDismissTap()
        }

        UIView.animate(withDuration: 0.18, animations: {
            self.cleanerMenuContainer.alpha = visible ? 1 : 0
            self.cleanerMenuContainer.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 6)
        }, completion: { _ in
            if !visible {
                self.cleanerMenuContainer.isHidden = true
                self.cleanerMenuContainer.transform = .identity
            }
        })
    }

    private func setChipsVisible(_ visible: Bool) {
        chipsVisible = visible
        chipsContainer.isHidden = false
        bringSubviewToFront(chipsContainer)

        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        let chevronName = visible ? "chevron.up" : "chevron.up.chevron.down"
        chevronIcon.image = UIImage(systemName: chevronName, withConfiguration: chevronConfig)
        screenshotIcon.tintColor = visible ? BrowserTheme.chromeBlue : BrowserTheme.textSecondary
        chevronIcon.tintColor = visible ? BrowserTheme.chromeBlue : BrowserTheme.textSecondary

        if visible || cleanerMenuVisible {
            installDismissTap()
        } else {
            removeDismissTap()
        }

        UIView.animate(withDuration: 0.18, animations: {
            self.chipsContainer.alpha = visible ? 1 : 0
            self.chipsContainer.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 6)
        }, completion: { _ in
            if !visible {
                self.chipsContainer.isHidden = true
                self.chipsContainer.transform = .identity
            }
        })
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

/// Forwards hits to children that draw outside the chrome bounds (e.g. screenshot chips).
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

    /// UIStackView ignores points outside its bounds, so walk arranged subviews manually.
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
