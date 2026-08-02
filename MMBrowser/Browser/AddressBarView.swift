import UIKit
import SnapKit

protocol AddressBarViewDelegate: AnyObject {
    func addressBarDidSubmit(_ text: String)
    func addressBarDidBeginEditing()
    func addressBarDidTapReload()
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
    func addressBarDidTapShield(blockCount: Int)
}

final class AddressBarView: UIView, UITextFieldDelegate, UIGestureRecognizerDelegate {
    weak var delegate: AddressBarViewDelegate?

    private let container = UIView()
    private let reloadButton = UIButton(type: .system)
    private let richMenuButton = UIButton(type: .system)
    private let shieldButton = UIButton(type: .custom)
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
    private let cleanerSiteChip = UIButton(type: .system)
    private let cleanerPageChip = UIButton(type: .system)
    private let cleanerExitChip = UIButton(type: .system)
    private var cleanerMenuVisible = false
    private var dismissTap: UITapGestureRecognizer?
    private var tabSwipe: UIPanGestureRecognizer?
    private let swipeClip = UIView()
    private let peekLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = BrowserTheme.background

        container.backgroundColor = BrowserTheme.elevated
        container.layer.cornerRadius = 22
        addSubview(container)

        reloadButton.accessibilityLabel = "Reload"
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)

        richMenuButton.accessibilityLabel = "Page menu"
        richMenuButton.addTarget(self, action: #selector(richMenuTapped), for: .touchUpInside)

        let shieldConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
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
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )

        progressView.progressTintColor = BrowserTheme.chromeBlue
        progressView.trackTintColor = .clear
        progressView.isHidden = true

        swipeClip.clipsToBounds = true
        swipeClip.isUserInteractionEnabled = true
        peekLabel.font = .systemFont(ofSize: 15, weight: .medium)
        peekLabel.textAlignment = .center
        peekLabel.isUserInteractionEnabled = false
        peekLabel.alpha = 0

        container.addSubview(reloadButton)
        container.addSubview(privateBadge)
        container.addSubview(swipeClip)
        swipeClip.addSubview(textField)
        swipeClip.addSubview(peekLabel)
        container.addSubview(shieldButton)
        container.addSubview(shieldBadge)
        container.addSubview(richMenuButton)
        addSubview(progressView)

        setupCleanerMenu()
        setupTabSwipe()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)

        container.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.top.equalToSuperview().offset(4)
            make.height.equalTo(40)
        }
        reloadButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        privateBadge.snp.makeConstraints { make in
            make.leading.equalTo(reloadButton.snp.trailing).offset(6)
            make.centerY.equalToSuperview()
            make.height.equalTo(20)
            make.width.equalTo(52)
        }
        richMenuButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-10)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        shieldButton.snp.makeConstraints { make in
            make.trailing.equalTo(richMenuButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        shieldBadge.snp.makeConstraints { make in
            make.top.equalTo(shieldButton).offset(-4)
            make.trailing.equalTo(shieldButton).offset(6)
            make.height.equalTo(14)
            make.width.greaterThanOrEqualTo(14)
        }
        // Trailing is owned exclusively by refreshTextFieldConstraints() so it can track the
        // shield button without fighting a second trailing constraint to richMenuButton.
        swipeClip.snp.makeConstraints { make in
            make.leading.equalTo(reloadButton.snp.trailing).offset(8)
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
        configureChip(cleanerExitChip, title: "Exit")
        cleanerSiteChip.addTarget(self, action: #selector(cleanerSiteTapped), for: .touchUpInside)
        cleanerPageChip.addTarget(self, action: #selector(cleanerPageTapped), for: .touchUpInside)
        cleanerExitChip.addTarget(self, action: #selector(cleanerExitTapped), for: .touchUpInside)

        let title = makeBubbleTitleLabel("Cleaner mode")
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
        // Don't clobber in-progress typing; apply once editing ends.
        guard !textField.isFirstResponder else { return }
        textField.text = text
    }

    /// Updates the field even while editing (e.g. expand to the full URL on focus).
    func setURLTextForcing(_ text: String) {
        textField.text = text
    }

    func setPrivateMode(_ isPrivate: Bool) {
        isPrivateMode = isPrivate
        privateBadge.isHidden = !isPrivate
        refreshTextFieldConstraints()
        applyTheme()
    }

    @objc private func applyTheme() {
        backgroundColor = isPrivateMode ? BrowserTheme.privateBackground : BrowserTheme.background
        container.backgroundColor = isPrivateMode ? BrowserTheme.privateElevated : BrowserTheme.elevated
        let accent = isPrivateMode ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        reloadButton.setImage(ThemeManager.shared.image(for: .menuReload, pointSize: 16), for: .normal)
        reloadButton.tintColor = BrowserTheme.textSecondary
        richMenuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        richMenuButton.tintColor = BrowserTheme.textSecondary
        shieldButton.tintColor = BrowserTheme.textSecondary
        shieldBadge.backgroundColor = accent
        privateBadge.textColor = BrowserTheme.privateAccent
        privateBadge.backgroundColor = BrowserTheme.privateAccent.withAlphaComponent(0.18)
        textField.textColor = BrowserTheme.textPrimary
        textField.tintColor = accent
        peekLabel.textColor = BrowserTheme.textSecondary
        progressView.progressTintColor = accent
        cleanerMenuContainer.backgroundColor = BrowserTheme.elevated
        [cleanerSiteChip, cleanerPageChip, cleanerExitChip].forEach {
            $0.setTitleColor(BrowserTheme.textPrimary, for: .normal)
            $0.backgroundColor = BrowserTheme.secondaryCard
        }
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

    func hideCleanerMenu() {
        guard cleanerMenuVisible else { return }
        setCleanerMenuVisible(false)
    }

    /// Opens the cleaner mode bubble (used when Webpage Cleaner is chosen from the rich menu).
    func presentCleanerMenu() {
        textField.resignFirstResponder()
        setCleanerMenuVisible(true)
    }

    func setPageCleanerActive(_ active: Bool) {
        isPageCleanerActive = active
        if !active {
            cleanerURLOnly = nil
            hideCleanerMenu()
        }
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
        return richMenuButton.snp.leading
    }

    private func updateShieldAppearance() {
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
        swipeClip.snp.remakeConstraints { make in
            if isPrivateMode {
                make.leading.equalTo(privateBadge.snp.trailing).offset(6)
            } else {
                make.leading.equalTo(reloadButton.snp.trailing).offset(8)
            }
            make.trailing.equalTo(rightmostTrailingAnchor()).offset(-6)
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
        // Let the host expand to the full URL before selecting.
        delegate?.addressBarDidBeginEditing()
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        hideCleanerMenu()
        delegate?.addressBarDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    @objc private func reloadTapped() {
        textField.resignFirstResponder()
        hideCleanerMenu()
        delegate?.addressBarDidTapReload()
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
            // Swipe left → previous; swipe right → next.
            let towardPrevious = dx < 0
            let canCommitDirection = towardPrevious ? canPrevious : canNext
            let distanceOK = abs(dx) > width * 0.28 || abs(velocity.x) > 520
            let mostlyHorizontal = abs(dx) > abs(translation.y) * 1.2
            let shouldCommit = gesture.state == .ended
                && canCommitDirection
                && mostlyHorizontal
                && distanceOK
                && abs(dx) > 8

            if shouldCommit {
                let target = towardPrevious ? -width : width
                UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.applySwipeOffset(target, width: width, peekAlpha: 1)
                } completion: { _ in
                    if towardPrevious {
                        self.delegate?.addressBarDidSwipeToPreviousTab()
                    } else {
                        self.delegate?.addressBarDidSwipeToNextTab()
                    }
                    self.resetSwipeVisuals(animated: false)
                    // Settle the new URL in from the opposite side.
                    let enterFrom = towardPrevious ? width * 0.35 : -width * 0.35
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

        if offset < 0, !canPrevious {
            offset = rubberBand(offset, limit: width)
        } else if offset > 0, !canNext {
            offset = rubberBand(offset, limit: width)
        } else {
            // Soft clamp so it doesn't overshoot too far while dragging.
            let maxPull = width * 0.95
            offset = max(-maxPull, min(maxPull, offset))
        }

        let towardPrevious = offset < 0
        let canShowPeek = towardPrevious ? canPrevious : canNext
        if canShowPeek, abs(offset) > 1 {
            let adjacentOffset = towardPrevious ? -1 : 1
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
        setCleanerMenuVisible(false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        if gestureRecognizer === tabSwipe {
            if view === reloadButton || view.isDescendant(of: reloadButton) { return false }
            if view === richMenuButton || view.isDescendant(of: richMenuButton) { return false }
            if view === shieldButton || view.isDescendant(of: shieldButton) { return false }
            if view === textField || view.isDescendant(of: textField) { return !textField.isFirstResponder }
            return true
        }
        if view === cleanerSiteChip || view === cleanerPageChip || view === cleanerExitChip
            || view.isDescendant(of: cleanerMenuContainer) {
            return false
        }
        if view === reloadButton || view === richMenuButton || view === shieldButton { return false }
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

        if visible {
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
