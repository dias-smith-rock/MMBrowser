import Foundation
import WebKit
import UIKit

enum YouTubeDarkMode {
    static func isYouTubeHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    static func isYouTube(_ url: URL?) -> Bool {
        isYouTubeHost(url?.host)
    }

    static func isYouTubeMusic(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "music.youtube.com" || host.hasSuffix(".music.youtube.com")
    }

    /// Document-start script: keep PREF.f6=400 and hint color-scheme.
    static var userScript: WKUserScript {
        let source = """
        (function() {
          var h = location.hostname || '';
          if (h !== 'youtu.be' && h.indexOf('youtube.com') === -1 && h.indexOf('youtube-nocookie.com') === -1) return;
          try { document.documentElement.style.colorScheme = 'dark'; } catch (e) {}
          function readPREF() {
            var m = document.cookie.match(/(?:^|; )PREF=([^;]*)/);
            return m ? decodeURIComponent(m[1]) : '';
          }
          function writePREF(v) {
            document.cookie = 'PREF=' + v + '; path=/; domain=.youtube.com; max-age=31536000';
          }
          var pref = readPREF();
          if (pref.indexOf('f6=400') !== -1) return;
          if (pref) {
            if (/f6=[^&]*/.test(pref)) {
              pref = pref.replace(/f6=[^&]*/, 'f6=400');
            } else {
              pref = pref + '&f6=400';
            }
          } else {
            pref = 'f6=400';
          }
          writePREF(pref);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    static func applyAppearance(to webView: WKWebView, url: URL?) {
        if isYouTube(url) {
            webView.overrideUserInterfaceStyle = .dark
            if #available(iOS 15.0, *) {
                webView.underPageBackgroundColor = UIColor(white: 0.07, alpha: 1)
            }
        } else {
            webView.overrideUserInterfaceStyle = .unspecified
            if #available(iOS 15.0, *) {
                webView.underPageBackgroundColor = .systemBackground
            }
        }
    }

    /// Ensure dark-theme PREF cookie exists before the first YouTube request.
    static func ensureDarkCookie(in dataStore: WKWebsiteDataStore, completion: @escaping () -> Void) {
        let store = dataStore.httpCookieStore
        store.getAllCookies { cookies in
            let existing = cookies.first { $0.name == "PREF" && ($0.domain == ".youtube.com" || $0.domain == "youtube.com") }
            var prefValue = existing?.value ?? ""
            if prefValue.contains("f6=400") {
                DispatchQueue.main.async(execute: completion)
                return
            }
            if prefValue.isEmpty {
                prefValue = "f6=400"
            } else if prefValue.range(of: "f6=[^&]*", options: .regularExpression) != nil {
                prefValue = prefValue.replacingOccurrences(of: "f6=[^&]*", with: "f6=400", options: .regularExpression)
            } else {
                prefValue += "&f6=400"
            }

            var props: [HTTPCookiePropertyKey: Any] = [
                .name: "PREF",
                .value: prefValue,
                .domain: ".youtube.com",
                .path: "/",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 365)
            ]
            if let cookie = HTTPCookie(properties: props) {
                store.setCookie(cookie) {
                    DispatchQueue.main.async(execute: completion)
                }
            } else {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }
}
