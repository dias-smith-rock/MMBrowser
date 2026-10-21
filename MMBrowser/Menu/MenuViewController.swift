import UIKit
import SnapKit

enum MenuAction: Equatable {
    case bookmarks, history, watchLater, readingList, downloads, settings, accounts, compareAccounts
    case reload, newTab, newIncognitoTab, addBookmark, addReadingList
    case readerMode, findInPage, share, userAgent, sharePDF, screenshot, longScreenshot
    case pageCleaner
    case downloadFile
    case copyURL, aboutSite, addToHomepage, printPage, translate, changeTextSize, adBlocker
    case pictureInPicture
    case setDefaultBrowser, passwords, backgroundGallery, theme, feedback
    case placeholder(String)
}

protocol MenuViewControllerDelegate: AnyObject {
    func menuDidSelect(_ action: MenuAction)
}

/// Toolbar app menu: libraries, appearance shortcuts, and default-browser promo.
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

        // Hidden until Apple grants `com.apple.developer.web-browser`.
        if DefaultBrowserFeature.isEnabled {
            stack.addArrangedSubview(makeDefaultBrowserCard())
        }
        stack.addArrangedSubview(makeGridCard(items: libraryItems()))
        stack.addArrangedSubview(makeGridCard(items: extrasItems()))
    }

    // MARK: - Data

    private func libraryItems() -> [(String, String, MenuAction)] {
        var items: [(String, String, MenuAction)] = [
            ("Spaces", "person.2", .accounts),
            ("Settings", "gearshape", .settings),
            ("Split View", "rectangle.split.1x2", .compareAccounts),
            ("Passwords (Isolated)", "key", .passwords),
            ("Downloads (Shared)", "arrow.down.circle", .downloads),
            ("Bookmarks (Isolated)", "bookmark", .bookmarks),
            ("History (Isolated)", "clock", .history),
            ("Watch Later (Isolated)", "clock.badge.checkmark", .watchLater),
            ("Reading list (Isolated)", "text.book.closed", .readingList)
        ]
        if isIncognito {
            items.removeAll { $0.2 == .downloads || $0.2 == .accounts }
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

    // MARK: - Card 1: Default browser

    private func makeDefaultBrowserCard() -> UIView {
        DefaultBrowserPromoUI.makeCard(
            cardColor: isIncognito ? BrowserTheme.privateElevated : BrowserTheme.elevated
        ) { [weak self] in
            guard let self else { return }
            self.delegate?.menuDidSelect(.setDefaultBrowser)
        }
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

/// Shared “set as default browser” promo used on NTP, page menu, and app menu.
enum DefaultBrowserPromoUI {
    static func makeBanner(onTap: @escaping () -> Void) -> UIView {
        let wrap = UIView()
        let button = GradientActionButton()
        button.addAction(UIAction { _ in onTap() }, for: .touchUpInside)
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.accessibilityLabel = "Make XBrowser the default browser"

        let icon = UIImageView(image: UIImage(systemName: "safari"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false

        let label = UILabel()
        label.text = "Make XBrowser the default browser"
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.numberOfLines = 2
        label.isUserInteractionEnabled = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.85)
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false

        wrap.addSubview(button)
        button.addSubview(icon)
        button.addSubview(label)
        button.addSubview(chevron)

        button.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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

    static func makeCard(
        cardColor: UIColor = BrowserTheme.elevated,
        onTap: @escaping () -> Void
    ) -> UIView {
        let card = UIView()
        card.backgroundColor = cardColor
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        let banner = makeBanner(onTap: onTap)
        card.addSubview(banner)
        banner.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        }
        return card
    }

    private final class GradientActionButton: UIButton {
        private let gradient = CAGradientLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            gradient.colors = [
                ThemeHex.color("7B5CFF").cgColor,
                ThemeHex.color("FF7A45").cgColor
            ]
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            layer.insertSublayer(gradient, at: 0)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            gradient.frame = bounds
        }
    }
}
