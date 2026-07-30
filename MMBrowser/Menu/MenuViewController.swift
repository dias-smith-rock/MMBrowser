import UIKit
import SnapKit

enum MenuAction: Equatable {
    case bookmarks, history, readingList, downloads, settings
    case reload, newTab, newIncognitoTab, addBookmark, addReadingList
    case readerMode, findInPage, share, desktopSite, sharePDF, screenshot, longScreenshot
    case placeholder(String)
}

protocol MenuViewControllerDelegate: AnyObject {
    func menuDidSelect(_ action: MenuAction)
}

final class MenuViewController: UIViewController {
    weak var delegate: MenuViewControllerDelegate?
    private let isIncognito: Bool
    private let scrollView = UIScrollView()
    private let content = UIView()

    init(isIncognito: Bool = false) {
        self.isIncognito = isIncognito
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = isIncognito ? BrowserTheme.privateElevated : BrowserTheme.elevated
        modalPresentationStyle = .pageSheet

        view.addSubview(scrollView)
        scrollView.addSubview(content)
        scrollView.snp.makeConstraints { make in make.edges.equalToSuperview() }
        content.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        var icons: [(String, String, MenuAction)] = [
            ("gear", "Settings", .settings),
            ("star", "Bookmarks", .bookmarks),
            ("book", "Reading list", .readingList),
            ("arrow.down.circle", "Downloads", .downloads),
            ("doc.text", "Reader", .readerMode)
        ]
        // Library icons still open existing libraries; private session cannot *add* to them.
        if isIncognito {
            icons = icons.filter { $0.2 != .downloads }
        }

        let iconScroll = UIScrollView()
        iconScroll.showsHorizontalScrollIndicator = false
        let iconStack = UIStackView()
        iconStack.axis = .horizontal
        iconStack.spacing = 12
        iconScroll.addSubview(iconStack)
        content.addSubview(iconScroll)
        for (symbol, title, action) in icons {
            iconStack.addArrangedSubview(makeIconItem(symbol: symbol, title: title, action: action))
        }
        iconScroll.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(88)
        }
        iconStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
            make.height.equalToSuperview()
        }

        var rows: [(String, String, MenuAction)] = [
            ("Reload", "arrow.clockwise", .reload),
            ("Find in page", "magnifyingglass", .findInPage),
            ("Share", "square.and.arrow.up", .share),
            ("Request Desktop Site", "desktopcomputer", .desktopSite),
            ("New Incognito tab", "eye.slash", .newIncognitoTab),
            ("Add to bookmarks", "star", .addBookmark),
            ("Add to reading list", "book", .addReadingList),
            ("Share as PDF", "doc.richtext", .sharePDF),
            ("Screenshot", "camera", .screenshot),
            ("Long screenshot", "camera.viewfinder", .longScreenshot)
        ]
        if isIncognito {
            rows.removeAll { $0.2 == .addBookmark || $0.2 == .addReadingList }
        }

        var previous: UIView = iconScroll
        for (index, row) in rows.enumerated() {
            let button = makeRow(title: row.0, symbol: row.1, action: row.2)
            content.addSubview(button)
            button.snp.makeConstraints { make in
                make.top.equalTo(previous.snp.bottom).offset(index == 0 ? 16 : 4)
                make.leading.trailing.equalToSuperview().inset(12)
                make.height.equalTo(48)
                if index == rows.count - 1 { make.bottom.equalToSuperview().offset(-24) }
            }
            previous = button
        }
    }

    private func makeIconItem(symbol: String, title: String, action: MenuAction) -> UIView {
        let container = UIView()
        container.snp.makeConstraints { make in make.width.equalTo(76) }
        let box = UIView()
        box.backgroundColor = BrowserTheme.secondaryCard
        box.layer.cornerRadius = 14
        let image = UIImageView(image: UIImage(systemName: symbol))
        image.tintColor = isIncognito ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        image.contentMode = .scaleAspectFit
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 11)
        label.textColor = BrowserTheme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 2
        let button = MenuActionButton(action: action)
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
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

    private func makeRow(title: String, symbol: String, action: MenuAction) -> UIButton {
        let button = MenuActionButton(action: action)
        button.backgroundColor = BrowserTheme.secondaryCard
        button.layer.cornerRadius = 12
        button.setTitle("  \(title)", for: .normal)
        button.setTitleColor(BrowserTheme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = isIncognito ? BrowserTheme.privateAccent : BrowserTheme.textPrimary
        button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
        button.semanticContentAttribute = .forceLeftToRight
        return button
    }

    @objc private func actionTapped(_ sender: MenuActionButton) {
        delegate?.menuDidSelect(sender.menuAction)
    }
}

private final class MenuActionButton: UIButton {
    let menuAction: MenuAction
    init(action: MenuAction) {
        self.menuAction = action
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
}
