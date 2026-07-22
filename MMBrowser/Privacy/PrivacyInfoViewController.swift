import UIKit
import SnapKit

final class PrivacyInfoViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy"
        view.backgroundColor = BrowserTheme.background
        let text = UITextView()
        text.backgroundColor = .clear
        text.textColor = BrowserTheme.textSecondary
        text.font = .systemFont(ofSize: 16)
        text.isEditable = false
        text.text = """
        MMBrowser helps reduce cross-site tracking and local browsing traces.

        Tracker Protection
        Blocks known ad/tracker network requests (including AdSense and common analytics) using WebKit content rules. You can turn this off anytime in Settings.

        Clear Browsing Data
        Removes history and/or website cookies, storage, and caches from this device.

        HTTPS First
        Prefers secure connections when you type a domain without a scheme.

        Limits
        No browser can fully prevent fingerprinting on the open web. MMBrowser focuses on practical tracking reduction and local data control—not impossible absolute anonymity.
        """
        view.addSubview(text)
        text.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
    }
}
