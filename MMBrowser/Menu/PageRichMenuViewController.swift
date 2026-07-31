import UIKit
import SnapKit

struct PageRichMenuContext {
    let url: URL?
    let title: String
    let isIncognito: Bool
    let preferDesktop: Bool
    let adBlockerEnabled: Bool
    let hasLoadablePage: Bool

    var host: String {
        if let host = url?.host, !host.isEmpty { return host }
        if let url { return url.absoluteString }
        return "New Tab"
    }
}

protocol PageRichMenuViewControllerDelegate: AnyObject {
    func pageRichMenuDidSelect(_ action: MenuAction)
}

/// Address-bar page actions sheet (card layout).
final class PageRichMenuViewController: UIViewController {
    weak var delegate: PageRichMenuViewControllerDelegate?

    private let context: PageRichMenuContext
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let faviconView = UIImageView()
    private var faviconTask: URLSessionDataTask?

    init(context: PageRichMenuContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { faviconTask?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = context.isIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
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

        stack.addArrangedSubview(makeHeaderCard())
        stack.addArrangedSubview(makeRowsCard([
            row("Add to Bookmarks", symbol: "bookmark", action: .addBookmark, enabled: context.hasLoadablePage && !context.isIncognito),
            row("Add to Reading List", symbol: "eyeglasses", action: .addReadingList, enabled: context.hasLoadablePage && !context.isIncognito),
            row("Add to Home", symbol: "plus.app", action: .addToHomepage, enabled: context.hasLoadablePage && !context.isIncognito)
        ]))
        stack.addArrangedSubview(makeRowsCard([
            row("Screenshot", symbol: "camera", action: .screenshot, enabled: context.hasLoadablePage),
            row("Long screenshot", symbol: "rectangle.bottomthird.inset.filled", action: .longScreenshot, enabled: context.hasLoadablePage),
            row("Save as PDF", symbol: "doc.richtext", action: .sharePDF, enabled: context.hasLoadablePage),
            row("Print", symbol: "printer", action: .printPage, enabled: context.hasLoadablePage)
        ]))
        stack.addArrangedSubview(makeRowsCard([
            row("Translate page", symbol: "character.bubble", action: .translate, enabled: context.hasLoadablePage, accent: true),
            row(
                context.preferDesktop ? "Request Mobile Site" : "Go to the desktop version",
                symbol: "desktopcomputer",
                action: .desktopSite,
                enabled: context.hasLoadablePage
            ),
            row("Find on page", symbol: "magnifyingglass", action: .findInPage, enabled: context.hasLoadablePage),
            row("Enable Reader mode", symbol: "doc.plaintext", action: .readerMode, enabled: context.hasLoadablePage),
            row("Change text size", symbol: "textformat.size", action: .changeTextSize, enabled: context.hasLoadablePage)
        ]))
        stack.addArrangedSubview(makeRowsCard([
            row(
                context.adBlockerEnabled ? "Ad blocker · On" : "Ad blocker · Off",
                symbol: "hand.raised",
                action: .adBlocker,
                enabled: true
            ),
            row("Webpage Cleaner", symbol: "wand.and.stars", action: .pageCleaner, enabled: context.hasLoadablePage)
        ]))
    }

    // MARK: - Cards

    private func makeHeaderCard() -> UIView {
        let card = makeCardContainer()

        faviconView.contentMode = .scaleAspectFill
        faviconView.clipsToBounds = true
        faviconView.layer.cornerRadius = 10
        faviconView.backgroundColor = BrowserTheme.secondaryCard
        faviconView.image = letterFavicon(for: context.host)

        let title = UILabel()
        title.text = context.host
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = BrowserTheme.textPrimary
        title.lineBreakMode = .byTruncatingMiddle

        let about = UIButton(type: .system)
        about.setTitle("About the site  >", for: .normal)
        about.setTitleColor(BrowserTheme.textSecondary, for: .normal)
        about.titleLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        about.contentHorizontalAlignment = .leading
        about.addTarget(self, action: #selector(aboutTapped), for: .touchUpInside)
        about.isEnabled = context.url != nil

        let textStack = UIStackView(arrangedSubviews: [title, about])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        let copyButton = makeHeaderIconButton(symbol: "link", action: #selector(copyURLTapped), label: "Copy URL")
        let shareButton = makeHeaderIconButton(symbol: "square.and.arrow.up", action: #selector(shareTapped), label: "Share")
        copyButton.isEnabled = context.url != nil
        shareButton.isEnabled = context.url != nil
        copyButton.alpha = context.url != nil ? 1 : 0.35
        shareButton.alpha = context.url != nil ? 1 : 0.35

        let actions = UIStackView(arrangedSubviews: [copyButton, shareButton])
        actions.axis = .horizontal
        actions.spacing = 8

        card.addSubview(faviconView)
        card.addSubview(textStack)
        card.addSubview(actions)

        faviconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(faviconView.snp.trailing).offset(12)
            make.trailing.lessThanOrEqualTo(actions.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
        }
        actions.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
        }
        card.snp.makeConstraints { make in
            make.height.equalTo(72)
        }

        loadFaviconIfNeeded()
        return card
    }

    private func makeRowsCard(_ rows: [UIView]) -> UIView {
        let card = makeCardContainer()
        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.spacing = 0
        card.addSubview(column)
        column.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        for (index, row) in rows.enumerated() where index < rows.count - 1 {
            let line = UIView()
            line.backgroundColor = BrowserTheme.textSecondary.withAlphaComponent(0.12)
            card.addSubview(line)
            line.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(52)
                make.trailing.equalToSuperview()
                make.height.equalTo(1.0 / UIScreen.main.scale)
                make.top.equalTo(row.snp.bottom)
            }
        }
        return card
    }

    private func makeCardContainer() -> UIView {
        let card = UIView()
        card.backgroundColor = context.isIncognito ? BrowserTheme.privateElevated : BrowserTheme.elevated
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        return card
    }

    private func row(
        _ title: String,
        symbol: String,
        action: MenuAction,
        enabled: Bool,
        accent: Bool = false
    ) -> UIView {
        let button = MenuActionButton(action: action)
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.38
        button.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = accent
            ? (context.isIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue)
            : BrowserTheme.textPrimary
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = BrowserTheme.textPrimary

        button.addSubview(icon)
        button.addSubview(label)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(22)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(14)
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
        }
        button.snp.makeConstraints { make in
            make.height.equalTo(52)
        }
        return button
    }

    private func makeHeaderIconButton(symbol: String, action: Selector, label: String) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = BrowserTheme.textPrimary
        button.backgroundColor = BrowserTheme.secondaryCard
        button.layer.cornerRadius = 18
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        button.snp.makeConstraints { make in
            make.size.equalTo(36)
        }
        return button
    }

