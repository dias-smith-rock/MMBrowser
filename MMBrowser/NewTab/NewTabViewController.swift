import UIKit
import SnapKit

protocol NewTabViewControllerDelegate: AnyObject {
    func newTabDidSubmit(_ text: String)
    func newTabDidRequestIncognito()
    func newTabDidOpenURL(_ url: URL)
    func newTabDidTapSeeMoreContinue()
    func newTabDidRequestEditShortcuts()
    func newTabDidRequestSettings()
}

final class NewTabViewController: UIViewController {
    weak var delegate: NewTabViewControllerDelegate?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let editButton = UIButton(type: .system)
    private let signInButton = UIButton(type: .system)
    private let logoView = GoogleLogoView()
    private let searchContainer = UIView()
    private let searchField = UITextField()
    private let aiButton = UIButton(type: .system)
    private let incognitoButton = UIButton(type: .system)
    private let shortcutsScroll = UIScrollView()
    private let shortcutsStack = UIStackView()
    private let continueCard = UIView()
    private let continueTitleLabel = UILabel()
    private let continueMetaLabel = UILabel()
    private let seeMoreButton = UIButton(type: .system)
    private let discoverStack = UIStackView()
    private var isEditingShortcuts = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        setupLayout()
        applyHomeSettings()
        reloadShortcuts()
        reloadContinue()
        reloadDiscover()
        NotificationCenter.default.addObserver(self, selector: #selector(applyHomeSettings), name: .homeSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(engineChanged), name: .searchEngineChanged, object: nil)
    }

    @objc func applyHomeSettings() {
        shortcutsScroll.isHidden = !AppSettings.showShortcuts
        continueCard.isHidden = continueCard.isHidden || !AppSettings.showContinue
        if !AppSettings.showContinue { continueCard.isHidden = true }
        discoverStack.isHidden = !AppSettings.showDiscover
        discoverStack.superview?.subviews.forEach { v in
            if let label = v as? UILabel, label.text == "Discover" {
                label.isHidden = !AppSettings.showDiscover
            }
        }
        let colors: [UIColor] = [
            BrowserTheme.background,
            UIColor(red: 0.08, green: 0.12, blue: 0.22, alpha: 1),
            UIColor(red: 0.07, green: 0.14, blue: 0.10, alpha: 1),
            UIColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
        ]
        view.backgroundColor = colors[AppSettings.homeWallpaperIndex % colors.count]
        engineChanged()
    }

