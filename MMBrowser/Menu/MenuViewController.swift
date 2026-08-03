import UIKit
import SnapKit

enum MenuAction: Equatable {
    case bookmarks, history, readingList, downloads, settings
    case reload, newTab, newIncognitoTab, addBookmark, addReadingList
    case readerMode, findInPage, share, desktopSite, sharePDF, screenshot, longScreenshot
    case pageCleaner
    case copyURL, aboutSite, addToHomepage, printPage, translate, changeTextSize, adBlocker
    case pictureInPicture
    case accountLogin, setDefaultBrowser, passwords, backgroundGallery, theme, feedback
    case placeholder(String)
}

protocol MenuViewControllerDelegate: AnyObject {
    func menuDidSelect(_ action: MenuAction)
}

/// Toolbar app menu: account, libraries, appearance shortcuts.
final class MenuViewController: UIViewController {
    weak var delegate: MenuViewControllerDelegate?
    private let isIncognito: Bool
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    init(isIncognito: Bool = false) {
        self.isIncognito = isIncognito
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = isIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
        modalPresentationStyle = .pageSheet
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-24)
            make.width.equalTo(scrollView).offset(-32)
        }

        stack.addArrangedSubview(makeAccountCard())
        stack.addArrangedSubview(makeGridCard(items: libraryItems()))
        stack.addArrangedSubview(makeGridCard(items: extrasItems()))
    }

    // MARK: - Data

    private func libraryItems() -> [(String, String, MenuAction)] {
        var items: [(String, String, MenuAction)] = [
            ("Settings", "gearshape", .settings),
            ("New tab", "plus.square", .newTab),
            ("Incognito tab", "theatermasks", .newIncognitoTab),
            ("Passwords", "key", .passwords),
            ("Downloads", "arrow.down.circle", .downloads),
            ("Bookmarks", "bookmark", .bookmarks),
            ("History", "clock", .history),
            ("Reading list", "text.book.closed", .readingList)
        ]
        if isIncognito {
            items.removeAll { $0.2 == .downloads }
        }
        return items
    }

    private func extrasItems() -> [(String, String, MenuAction)] {
        [
            ("Background gallery", "photo.on.rectangle", .backgroundGallery),
            ("Theme", "paintpalette", .theme),
            ("Feedback", "bubble.left", .feedback)
        ]
    }

    // MARK: - Card 1: Account + default browser

    private func makeAccountCard() -> UIView {
        let card = makeCard()

        let avatar = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
        avatar.tintColor = BrowserTheme.textSecondary
        avatar.contentMode = .scaleAspectFit

        let name = UILabel()
        name.text = "User"
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = BrowserTheme.textPrimary

        let status = UILabel()
        status.text = "Not logged in"
        status.font = .systemFont(ofSize: 13, weight: .regular)
        status.textColor = BrowserTheme.textSecondary

        let textStack = UIStackView(arrangedSubviews: [name, status])
        textStack.axis = .vertical
        textStack.spacing = 2

        let login = UIButton(type: .system)
        login.setTitle("Log in", for: .normal)
        login.setTitleColor(BrowserTheme.background, for: .normal)
        login.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        login.backgroundColor = BrowserTheme.textPrimary
        login.layer.cornerRadius = 16
        login.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        login.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        let accountRow = UIView()
        accountRow.addSubview(avatar)
        accountRow.addSubview(textStack)
        accountRow.addSubview(login)
        avatar.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(avatar.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(login.snp.leading).offset(-10)
        }
        login.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
            make.height.equalTo(32)
        }
        accountRow.snp.makeConstraints { make in make.height.equalTo(64) }

        let defaultBanner = makeDefaultBrowserBanner()

        let column = UIStackView(arrangedSubviews: [accountRow, defaultBanner])
        column.axis = .vertical
        column.spacing = 10
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 6, left: 0, bottom: 12, right: 0)
        card.addSubview(column)
        column.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        return card
    }

    private func makeDefaultBrowserBanner() -> UIView {
        let wrap = UIView()
        let button = MenuActionButton(action: .setDefaultBrowser)
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.accessibilityLabel = "Make MMBrowser the default browser"

        let gradient = CAGradientLayer()
        gradient.colors = [
            ThemeHex.color("7B5CFF").cgColor,
            ThemeHex.color("FF7A45").cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        button.layer.insertSublayer(gradient, at: 0)
        button.layoutSubviewsHook = { [weak button] in
            guard let button else { return }
            button.layer.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = button.bounds
        }

        let icon = UIImageView(image: UIImage(systemName: "safari"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Make MMBrowser the default browser"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.numberOfLines = 2

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.85)
        chevron.contentMode = .scaleAspectFit

        wrap.addSubview(button)
        button.addSubview(icon)
        button.addSubview(label)
        button.addSubview(chevron)

        button.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.top.bottom.equalToSuperview()
            make.height.equalTo(52)
        }
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(10)
            make.trailing.equalTo(chevron.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
        chevron.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(14)
        }
        return wrap
    }

    // MARK: - Grid cards

    private func makeGridCard(items: [(String, String, MenuAction)]) -> UIView {
        let card = makeCard()
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 10
        grid.isLayoutMarginsRelativeArrangement = true
        grid.layoutMargins = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)

        let columns = 4
        var row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        row.alignment = .top

        for (index, item) in items.enumerated() {
            if index > 0, index % columns == 0 {
                grid.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.spacing = 8
                row.distribution = .fillEqually
                row.alignment = .top
            }
            row.addArrangedSubview(makeGridItem(title: item.0, symbol: item.1, action: item.2))
        }
        // Pad last row so tiles stay equal width.
        let remainder = items.count % columns
        if remainder != 0 {
            for _ in remainder..<columns {
                row.addArrangedSubview(UIView())
            }
        }
        grid.addArrangedSubview(row)

        card.addSubview(grid)
        grid.snp.makeConstraints { make in make.edges.equalToSuperview() }
        return card
    }

    private func makeGridItem(title: String, symbol: String, action: MenuAction) -> UIView {
        let container = UIView()
        let box = UIView()
        box.backgroundColor = BrowserTheme.secondaryCard
        box.layer.cornerRadius = 14

        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = isIncognito ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        image.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = BrowserTheme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 2

        let button = MenuActionButton(action: action)
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        button.accessibilityLabel = title

        container.addSubview(box)
        box.addSubview(image)
        container.addSubview(label)
        container.addSubview(button)

        box.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(52)
        }
        image.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.top.equalTo(box.snp.bottom).offset(6)
            make.leading.trailing.bottom.equalToSuperview()
        }
        button.snp.makeConstraints { make in make.edges.equalToSuperview() }
        return container
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = isIncognito ? BrowserTheme.privateElevated : BrowserTheme.elevated
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        return card
    }

    // MARK: - Actions

    @objc private func actionTapped(_ sender: MenuActionButton) {
        delegate?.menuDidSelect(sender.menuAction)
    }

    @objc private func loginTapped() {
        delegate?.menuDidSelect(.accountLogin)
    }
}

final class MenuActionButton: UIButton {
    let menuAction: MenuAction
    /// Optional layout hook (used to keep gradient layers sized).
    var layoutSubviewsHook: (() -> Void)?

    init(action: MenuAction) {
        self.menuAction = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSubviewsHook?()
    }
}
