import Foundation

/// Sites that sign in more reliably with a Computer user agent (QR code, full web UI).
enum DesktopUAHint {
    struct Site {
        let displayName: String
        let hostSuffixes: [String]
        let loginPathTokens: [String]
        let probeJavaScript: String
    }

    static let sites: [Site] = [
        Site(
            displayName: "WhatsApp Web",
            hostSuffixes: ["web.whatsapp.com"],
            loginPathTokens: ["/mobile", "/lite"],
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

    static func looksLikeComputer(_ settings: TabUserAgentSettings) -> Bool {
        switch settings.userAgentMode {
        case .desktop:
            return true
        case .custom:
            return settings.customProfile?.isMobile == false
        case .automatic, .mobile:
            return false
        }
    }
}
