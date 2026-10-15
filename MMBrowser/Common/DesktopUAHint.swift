import Foundation

/// Sites that sign in more reliably with a Computer user agent (QR code, full web UI).
enum DesktopUAHint {
    struct Site {
        let displayName: String
        let hostSuffixes: [String]
        let loginPathTokens: [String]
        /// When true, apply Computer UA immediately (no login-page probe / alert).
        let autoApplyComputerUserAgent: Bool
        let probeJavaScript: String
    }

    static let sites: [Site] = [
        Site(
            displayName: "WhatsApp Web",
            // Matches whatsapp.com, www.whatsapp.com, web.whatsapp.com, …
            // autoApplyComputerUserAgent: enforced in WebViewController before the first request
            // (not only as a post-load delegate hint).
            hostSuffixes: ["whatsapp.com"],
            loginPathTokens: ["/mobile", "/lite"],
            autoApplyComputerUserAgent: true,
            probeJavaScript: """
            (function() {
              try {
                var href = (location.href || '').toLowerCase();
                if (href.indexOf('/mobile') !== -1 || href.indexOf('/lite') !== -1) return 'login';
                if (document.querySelector('#pane-side')
                    || document.querySelector('#side')
                    || document.querySelector('[data-testid="chat-list"]')
                    || document.querySelector('[aria-label="Chat list"]')) return 'logged-in';
                if (document.querySelector('canvas')
                    || document.querySelector('[data-testid="qr-code"]')
                    || document.querySelector('[data-testid="qrcode"]')) return 'login';
                var text = ((document.body && document.body.innerText) || '').slice(0, 2500);
                if (/scan this qr|scan the qr|log in to whatsapp|continue with phone number|phone number/i.test(text)) return 'login';
                return 'unknown';
              } catch (e) { return 'unknown'; }
            })()
            """
        ),
        Site(
            displayName: "Telegram Web",
            hostSuffixes: ["web.telegram.org", "webk.telegram.org", "webz.telegram.org"],
            loginPathTokens: [],
            autoApplyComputerUserAgent: false,
            probeJavaScript: """
            (function() {
              try {
                if (document.querySelector('.ChatList')
                    || document.querySelector('#column-left')
                    || document.querySelector('.chat-list')) return 'logged-in';
                if (document.querySelector('.auth-form')
                    || document.querySelector('.qr-container')
                    || document.querySelector('canvas')) return 'login';
                var text = ((document.body && document.body.innerText) || '').slice(0, 2000);
                if (/log in to telegram|log in by phone|scan to log in/i.test(text)) return 'login';
                return 'unknown';
              } catch (e) { return 'unknown'; }
            })()
            """
        ),
        Site(
            displayName: "Discord",
            hostSuffixes: ["discord.com", "discordapp.com"],
            loginPathTokens: ["/login"],
            autoApplyComputerUserAgent: false,
            probeJavaScript: """
            (function() {
              try {
                var href = (location.href || '').toLowerCase();
                if (href.indexOf('/login') !== -1 || href.indexOf('/register') !== -1) return 'login';
                if (document.querySelector('[aria-label="Servers"]')
                    || document.querySelector('[class*="guilds"]')
                    || document.querySelector('[class*="sidebar"]')) return 'logged-in';
                var text = ((document.body && document.body.innerText) || '').slice(0, 2000);
                if (/welcome back|log in|login/i.test(text) && !document.querySelector('[aria-label="Servers"]')) return 'login';
                return 'unknown';
              } catch (e) { return 'unknown'; }
            })()
            """
        )
    ]

    static func site(matching url: URL) -> Site? {
        let host = (url.host ?? "").lowercased()
        guard !host.isEmpty else { return nil }
        return sites.first { site in
            site.hostSuffixes.contains { suffix in
                host == suffix || host.hasSuffix("." + suffix)
            }
        }
    }

    /// Marketing / mobile portals that should open the real web app instead.
    static func canonicalWebAppURL(for url: URL) -> URL? {
        let host = (url.host ?? "").lowercased()
        guard host == "whatsapp.com" || host == "www.whatsapp.com" else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = "web.whatsapp.com"
        // Drop marketing paths; WhatsApp Web only serves the app shell.
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }
}
