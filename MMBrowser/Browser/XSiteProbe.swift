import Foundation
import WebKit

/// Diagnostics for x.com / Twitter cookie-consent, kickouts, and Google OAuth.
/// Filter Xcode console with `[XSiteProbe]`.
enum XSiteProbe {
    static let handlerName = "mmXSiteProbe"

    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "debug.xsite.probe")
        #endif
    }

    static func isRelevant(_ url: URL?) -> Bool {
        guard let url else { return false }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme.hasPrefix("x-safari-") { return true }
        guard let host = url.host?.lowercased() else {
            return scheme == "about" || url.absoluteString.lowercased().contains("google")
        }
        return isXHost(host) || isAuthHost(host)
    }

    static func isXHost(_ host: String) -> Bool {
        host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
            || host == "t.co"
            || host.hasSuffix(".t.co")
            || host.contains("twimg.com")
    }

    static func isAuthHost(_ host: String) -> Bool {
        host == "accounts.google.com"
            || host.hasSuffix(".accounts.google.com")
            || host == "google.com"
            || host.hasSuffix(".google.com")
            || host == "appleid.apple.com"
            || host.hasSuffix(".appleid.apple.com")
            || host.contains("googleapis.com")
            || host.contains("gstatic.com")
            || host == "api.twitter.com"
            || host == "api.x.com"
            || host.hasSuffix(".api.x.com")
            || host.contains("oauth")
    }

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        guard isEnabled else { return }
        var parts: [String] = ["[XSiteProbe]", event]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            parts.append("\(key)=\(stringify(value))")
        }
        print(parts.joined(separator: " "))
    }

    static func logJS(_ body: [String: Any]) {
        guard isEnabled else { return }
        let event = (body["event"] as? String) ?? "js"
        var fields = body
        fields.removeValue(forKey: "event")
        log("js.\(event)", fields)
    }

    /// Inject on every page when probing — login popups open on Google, not only x.com.
    static var userScript: WKUserScript {
        WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static let scriptSource = #"""
(function() {
  if (window.__mmXSiteProbeInstalled) return;
  window.__mmXSiteProbeInstalled = true;
  var host = (location.hostname || '').toLowerCase();
  var href = String(location.href || '');
  var relevant = host === 'x.com' || host.indexOf('.x.com') !== -1
    || host === 'twitter.com' || host.indexOf('.twitter.com') !== -1
    || host === 't.co' || host.indexOf('redirect.x.com') !== -1
    || host.indexOf('google.com') !== -1 || host.indexOf('googleapis.com') !== -1
    || host.indexOf('gstatic.com') !== -1 || host.indexOf('appleid.apple.com') !== -1
    || href.indexOf('oauth') !== -1 || href.indexOf('login') !== -1;
  if (!relevant) return;

  function post(event, fields) {
    try {
      var body = fields || {};
      body.event = event;
      body.host = host;
      body.href = String(location.href || '').slice(0, 240);
      window.webkit.messageHandlers.mmXSiteProbe.postMessage(body);
    } catch (e) {}
  }

  post('boot', {
    readyState: document.readyState,
    ua: String(navigator.userAgent || '').slice(0, 180),
    hasSafari: !!(window.safari && window.safari.pushNotification),
    hasOpener: !!window.opener
  });

  function textOf(el) {
    try { return String((el.innerText || el.textContent || '')).replace(/\s+/g, ' ').trim().slice(0, 80); }
    catch (e) { return ''; }
  }

  function looksLikeAuth(el) {
    if (!el || !el.closest) return null;
    var btn = el.closest('button,[role="button"],a,div[tabindex]');
    if (!btn) return null;
    var t = textOf(btn).toLowerCase();
    var aria = String(btn.getAttribute('aria-label') || '').toLowerCase();
    var blob = t + ' ' + aria;
    if (!blob.trim()) return null;
    if (blob.indexOf('google') !== -1 || blob.indexOf('sign in') !== -1
        || blob.indexOf('log in') !== -1 || blob.indexOf('continue') !== -1
        || blob.indexOf('apple') !== -1 || blob.indexOf('登录') !== -1
        || blob.indexOf('oauth') !== -1) {
      return { tag: btn.tagName, text: textOf(btn) || aria, id: btn.id || '', cls: String(btn.className || '').slice(0, 80) };
    }
    return null;
  }

  function looksLikeConsent(el) {
    if (!el || !el.closest) return null;
    var btn = el.closest('button,[role="button"],a,div[tabindex]');
    if (!btn) return null;
    var t = textOf(btn).toLowerCase();
    if (!t) return null;
    if (t.indexOf('accept') !== -1 || t.indexOf('refuse') !== -1
        || t.indexOf('reject') !== -1 || t.indexOf('cookie') !== -1
        || t.indexOf('同意') !== -1 || t.indexOf('拒绝') !== -1) {
      return { tag: btn.tagName, text: textOf(btn), id: btn.id || '', cls: String(btn.className || '').slice(0, 80) };
    }
    return null;
  }

  ['pointerdown', 'click', 'touchend'].forEach(function(type) {
    document.addEventListener(type, function(ev) {
      var auth = looksLikeAuth(ev.target);
      if (auth) {
        post('auth.' + type, {
          text: auth.text, tag: auth.tag, id: auth.id, cls: auth.cls,
          defaultPrevented: !!ev.defaultPrevented
        });
      }
      var info = looksLikeConsent(ev.target);
      if (!info) return;
      post('consent.' + type, {
        text: info.text, tag: info.tag, id: info.id, cls: info.cls,
        defaultPrevented: !!ev.defaultPrevented, cancelable: !!ev.cancelable
      });
    }, true);
  });

  // window.open is how Google OAuth usually starts from x.com.
  try {
    var origOpen = window.open;
    window.open = function(url, name, features) {
      var u = '';
      try { u = String(url == null ? '' : url); } catch (e) { u = '<err>'; }
      post('window.open', {
        url: u.slice(0, 220),
        name: String(name || ''),
        features: String(features || '').slice(0, 120),
        openerPresent: !!window.opener
      });
      var win = null;
      var threw = '';
      try {
        win = origOpen.apply(this, arguments);
      } catch (e) {
        threw = String(e && e.message || e);
      }
      post('window.open.result', {
        url: u.slice(0, 220),
        ok: !!win,
        threw: threw,
        closed: !!(win && win.closed)
      });
      return win;
    };
  } catch (e) {
    post('window.open.wrapFail', { message: String(e) });
  }

  // location.assign / replace often used for full-page OAuth redirects.
  try {
    var desc = Object.getOwnPropertyDescriptor(Location.prototype, 'href')
      || Object.getOwnPropertyDescriptor(HTMLAnchorElement.prototype, 'href');
    var origAssign = location.assign.bind(location);
    var origReplace = location.replace.bind(location);
    location.assign = function(u) {
      post('location.assign', { url: String(u || '').slice(0, 220) });
      return origAssign(u);
    };
    location.replace = function(u) {
      post('location.replace', { url: String(u || '').slice(0, 220) });
      return origReplace(u);
    };
  } catch (e) {}

  function wrapFetch() {
    if (!window.fetch) return;
    var orig = window.fetch;
    window.fetch = function() {
      var input = arguments[0];
      var url = '';
      try {
        if (typeof input === 'string') url = input;
        else if (input && input.url) url = input.url;
      } catch (e) {}
      var lower = String(url).toLowerCase();
      var watch = lower.indexOf('twitter') !== -1 || lower.indexOf('x.com') !== -1
        || lower.indexOf('t.co') !== -1 || lower.indexOf('twimg') !== -1
        || lower.indexOf('google') !== -1 || lower.indexOf('oauth') !== -1
        || lower.indexOf('privacy') !== -1 || lower.indexOf('consent') !== -1
        || lower.indexOf('gdpr') !== -1 || lower.indexOf('cookie') !== -1
        || lower.indexOf('login') !== -1 || lower.indexOf('auth') !== -1;
      var p = orig.apply(this, arguments);
      if (watch) {
        post('fetch.start', { url: String(url).slice(0, 200) });
        p.then(function(res) {
          post('fetch.done', { url: String(url).slice(0, 200), status: res && res.status, ok: !!(res && res.ok) });
          return res;
        }).catch(function(err) {
          post('fetch.fail', { url: String(url).slice(0, 200), message: String(err && err.message || err) });
          throw err;
        });
      }
      return p;
    };
  }

  function wrapXHR() {
    if (!window.XMLHttpRequest) return;
    var open = XMLHttpRequest.prototype.open;
    var send = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
      this.__mmXUrl = String(url || '');
      this.__mmXMethod = String(method || '');
      return open.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function() {
      var url = this.__mmXUrl || '';
      var lower = url.toLowerCase();
      var watch = lower.indexOf('twitter') !== -1 || lower.indexOf('x.com') !== -1
        || lower.indexOf('google') !== -1 || lower.indexOf('oauth') !== -1
        || lower.indexOf('privacy') !== -1 || lower.indexOf('consent') !== -1
        || lower.indexOf('gdpr') !== -1 || lower.indexOf('cookie') !== -1
        || lower.indexOf('login') !== -1 || lower.indexOf('auth') !== -1;
      if (watch) {
        var xhr = this;
        post('xhr.start', { method: this.__mmXMethod, url: url.slice(0, 200) });
        this.addEventListener('loadend', function() {
          post('xhr.done', { method: xhr.__mmXMethod, url: url.slice(0, 200), status: xhr.status });
        });
        this.addEventListener('error', function() {
          post('xhr.fail', { method: xhr.__mmXMethod, url: url.slice(0, 200) });
        });
      }
      return send.apply(this, arguments);
    };
  }

  wrapFetch();
  wrapXHR();

  window.addEventListener('hashchange', function() {
    post('hashchange', {});
  });
  window.addEventListener('pagehide', function() {
    post('pagehide', {});
  });
  document.addEventListener('visibilitychange', function() {
    post('visibility', { state: document.visibilityState });
  });
  window.addEventListener('message', function(ev) {
    var origin = '';
    try { origin = String(ev.origin || ''); } catch (e) {}
    if (origin.indexOf('google') === -1 && origin.indexOf('x.com') === -1
        && origin.indexOf('twitter') === -1 && origin.indexOf('apple') === -1) return;
    post('postMessage', {
      origin: origin.slice(0, 80),
      dataType: typeof ev.data,
      data: (typeof ev.data === 'string' ? ev.data : JSON.stringify(ev.data) || '').slice(0, 120)
    });
  }, true);
})();
"""#

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        case let s as String:
            let trimmed = s.replacingOccurrences(of: "\n", with: " ")
            return trimmed.count > 220 ? String(trimmed.prefix(217)) + "..." : trimmed
        case let arr as [Any]:
            return "[\(arr.prefix(8).map(stringify).joined(separator: ","))]"
        case let dict as [String: Any]:
            let inner = dict.keys.sorted().compactMap { k -> String? in
                guard let v = dict[k] else { return nil }
                return "\(k):\(stringify(v))"
            }.joined(separator: ",")
            return "{\(inner)}"
        default:
            return String(describing: value)
        }
    }
}
