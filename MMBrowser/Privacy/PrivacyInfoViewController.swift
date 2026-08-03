import UIKit
import SnapKit

final class PrivacyInfoViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Privacy"
        BrowserTheme.applyScreenChrome(to: self)
        let text = UITextView()
        text.backgroundColor = .clear
        text.textColor = BrowserTheme.textPrimary
        text.font = .systemFont(ofSize: 16)
        text.isEditable = false
        text.text = """
        MMBrowser is a private browser for separate accounts and cleaner browsing on the open web.

        Accounts
        Each account keeps its own cookies and site data, so you can stay signed in to different logins side by side. You can also set location to Deny, Ask, or a virtual city per account.

        Block Ads & Trackers
        Blocks known ad and tracker network requests and hides common page banners using WebKit content rules. You can turn this off anytime in Settings.

        Location
        By default, MMBrowser denies GPS-like location to websites. You can Spoof a virtual city (and matching timezone when possible) for sites that use the browser Geolocation API. Changing virtual location only affects sites that ask the browser for coordinates. Sites that detect your network IP cannot be changed without a VPN or proxy.

        Clear Browsing Data
        Removes history and/or website cookies, storage, and caches from this device.

        Clear Option
        Auto-clears cache, cookies, history, and/or local storage when you leave the app. History is still recorded during the session; turn History auto-clear off to keep it across launches.

        HTTPS First
        Prefers secure connections when you type a domain without a scheme.

        Limits
        Account separation does not change your network IP address or make you anonymous on the internet. No browser can fully prevent fingerprinting on the open web. MMBrowser focuses on practical tracking reduction, cleaner pages, and local data control—not impossible absolute anonymity.
        """
        view.addSubview(text)
        text.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
    }
}
