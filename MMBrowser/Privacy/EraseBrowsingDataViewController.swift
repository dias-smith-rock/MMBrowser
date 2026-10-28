import UIKit
import SnapKit
import WebKit

/// One-tap erase for the current Space, every Space, or private tabs. Does not touch App Lock or Space Lock.
final class EraseBrowsingDataViewController: UIViewController {
    enum Mode {
        case space(name: String, containerID: UUID, sessionID: UUID)
        case privateTabs
    }

    var onFinished: ((Outcome) -> Void)?

    enum Outcome {
        case erasedSpaces([UUID])
        case closedPrivateTabs
    }

    private let mode: Mode
    private let allSpaces: [(id: UUID, sessionID: UUID)]
    private var scopeAll = false
    private var isErasing = false
    private let cookiesSwitch = UISwitch()
    private let historySwitch = UISwitch()
    private let cacheSwitch = UISwitch()
    private let bookmarksSwitch = UISwitch()
    private let downloadsSwitch = UISwitch()
    private let helperLabel = UILabel()

    init(mode: Mode, allSpaces: [(id: UUID, sessionID: UUID)]) {
        self.mode = mode
        self.allSpaces = allSpaces
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Erase browsing data"
        BrowserTheme.applyScreenChrome(to: self)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }

        switch mode {
        case .privateTabs:
            helperLabel.text = "Private tabs do not keep history or cookies after you close them. This does not hide your IP."
            stack.addArrangedSubview(helperLabel)
            stack.addArrangedSubview(makeActionButton(title: "Close all private tabs", destructive: true, action: #selector(closePrivateTapped)))
        case .space:
            let this = makeScopeButton(title: "This Space", selected: true, action: #selector(selectThisSpace))
            let all = makeScopeButton(title: "All Spaces", selected: false, action: #selector(selectAllSpaces))
            this.tag = 1
            all.tag = 2
            stack.addArrangedSubview(this)
            stack.addArrangedSubview(all)
            stack.addArrangedSubview(helperLabel)
            cookiesSwitch.isOn = true
            historySwitch.isOn = true
            cacheSwitch.isOn = true
            bookmarksSwitch.isOn = false
            downloadsSwitch.isOn = false
            stack.addArrangedSubview(toggleRow("Cookies and site data", cookiesSwitch))
            stack.addArrangedSubview(toggleRow("History", historySwitch))
            stack.addArrangedSubview(toggleRow("Cached files", cacheSwitch))
            stack.addArrangedSubview(toggleRow("Bookmarks", bookmarksSwitch))
            stack.addArrangedSubview(toggleRow("Downloads (shared across Spaces)", downloadsSwitch))
            stack.addArrangedSubview(makeActionButton(title: "Erase", destructive: true, action: #selector(eraseTapped)))
            refreshScopeChrome()
        }
        helperLabel.font = .systemFont(ofSize: 15)
        helperLabel.textColor = BrowserTheme.textSecondary
        helperLabel.numberOfLines = 0
    }

    private func refreshScopeChrome() {
        guard case .space(let name, _, _) = mode else { return }
        helperLabel.text = scopeAll
            ? "Clears browsing data in every Space. You will be signed out of sites in all Spaces."
            : "Clears data for “\(name)” only. Other Spaces stay signed in."
        for case let button as UIButton in view.subviews.flatMap({ ($0 as? UIStackView)?.arrangedSubviews ?? [] }) where button.tag == 1 || button.tag == 2 {
            let selected = (button.tag == 1 && !scopeAll) || (button.tag == 2 && scopeAll)
            button.backgroundColor = selected ? BrowserTheme.chromeBlue : BrowserTheme.card
            button.setTitleColor(selected ? .white : BrowserTheme.textPrimary, for: .normal)
        }
    }

    @objc private func selectThisSpace() {
        scopeAll = false
        refreshScopeChrome()
    }

    @objc private func selectAllSpaces() {
        scopeAll = true
        refreshScopeChrome()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func closePrivateTapped() {
        let done = onFinished
        dismiss(animated: true) { done?(.closedPrivateTabs) }
    }

    @objc private func eraseTapped() {
        if scopeAll {
            let alert = UIAlertController(
                title: "Erase data in all Spaces?",
                message: "This cannot be undone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Erase everything", style: .destructive) { [weak self] _ in
                self?.performErase()
            })
            present(alert, animated: true)
            return
        }
        performErase()
    }

    private func performErase() {
        guard case .space(_, let containerID, let sessionID) = mode else { return }
        guard !isErasing else { return }
        isErasing = true
        isModalInPresentation = true
        navigationController?.isModalInPresentation = true
        view.isUserInteractionEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false

        let targets: [(id: UUID, sessionID: UUID)] = scopeAll
            ? allSpaces
            : [(containerID, sessionID)]
        let options = BrowsingDataEraser.Options(
            cookiesAndSiteData: cookiesSwitch.isOn,
            history: historySwitch.isOn,
            cache: cacheSwitch.isOn,
            bookmarks: bookmarksSwitch.isOn,
            downloads: downloadsSwitch.isOn
        )
        let ids = targets.map(\.id)
        let finish = { [weak self] in
            guard let self else { return }
            let done = self.onFinished
            self.dismiss(animated: false) { done?(.erasedSpaces(ids)) }
        }
        if UIAccessibility.isReduceMotionEnabled {
            BrowsingDataEraser.erase(spaces: targets, options: options, completion: finish)
            return
        }

        let host = navigationController?.view ?? view!
        let fire = EraseFireOverlayView(frame: host.bounds)
        fire.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(fire)
        fire.play()

        var dataCleared = false
        var burnFinished = false
        let tryFinish = {
            guard dataCleared, burnFinished else { return }
            finish()
        }
        BrowsingDataEraser.erase(spaces: targets, options: options) {
            dataCleared = true
            tryFinish()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + EraseFireOverlayView.duration) {
            burnFinished = true
            tryFinish()
        }
    }

    private func toggleRow(_ title: String, _ toggle: UISwitch) -> UIView {
        let box = UIView()
        box.backgroundColor = BrowserTheme.card
        box.layer.cornerRadius = 12
        let label = UILabel()
        label.text = title
        label.textColor = BrowserTheme.textPrimary
        label.font = .systemFont(ofSize: 16)
        label.numberOfLines = 0
        box.addSubview(label)
        box.addSubview(toggle)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.trailing.lessThanOrEqualTo(toggle.snp.leading).offset(-12)
            make.top.bottom.equalToSuperview().inset(14)
        }
        toggle.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        return box
    }

    private func makeScopeButton(title: String, selected: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.layer.cornerRadius = 12
        button.backgroundColor = selected ? BrowserTheme.chromeBlue : BrowserTheme.card
        button.setTitleColor(selected ? .white : BrowserTheme.textPrimary, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.snp.makeConstraints { $0.height.equalTo(48) }
        return button
    }

    private func makeActionButton(title: String, destructive: Bool, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.layer.cornerRadius = 12
        button.backgroundColor = destructive ? .systemRed : BrowserTheme.chromeBlue
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.snp.makeConstraints { $0.height.equalTo(50) }
        return button
    }
}

enum BrowsingDataEraser {
    struct Options {
        var cookiesAndSiteData: Bool
        var history: Bool
        var cache: Bool
        var bookmarks: Bool
        var downloads: Bool
    }

    static func erase(spaces: [(id: UUID, sessionID: UUID)], options: Options, completion: @escaping () -> Void) {
        if options.history {
            for space in spaces {
                HistoryStore.shared.clear(containerID: space.id)
            }
        }
        if options.bookmarks {
            for space in spaces {
                BookmarkStore.shared.clear(containerID: space.id)
            }
        }
        if options.downloads {
            DownloadManager.shared.removeAll()
        }
        var types = Set<String>()
        if options.cookiesAndSiteData {
            types.formUnion([
                WKWebsiteDataTypeCookies,
                WKWebsiteDataTypeLocalStorage,
                WKWebsiteDataTypeSessionStorage,
                WKWebsiteDataTypeIndexedDBDatabases,
                WKWebsiteDataTypeWebSQLDatabases
            ])
        }
        if options.cache {
            types.formUnion([
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeOfflineWebApplicationCache
            ])
        }
        let sessionIDs = spaces.map(\.sessionID)
        TabSessionStore.clear(types: types, sessionIDs: sessionIDs, completion: completion)
    }

    static func clearSiteData(host: String, sessionID: UUID, completion: @escaping () -> Void) {
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache
        ]
        TabSessionStore.removeRecords(matchingHost: host, types: types, sessionID: sessionID, completion: completion)
    }
}

/// Full-page burn played over the erase sheet before the cleared page appears.
final class EraseFireOverlayView: UIView {
    static let duration: TimeInterval = 1.5

    /// Covers `host` for about 1.5s, then runs `completion` on the main queue.
    static func play(on host: UIView, then completion: @escaping () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            completion()
            return
        }
        let fire = EraseFireOverlayView(frame: host.bounds)
        fire.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(fire)
        fire.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            fire.removeFromSuperview()
            completion()
        }
    }

    private let ash = UIView()
    private let glow = CAGradientLayer()
    private let flames = CAEmitterLayer()
    private let smoke = CAEmitterLayer()
    private var displayLink: CADisplayLink?
    private var startedAt: CFTimeInterval = 0
    private var lastFlameSpawn: CFTimeInterval = 0
    private let flameImage = UIImage(systemName: "flame.fill")

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear

        ash.backgroundColor = UIColor(red: 0.07, green: 0.025, blue: 0.01, alpha: 1)
        addSubview(ash)

        glow.colors = [
            UIColor.clear.cgColor,
            UIColor(red: 1, green: 0.28, blue: 0.02, alpha: 0.15).cgColor,
            UIColor(red: 1, green: 0.62, blue: 0.08, alpha: 0.95).cgColor,
            UIColor(red: 1, green: 0.22, blue: 0, alpha: 0.0).cgColor
        ]
        glow.locations = [0, 0.25, 0.62, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0)
        glow.endPoint = CGPoint(x: 0.5, y: 1)
        layer.addSublayer(glow)

        flames.emitterShape = .line
        flames.emitterMode = .outline
        flames.renderMode = .additive
        flames.emitterCells = [
            flameCell(color: UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 0.95), scale: 0.22, birthRate: 140, lifetime: 0.45, velocity: 120),
            flameCell(color: UIColor(red: 1, green: 0.48, blue: 0.05, alpha: 0.9), scale: 0.42, birthRate: 80, lifetime: 0.7, velocity: 80),
            flameCell(color: UIColor(red: 0.95, green: 0.16, blue: 0.02, alpha: 0.75), scale: 0.7, birthRate: 36, lifetime: 0.9, velocity: 46)
        ]
        layer.addSublayer(flames)

        smoke.emitterShape = .line
        smoke.renderMode = .unordered
        smoke.emitterCells = [
            flameCell(color: UIColor(white: 0.15, alpha: 0.35), scale: 0.8, birthRate: 18, lifetime: 1.1, velocity: 30)
        ]
        layer.addSublayer(smoke)
    }