    @objc private func engineChanged() {
        let name = SearchEngineManager.current.name
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search \(name) or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )
    }

    func reloadShortcuts() {
        shortcutsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in ShortcutStore.shared.items {
            shortcutsStack.addArrangedSubview(makeShortcutView(item))
        }
        shortcutsStack.addArrangedSubview(makeAddShortcutView())
    }

    func reloadContinue(from tabs: [BrowserTab] = []) {
        guard AppSettings.showContinue else {
            continueCard.isHidden = true
            return
        }
        let recent = tabs.first
        if let tab = recent, let url = tab.url {
            continueCard.isHidden = false
            continueTitleLabel.text = tab.title
            let host = url.host ?? ""
            continueMetaLabel.text = "\(host) · \(relativeTime(tab.lastAccessed))"
        } else if let history = HistoryStore.shared.items.first {
            continueCard.isHidden = false
            continueTitleLabel.text = history.title
            continueMetaLabel.text = "\(history.url?.host ?? "") · \(relativeTime(history.date))"
        } else {
            continueCard.isHidden = true
        }
    }

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag

        scrollView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        editButton.setImage(UIImage(systemName: "pencil"), for: .normal)
        editButton.tintColor = BrowserTheme.textPrimary
        editButton.backgroundColor = BrowserTheme.elevated
        editButton.layer.cornerRadius = 18
        editButton.addTarget(self, action: #selector(editTapped), for: .touchUpInside)

        signInButton.setTitle("Settings", for: .normal)
        signInButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        signInButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        signInButton.layer.cornerRadius = 16
        signInButton.layer.borderWidth = 1
        signInButton.layer.borderColor = UIColor(white: 0.35, alpha: 1).cgColor
        signInButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        signInButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        searchContainer.backgroundColor = BrowserTheme.elevated
        searchContainer.layer.cornerRadius = 28

        let gIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        gIcon.tintColor = BrowserTheme.chromeBlue
        gIcon.contentMode = .scaleAspectFit

        searchField.textColor = BrowserTheme.textPrimary
        searchField.tintColor = BrowserTheme.chromeBlue
        searchField.font = .systemFont(ofSize: 16)
        searchField.returnKeyType = .go
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.delegate = self
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )

        let mic = UIButton(type: .system)
        mic.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        mic.tintColor = BrowserTheme.textSecondary
        mic.addTarget(self, action: #selector(placeholderFeature), for: .touchUpInside)

        let lens = UIButton(type: .system)
        lens.setImage(UIImage(systemName: "camera.viewfinder"), for: .normal)
        lens.tintColor = BrowserTheme.textSecondary
        lens.addTarget(self, action: #selector(placeholderFeature), for: .touchUpInside)

        searchContainer.addSubview(gIcon)
        searchContainer.addSubview(searchField)
        searchContainer.addSubview(mic)
        searchContainer.addSubview(lens)

        styleChip(aiButton, title: "Search", systemName: "magnifyingglass")
        styleChip(incognitoButton, title: "Incognito", systemName: "eye.slash")
        aiButton.addTarget(self, action: #selector(placeholderFeature), for: .touchUpInside)
        incognitoButton.addTarget(self, action: #selector(incognitoTapped), for: .touchUpInside)
        let chipStack = UIStackView(arrangedSubviews: [aiButton, incognitoButton])
        chipStack.axis = .horizontal
        chipStack.spacing = 12
        chipStack.distribution = .fillEqually

        shortcutsScroll.showsHorizontalScrollIndicator = false
        shortcutsStack.axis = .horizontal
        shortcutsStack.spacing = 16
        shortcutsScroll.addSubview(shortcutsStack)

        continueCard.backgroundColor = BrowserTheme.card
        continueCard.layer.cornerRadius = 16
        let continueHeader = UILabel()
        continueHeader.text = "Continue with this tab"
        continueHeader.textColor = BrowserTheme.textPrimary
        continueHeader.font = .systemFont(ofSize: 16, weight: .semibold)
        seeMoreButton.setTitle("See more", for: .normal)
        seeMoreButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        seeMoreButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        seeMoreButton.addTarget(self, action: #selector(seeMoreTapped), for: .touchUpInside)
        continueTitleLabel.textColor = BrowserTheme.textPrimary
        continueTitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        continueTitleLabel.numberOfLines = 2
        continueMetaLabel.textColor = BrowserTheme.textSecondary
        continueMetaLabel.font = .systemFont(ofSize: 12)
        let continueTap = UITapGestureRecognizer(target: self, action: #selector(continueTapped))
        continueCard.addGestureRecognizer(continueTap)
        continueCard.addSubview(continueHeader)
        continueCard.addSubview(seeMoreButton)
        continueCard.addSubview(continueTitleLabel)
        continueCard.addSubview(continueMetaLabel)

        let discoverHeader = UILabel()
        discoverHeader.text = "Discover"
        discoverHeader.textColor = BrowserTheme.textPrimary
        discoverHeader.font = .systemFont(ofSize: 18, weight: .semibold)

        discoverStack.axis = .vertical
        discoverStack.spacing = 12

        [editButton, signInButton, logoView, searchContainer, chipStack, shortcutsScroll, continueCard, discoverHeader, discoverStack].forEach {
            contentView.addSubview($0)
        }

        editButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.equalToSuperview().offset(16)
            make.size.equalTo(36)
        }
        signInButton.snp.makeConstraints { make in
            make.centerY.equalTo(editButton)
            make.trailing.equalToSuperview().offset(-16)
        }
        logoView.snp.makeConstraints { make in
            make.top.equalTo(editButton.snp.bottom).offset(36)
            make.centerX.equalToSuperview()
            make.height.equalTo(52)
            make.width.equalTo(260)
        }
        searchContainer.snp.makeConstraints { make in
            make.top.equalTo(logoView.snp.bottom).offset(28)
            make.leading.equalToSuperview().offset(20)
            make.trailing.equalToSuperview().offset(-20)
            make.height.equalTo(56)
        }
        gIcon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        lens.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        mic.snp.makeConstraints { make in
            make.trailing.equalTo(lens.snp.leading).offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(20)
        }
        searchField.snp.makeConstraints { make in
            make.leading.equalTo(gIcon.snp.trailing).offset(10)
            make.trailing.equalTo(mic.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
        chipStack.snp.makeConstraints { make in
            make.top.equalTo(searchContainer.snp.bottom).offset(14)
            make.leading.trailing.equalTo(searchContainer)
            make.height.equalTo(40)
        }
        shortcutsScroll.snp.makeConstraints { make in
            make.top.equalTo(chipStack.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(92)
        }
        shortcutsStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
            make.height.equalToSuperview()
        }
        continueCard.snp.makeConstraints { make in
            make.top.equalTo(shortcutsScroll.snp.bottom).offset(20)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
        }
        continueHeader.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(14)
        }
        seeMoreButton.snp.makeConstraints { make in
            make.centerY.equalTo(continueHeader)
            make.trailing.equalToSuperview().offset(-14)
        }
        continueTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(continueHeader.snp.bottom).offset(12)
            make.leading.equalToSuperview().offset(14)
            make.trailing.equalToSuperview().offset(-14)
        }
        continueMetaLabel.snp.makeConstraints { make in
            make.top.equalTo(continueTitleLabel.snp.bottom).offset(6)
            make.leading.equalToSuperview().offset(14)
            make.trailing.equalToSuperview().offset(-14)
            make.bottom.equalToSuperview().offset(-14)
        }
        discoverHeader.snp.makeConstraints { make in
            make.top.equalTo(continueCard.snp.bottom).offset(24)
            make.leading.equalToSuperview().offset(16)
        }
        discoverStack.snp.makeConstraints { make in
            make.top.equalTo(discoverHeader.snp.bottom).offset(12)
            make.leading.equalToSuperview().offset(16)
            make.trailing.equalToSuperview().offset(-16)
            make.bottom.equalToSuperview().offset(-24)
        }
    }

    private func reloadDiscover() {
        discoverStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in DiscoverMock.items.enumerated() {
            let card = makeDiscoverCard(item)
            card.tag = index
            discoverStack.addArrangedSubview(card)
        }
    }

    private func styleChip(_ button: UIButton, title: String, systemName: String) {
        button.setTitle("  \(title)", for: .normal)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = BrowserTheme.textPrimary
        button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.backgroundColor = BrowserTheme.elevated
        button.layer.cornerRadius = 20
    }

    private func makeShortcutView(_ item: ShortcutItem) -> UIView {
        let container = UIView()
        container.snp.makeConstraints { make in make.width.equalTo(72) }

        let avatar = LetterAvatarView()
        avatar.configure(title: item.title, colorSeed: item.urlString)
        let title = UILabel()
        title.text = item.title
        title.textColor = BrowserTheme.textSecondary
        title.font = .systemFont(ofSize: 11)
        title.textAlignment = .center
        title.numberOfLines = 2

        let button = ShortcutTapButton(item: item)
        button.addTarget(self, action: #selector(shortcutButtonTapped(_:)), for: .touchUpInside)

        container.addSubview(avatar)
        container.addSubview(title)
        container.addSubview(button)
        avatar.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(56)
        }
        title.snp.makeConstraints { make in
            make.top.equalTo(avatar.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }

        if isEditingShortcuts {
            let badge = UILabel()
            badge.text = "−"
            badge.textAlignment = .center
            badge.textColor = .white
            badge.backgroundColor = .systemRed
            badge.font = .systemFont(ofSize: 14, weight: .bold)
            badge.layer.cornerRadius = 10
            badge.clipsToBounds = true
            container.addSubview(badge)
            badge.snp.makeConstraints { make in
                make.top.trailing.equalTo(avatar)
                make.size.equalTo(20)
            }
        }
        return container
    }

    private func makeAddShortcutView() -> UIView {
        let container = UIView()
        container.snp.makeConstraints { make in make.width.equalTo(72) }
        let circle = UIView()
        circle.backgroundColor = BrowserTheme.elevated
        circle.layer.cornerRadius = 28
        let plus = UIImageView(image: UIImage(systemName: "plus"))
        plus.tintColor = BrowserTheme.textPrimary
        plus.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "Add"
        title.textColor = BrowserTheme.textSecondary
        title.font = .systemFont(ofSize: 11)
        title.textAlignment = .center
        let button = UIButton(type: .custom)
        button.addTarget(self, action: #selector(addShortcutTapped), for: .touchUpInside)
        container.addSubview(circle)
        circle.addSubview(plus)
        container.addSubview(title)
        container.addSubview(button)
        circle.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(56)
        }
        plus.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }
        title.snp.makeConstraints { make in
            make.top.equalTo(circle.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        return container
    }

    private func makeDiscoverCard(_ item: DiscoverItem) -> UIView {
        let card = UIView()
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16

        let title = UILabel()
        title.text = item.title
        title.textColor = BrowserTheme.textPrimary
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.numberOfLines = 3

        let meta = UILabel()
        meta.text = "\(item.source) · \(item.timeText)"
        meta.textColor = BrowserTheme.textSecondary
        meta.font = .systemFont(ofSize: 12)

        let thumb = UIView()
        thumb.backgroundColor = UIColor(rgb: item.accentColorHex)
        thumb.layer.cornerRadius = 10

        let button = DiscoverTapButton(urlString: item.urlString)
        button.addTarget(self, action: #selector(discoverButtonTapped(_:)), for: .touchUpInside)

        card.addSubview(title)
        card.addSubview(meta)
        card.addSubview(thumb)
        card.addSubview(button)
        thumb.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 72, height: 72))
        }
        title.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().offset(14)
            make.trailing.equalTo(thumb.snp.leading).offset(-12)
        }
        meta.snp.makeConstraints { make in
            make.leading.equalTo(title)
            make.bottom.equalToSuperview().offset(-14)
            make.trailing.equalTo(thumb.snp.leading).offset(-12)
        }
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        card.snp.makeConstraints { make in make.height.greaterThanOrEqualTo(96) }
        return card
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    @objc private func editTapped() {
        isEditingShortcuts.toggle()
        reloadShortcuts()
        if isEditingShortcuts {
            Toast.show("Tap a shortcut to remove", from: self)
        }
        delegate?.newTabDidRequestEditShortcuts()
    }

    @objc private func settingsTapped() {
        delegate?.newTabDidRequestSettings()
    }

    @objc private func placeholderFeature() {
        if let url = URL(string: SearchEngineManager.current.homeURL) {
            delegate?.newTabDidOpenURL(url)
        }
    }

    @objc private func incognitoTapped() {
        delegate?.newTabDidRequestIncognito()
    }

    @objc private func seeMoreTapped() {
        delegate?.newTabDidTapSeeMoreContinue()
    }

    @objc private func continueTapped() {
        if let history = HistoryStore.shared.items.first, let url = history.url {
            delegate?.newTabDidOpenURL(url)
        }
    }

    @objc private func addShortcutTapped() {
        let alert = UIAlertController(title: "Add shortcut", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Title" }
        alert.addTextField {
            $0.placeholder = "URL"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { [weak self] _ in
            let title = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let urlText = alert.textFields?[1].text ?? ""
            let url = URLInputResolver.resolve(urlText)
            let name = title.isEmpty ? (url.host ?? "Shortcut") : title
            ShortcutStore.shared.add(title: name, url: url)
            self?.reloadShortcuts()
        }))
        present(alert, animated: true)
    }

    @objc private func shortcutButtonTapped(_ sender: ShortcutTapButton) {
        let item = sender.item
        if isEditingShortcuts {
            ShortcutStore.shared.remove(id: item.id)
            reloadShortcuts()
        } else if let url = item.url {
            delegate?.newTabDidOpenURL(url)
        }
    }

    @objc private func discoverButtonTapped(_ sender: DiscoverTapButton) {
        if let url = URL(string: sender.urlString) {
            delegate?.newTabDidOpenURL(url)
        }
    }

}

private final class ShortcutTapButton: UIButton {
    let item: ShortcutItem
    init(item: ShortcutItem) {
        self.item = item
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class DiscoverTapButton: UIButton {
    let urlString: String
    init(urlString: String) {
        self.urlString = urlString
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
}

extension NewTabViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.newTabDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
