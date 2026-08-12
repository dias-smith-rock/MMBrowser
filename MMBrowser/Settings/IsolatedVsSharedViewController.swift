import UIKit
import SnapKit

/// Explains which data is isolated per account vs shared across the app.
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
            title: "Isolated per account",
            body: "Cookies and website data, browsing history, bookmarks, home-page shortcuts, open tabs, and saved passwords (when saved while using that account)."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Shared across the app",
            body: "Downloads, Reading List, autofill form profile, bank cards, search engine, themes, ad filters, App Lock, and most Settings. These are marked Shared where they appear."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Location spoof",
            body: "Per-account location Deny / Ask / Spoof only affects browser geolocation APIs. It does not change your network IP address."
        ))
        stack.addArrangedSubview(makeBlock(
            title: "Clear Option",
            body: "Auto-clear when you leave the app can remove site data for every account’s data store. Delete a single account anytime under Manage Accounts to wipe only that identity."
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