    required init?(coder: NSCoder) { fatalError() }

    func play() {
        layoutFire(progress: 0)
        startedAt = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func removeFromSuperview() {
        displayLink?.invalidate()
        displayLink = nil
        super.removeFromSuperview()
    }

    @objc private func tick() {
        let elapsed = CACurrentMediaTime() - startedAt
        let t = min(1, elapsed / Self.duration)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        let progress = CGFloat(eased)
        layoutFire(progress: progress)
        if elapsed - lastFlameSpawn > 0.07 {
            lastFlameSpawn = elapsed
            spawnFlameMark(progress: progress)
        }
        if t >= 1 {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func layoutFire(progress: CGFloat) {
        let burned = bounds.height * progress
        let front = bounds.height - burned
        ash.frame = CGRect(x: 0, y: front, width: bounds.width, height: max(burned, 0))
        glow.frame = CGRect(x: 0, y: front - 36, width: bounds.width, height: 84)
        let origin = CGPoint(x: bounds.midX, y: front)
        let size = CGSize(width: bounds.width, height: 8)
        flames.emitterPosition = origin
        flames.emitterSize = size
        smoke.emitterPosition = CGPoint(x: bounds.midX, y: front - 12)
        smoke.emitterSize = size
    }

    private func spawnFlameMark(progress: CGFloat) {
        guard let flameImage, bounds.width > 1 else { return }
        let size = CGFloat.random(in: 26...64)
        let mark = UIImageView(image: flameImage)
        mark.tintColor = Bool.random()
            ? UIColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)
            : UIColor(red: 1, green: 0.22, blue: 0.02, alpha: 1)
        let x = CGFloat.random(in: 0...max(bounds.width - size, 0))
        let front = bounds.height * (1 - progress)
        mark.frame = CGRect(x: x, y: front - size * 0.35, width: size, height: size)
        mark.alpha = 0
        addSubview(mark)
        UIView.animate(withDuration: 0.55, delay: 0, options: [.curveEaseOut]) {
            mark.alpha = 1
            mark.frame.origin.y -= CGFloat.random(in: 70...150)
            mark.transform = CGAffineTransform(scaleX: 1.25, y: 1.35)
        } completion: { _ in
            UIView.animate(withDuration: 0.2, animations: {
                mark.alpha = 0
            }, completion: { _ in
                mark.removeFromSuperview()
            })
        }
    }

    private func flameCell(color: UIColor, scale: CGFloat, birthRate: Float, lifetime: Float, velocity: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = Self.blob
        cell.color = color.cgColor
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetime * 0.25
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.45
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = 0.55
        cell.scale = scale
        cell.scaleRange = scale * 0.45
        cell.scaleSpeed = 0.12
        cell.alphaSpeed = -1 / max(lifetime, 0.2)
        cell.yAcceleration = -30
        cell.spin = 0.6
        cell.spinRange = 1.2
        return cell
    }

    private static let blob: CGImage? = {
        let diameter: CGFloat = 48
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter))
        let image = renderer.image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: diameter / 2,
                options: []
            )
        }
        return image.cgImage
    }()
}
