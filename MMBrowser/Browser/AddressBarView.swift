import UIKit
import SnapKit

protocol AddressBarViewDelegate: AnyObject {
    func addressBarDidSubmit(_ text: String)
    func addressBarDidTapPageCleaner()
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
    private let privateBadge = UILabel()
    let textField = UITextField()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var isPrivateMode = false

    private let chipsContainer = UIView()
    private let longShotChip = UIButton(type: .system)
    private let manualShotChip = UIButton(type: .system)
    private var chipsVisible = false
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
        container.addSubview(pageCleanerButton)
        addSubview(progressView)

        setupChips()

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
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(screenshotEntry.snp.trailing).offset(4)
            make.trailing.equalTo(pageCleanerButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(container.snp.top)
            make.height.equalTo(2)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Chips draw above our bounds; include them in hit testing.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) { return true }
        guard chipsVisible, !chipsContainer.isHidden else { return false }
        let p = convert(point, to: chipsContainer)
        return chipsContainer.point(inside: p, with: event)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        if chipsVisible, !chipsContainer.isHidden {
            let p = convert(point, to: chipsContainer)
            if let hit = chipsContainer.hitTest(p, with: event) {
                return hit
            }
        }
        return super.hitTest(point, with: event)
    }

    private func setupChips() {
        chipsContainer.isHidden = true
        chipsContainer.alpha = 0
        chipsContainer.transform = CGAffineTransform(translationX: 0, y: 6)
        chipsContainer.backgroundColor = BrowserTheme.elevated
        chipsContainer.layer.cornerRadius = 16
        chipsContainer.layer.borderWidth = 1
        chipsContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        chipsContainer.layer.shadowColor = UIColor.black.cgColor
        chipsContainer.layer.shadowOpacity = 0.35
        chipsContainer.layer.shadowRadius = 10
        chipsContainer.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(chipsContainer)

        configureChip(longShotChip, title: "长截屏")
        configureChip(manualShotChip, title: "手动截图")
        longShotChip.addTarget(self, action: #selector(longShotTapped), for: .touchUpInside)
        manualShotChip.addTarget(self, action: #selector(manualShotTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [longShotChip, manualShotChip])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        chipsContainer.addSubview(stack)

        chipsContainer.snp.makeConstraints { make in
            make.leading.equalTo(container.snp.leading)
            make.bottom.equalTo(container.snp.top).offset(-8)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
        }
    }

    private func configureChip(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = BrowserTheme.secondaryCard
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
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
            make.trailing.equalTo(pageCleanerButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
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

    func textFieldDidBeginEditing(_ textField: UITextField) {
        hideScreenshotChips()
        textField.textAlignment = .left
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        hideScreenshotChips()
        delegate?.addressBarDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    @objc private func pageCleanerTapped() {
        hideScreenshotChips()
        delegate?.addressBarDidTapPageCleaner()
    }

    @objc private func screenshotEntryTapped() {
        textField.resignFirstResponder()
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
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        if view === longShotChip || view === manualShotChip || view.isDescendant(of: chipsContainer) {
            return false
        }
        if view === screenshotEntry || view.isDescendant(of: screenshotEntry) {
            return false
        }
        return true
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

        if visible {
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
