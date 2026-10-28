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
        Private browsing identities: ads and trackers blocked by default, and accounts that never mix. XBrowser does not show in-app ads.

        Protections
        Block Ads & Trackers stops known ad and tracker network requests and hides common page banners and many pop-up overlays. HTTPS First prefers secure connections and does not fall back to HTTP. Global Privacy Control sends a Sec-GPC signal so sites can treat the visit as opted out of sale or sharing. Fewer YouTube video ads is separate and best-effort—it may stop working when the site changes. Filter lists update so blocking can recover after site changes. Tap the address-bar shield for a Privacy Report.

        Dangerous sites
        Lookalike and phishing-style hosts are blocked before the page loads. Go Back is the recommended choice; Continue is available if you still want to open the site.

        Spaces
        Each Space keeps its own cookies, website storage, history, bookmarks, Watch Later, Reading List, home shortcuts, and passwords. You can also set location to Deny, Current Location, or a virtual city per Space.

        Private Browsing
        Private tabs do not keep history, cookies, or site data after you close them. Downloads are off. Private Browsing does not hide your network IP.

        App Lock & Space Lock
        App Lock protects the whole app with PIN, pattern, and optional biometrics when you open or return to XBrowser. Spaces stay isolated from each other. Space Lock (Premium) adds a PIN or pattern on a single Space so that identity stays closed until unlocked.

        Downloads (Shared)
        Downloaded files are shared across Spaces for convenience. Site logins and website storage are not shared with downloads from another Space.

        Location
        By default, XBrowser denies GPS-like location to websites. Choose Current Location to allow sites to use device GPS (iOS will ask for permission), or spoof a virtual city (and matching timezone when possible) for sites that use the browser Geolocation API. This only affects sites that ask the browser for coordinates. It does not change your network IP.

        Clear Browsing Data
        Removes history and/or website cookies, storage, and caches from this device.

        Clear Option
        Cache, cookies, history, and local storage clear when you leave the app. Close All Tabs on Exit is also on, so you return to one fresh New Tab. Turn any of these off in Clear Option to keep that data.

        Background Audio & Picture in Picture
        When enabled, supported web video and audio can keep playing after you leave the app or lock the screen. Results depend on the site and iOS media rules.

        Limits
        Space separation does not change your network IP or make you anonymous. No browser can fully prevent fingerprinting on the open web. XBrowser focuses on practical isolation, local locks, and best-effort blocking—not a VPN and not absolute anonymity.
        """
        view.addSubview(text)
        text.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
    }
}
