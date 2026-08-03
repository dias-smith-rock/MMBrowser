import Foundation
import WebKit

/// Diagnostics for x.com / Twitter cookie-consent & x-safari kickouts.
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
        guard let host = url?.host?.lowercased() else {
            let scheme = (url?.scheme ?? "").lowercased()
            return scheme.hasPrefix("x-safari-")
        }
        return host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
            || host == "t.co"
            || host.hasSuffix(".t.co")
            || host.contains("twimg.com")
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

    static var userScript: WKUserScript {
        WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static let scriptSource = #"""
(function() {
  if (window.__mmXSiteProbeInstalled) return;
  window.__mmXSiteProbeInstalled = true;
  var host = (location.hostname || '').toLowerCase();
  var relevant = host === 'x.com' || host.indexOf('.x.com') !== -1
    || host === 'twitter.com' || host.indexOf('.twitter.com') !== -1
    || host === 't.co' || host.indexOf('redirect.x.com') !== -1
    || host.indexOf('redirect.twitter.com') !== -1;
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
    hasSafari: !!(window.safari && window.safari.pushNotification)
  });

  function textOf(el) {
    try { return String((el.innerText || el.textContent || '')).replace(/\s+/g, ' ').trim().slice(0, 80); }
    catch (e) { return ''; }
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

  function scanBanner() {
    try {
      var nodes = document.querySelectorAll('button,[role="button"]');
      var hits = [];
      for (var i = 0; i < nodes.length && hits.length < 8; i++) {
        var t = textOf(nodes[i]).toLowerCase();
        if (t.indexOf('accept') !== -1 || t.indexOf('cookie') !== -1 || t.indexOf('refuse') !== -1) {
          hits.push(textOf(nodes[i]));
        }
      }
      if (hits.length) post('banner.scan', { buttons: hits.join(' | '), count: hits.length });
    } catch (e) {
      post('banner.scan.error', { message: String(e) });
    }
  }

  ['pointerdown', 'click', 'touchend'].forEach(function(type) {
    document.addEventListener(type, function(ev) {
      var info = looksLikeConsent(ev.target);
      if (!info) return;
      post('consent.' + type, {
        text: info.text,
        tag: info.tag,
        id: info.id,
        cls: info.cls,
        defaultPrevented: !!ev.defaultPrevented,
        cancelable: !!ev.cancelable
      });
    }, true);
  });

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
        || lower.indexOf('privacy') !== -1 || lower.indexOf('consent') !== -1
        || lower.indexOf('gdpr') !== -1 || lower.indexOf('cookie') !== -1;
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
        || lower.indexOf('privacy') !== -1 || lower.indexOf('consent') !== -1
        || lower.indexOf('gdpr') !== -1 || lower.indexOf('cookie') !== -1;
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

  var scans = 0;
  var timer = setInterval(function() {
    scans += 1;
    scanBanner();
    if (scans >= 8) clearInterval(timer);
  }, 1000);

  window.addEventListener('hashchange', function() {
    post('hashchange', {});
  });
  document.addEventListener('visibilitychange', function() {
    post('visibility', { state: document.visibilityState });
  });
})();
"""#

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        case let s as String:
            let trimmed = s.replacingOccurrences(of: "\n", with: " ")
            return trimmed.count > 180 ? String(trimmed.prefix(177)) + "..." : trimmed
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
