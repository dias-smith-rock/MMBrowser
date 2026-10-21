import UIKit
import SnapKit

/// Explains which data is isolated per space vs shared across the app.
final class IsolatedVsSharedViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Isolated vs Shared"
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 32, right: 20)

        stack.addArrangedSubview(makeBlock(
            title: "Zero-trust-inspired isolation",
            body: "XBrowser keeps browsing identities separate on this device. It does not change your network IP, and no browser can fully prevent fingerprinting on the open web."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Isolated per space",
            body: "Cookies and website data, browsing history, bookmarks, home-page shortcuts, open tabs, Watch Later (including offline files), Reading List (including offline PDFs), and saved passwords."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Shared across the app",
            body: "Downloaded files, autofill form profile, bank cards, search engine, themes, content filters, App Lock, and most Settings. Downloads are marked Shared where they appear — site logins are not shared with them."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Location spoof",
            body: "Per-space location Deny / Current Location / Spoof only affects browser geolocation APIs. It does not change your network IP address."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Clear Option",
            body: "Auto-clear when you leave the app can remove site data for every space’s data store. Delete a single space anytime under Manage Spaces to wipe only that identity’s libraries and site data."
        ))

        view.addSubview(scroll)
        scroll.addSubview(stack)
        scroll.snp.makeConstraints { $0.edges.equalToSuperview() }
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scroll.contentLayoutGuide)
            make.width.equalTo(scroll.frameLayoutGuide)
        }
    }

    private func makeBlock(title: String, body: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }
}
