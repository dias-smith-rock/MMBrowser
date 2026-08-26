import Foundation
import WebKit

enum IdentitySpoof {
    static let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func resolvedUserAgent(for settings: TabUserAgentSettings) -> String? {
        switch settings.userAgentMode {
        case .automatic:
            return nil
        case .mobile:
            return mobileUA
        case .desktop:
            return desktopUA
        case .custom:
            if let profile = settings.customProfile {
                return profile.userAgentString
            }
            let trimmed = settings.customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    static func userScript(localeIdentifier: String?) -> WKUserScript? {
        guard let locale = localeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !locale.isEmpty else { return nil }

        let escaped = locale
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let languages = locale.hasPrefix("en") ? "[\(escaped), 'en']" : "[\(escaped), \(escaped.split(separator: "-").first.map { "'\($0)'" } ?? "'en'")]"

        let source = """
        (function() {
          if (window.__mmIdentityInstalled) return;
          window.__mmIdentityInstalled = true;
          var LOCALE = '\(escaped)';
          var LANGS = \(languages);
          try {
            Object.defineProperty(navigator, 'language', { get: function() { return LOCALE; }, configurable: true });
            Object.defineProperty(navigator, 'languages', { get: function() { return LANGS; }, configurable: true });
          } catch (e) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