    // MARK: - Actions

    @objc private func rowTapped(_ sender: MenuActionButton) {
        guard sender.isEnabled else { return }
        delegate?.pageRichMenuDidSelect(sender.menuAction)
    }

    @objc private func copyURLTapped() {
        delegate?.pageRichMenuDidSelect(.copyURL)
    }

    @objc private func shareTapped() {
        delegate?.pageRichMenuDidSelect(.share)
    }

    @objc private func aboutTapped() {
        delegate?.pageRichMenuDidSelect(.aboutSite)
    }

    // MARK: - Favicon

    private func loadFaviconIfNeeded() {
        guard let host = context.url?.host, !host.isEmpty else { return }
        let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
        guard let faviconURL = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(encoded)") else { return }
        faviconTask = URLSession.shared.dataTask(with: faviconURL) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data), image.size.width > 1 else { return }
            DispatchQueue.main.async {
                self?.faviconView.image = image
            }
        }
        faviconTask?.resume()
    }

    private func letterFavicon(for host: String) -> UIImage {
        let size = CGSize(width: 88, height: 88)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let colors: [UIColor] = [
                ThemeHex.color("E85D75"),
                ThemeHex.color("5B8DEF"),
                ThemeHex.color("3CB371"),
                ThemeHex.color("F0A500")
            ]
            let color = colors[abs(host.hashValue) % colors.count]
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 20).fill()
            let letter = String(host.prefix(1)).uppercased()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            letter.draw(in: CGRect(x: 0, y: 22, width: size.width, height: 44), withAttributes: attrs)
        }
    }
}
