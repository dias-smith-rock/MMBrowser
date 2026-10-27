import Foundation
import WebKit

/// Sends the Global Privacy Control signal (`Sec-GPC: 1` and `navigator.globalPrivacyControl`).
enum GlobalPrivacyControl {
    static var userScript: WKUserScript {
        WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static func applying(to request: URLRequest) -> URLRequest {
        guard AppSettings.globalPrivacyControlEnabled else { return request }
        if request.value(forHTTPHeaderField: "Sec-GPC") != nil { return request }
        var copy = request
        copy.setValue("1", forHTTPHeaderField: "Sec-GPC")
        return copy
    }

    /// Main-frame http(s) loads that still lack the header should be reissued once.
    static func shouldRewriteMainFrame(_ action: WKNavigationAction) -> Bool {
        guard AppSettings.globalPrivacyControlEnabled else { return false }
        let request = action.request
        guard request.value(forHTTPHeaderField: "Sec-GPC") == nil else { return false }
        let method = request.httpMethod?.uppercased() ?? "GET"
        guard method == "GET" else { return false }
        guard let url = request.url else { return false }
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else { return false }
        return action.targetFrame?.isMainFrame ?? true
    }

    private static let scriptSource = """
    (function() {
      if (window.__mmGPCInstalled) return;
      window.__mmGPCInstalled = true;
      try {
        Object.defineProperty(Navigator.prototype, 'globalPrivacyControl', {
          configurable: true,
          get: function() { return true; }
        });
      } catch (e) {}
      try {
        var origFetch = window.fetch;
        if (typeof origFetch === 'function') {
          window.fetch = function(input, init) {
            var next = init ? Object.assign({}, init) : {};
            try {
              var headers = new Headers(next.headers || (input && input.headers));
              if (!headers.has('Sec-GPC')) headers.set('Sec-GPC', '1');
              next.headers = headers;
            } catch (e) {}
            return origFetch.call(this, input, next);
          };
        }
      } catch (e) {}
      try {
        var origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function() {
          try { this.setRequestHeader('Sec-GPC', '1'); } catch (e) {}
          return origSend.apply(this, arguments);
        };
      } catch (e) {}
    })();
    """
}
