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
        XBrowser uses Zero-trust-inspired isolation: separate Spaces on this device, HTTPS-Only by default, and no ad monetization.

        Spaces
        Each space keeps its own cookies, website storage, history, bookmarks, Watch Later, Reading List, home shortcuts, and passwords. You can also set location to Deny, Current Location, or a virtual city per space.

        Downloads (Shared)
        Downloaded files are shared across Spaces for convenience. Site logins and website storage are not shared with downloads from another Space.

        Block Ads & Trackers
        Blocks known ad and tracker network requests and hides common page banners using WebKit content rules. You can turn this off anytime in Settings.

        HTTPS Only
        Prefers secure connections and does not automatically fall back to HTTP when HTTPS fails. You can turn this off in Settings if needed.

        Location
        By default, XBrowser denies GPS-like location to websites. Choose Current Location to allow sites to use device GPS (iOS will ask for permission), or Spoof a virtual city (and matching timezone when possible) for sites that use the browser Geolocation API. Changing virtual location only affects sites that ask the browser for coordinates. Sites that detect your network IP cannot be changed without a VPN or proxy.

        Clear Browsing Data
        Removes history and/or website cookies, storage, and caches from this device.

        Clear Option
        Optionally auto-clears cache, cookies, history, and/or local storage when you leave the app. All of these default off so logins stay signed in; turn items on only if you want them wiped on exit.

        Limits
        Space separation does not change your network IP address or make you anonymous on the internet. No browser can fully prevent fingerprinting on the open web. XBrowser focuses on practical isolation and local data control—not impossible absolute anonymity.
        """
        view.addSubview(text)
        text.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
    }
}
