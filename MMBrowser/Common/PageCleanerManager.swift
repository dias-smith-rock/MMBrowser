import Foundation
import WebKit

enum PageCleanerManager {
    static let handlerName = "mmPageCleaner"
    private static let styleID = "mm-page-cleaner"

    /// Inject / refresh hide CSS for rules matching the current URL.
    static func apply(to webView: WKWebView, url: URL?) {
        guard let url = url, url.host != nil else { return }
        let selectors = PageCleanerStore.shared.rules(matching: url).map(\.selector)
        let css: String
        if selectors.isEmpty {
            css = ""
        } else {
            let unique = Array(NSOrderedSet(array: selectors)) as? [String] ?? selectors
            css = unique.map { "\($0){display:none!important;}" }.joined()
        }
        let js = """
        (function() {
          var id = '\(styleID)';
          var css = \(jsonString(css));
          var s = document.getElementById(id);
          if (!css) {
            if (s && s.parentNode) s.parentNode.removeChild(s);
            return;
          }
          if (!s) {
            s = document.createElement('style');
            s.id = id;
            (document.head || document.documentElement).appendChild(s);
          }
          s.textContent = css;
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    static func setPickMode(enabled: Bool, on webView: WKWebView) {
        let js = enabled ? enablePickModeJS : disablePickModeJS
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    static func hideSelector(_ selector: String, on webView: WKWebView) {
        let js = """
        (function() {
          var sel = \(jsonString(selector));
          try {
            document.querySelectorAll(sel).forEach(function(el) {
              el.style.setProperty('display', 'none', 'important');
            });
          } catch (e) {}
          var id = '\(styleID)';
          var s = document.getElementById(id);
          if (!s) {
            s = document.createElement('style');
            s.id = id;
            (document.head || document.documentElement).appendChild(s);
          }
          var rule = sel + '{display:none!important;}';
          if ((s.textContent || '').indexOf(rule) === -1) {
            s.textContent = (s.textContent || '') + rule;
          }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// JSON-encode a string literal for embedding in JS. Top-level String is invalid for NSJSONSerialization.
    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let wrapped = String(data: data, encoding: .utf8),
              wrapped.count >= 2 else {
            return "\"\""
        }
        // ["hello"] -> "hello"
        return String(wrapped.dropFirst().dropLast())
    }

    private static let disablePickModeJS = """
    (function() {
      if (!window.__mmPageCleaner) return;
      window.__mmPageCleaner.disable();
    })();
    """

    private static let enablePickModeJS = """
    (function() {
      if (window.__mmPageCleaner && window.__mmPageCleaner.enabled) return;
      if (window.__mmPageCleaner) {
        window.__mmPageCleaner.enable();
        return;
      }

      var STYLE_ID = 'mm-page-cleaner-pick-style';
      var BTN_ID = 'mm-page-cleaner-delete-btn';
      var HIGHLIGHT = 'mm-page-cleaner-hl';
      var selected = null;

      function ensureStyle() {
        if (document.getElementById(STYLE_ID)) return;
        var s = document.createElement('style');
        s.id = STYLE_ID;
        s.textContent = ''
          + '.' + HIGHLIGHT + '{outline:2px solid #0A84FF!important;outline-offset:2px!important;'
          + 'cursor:pointer!important;}'
          + '#' + BTN_ID + '{position:fixed!important;z-index:2147483647!important;'
          + 'padding:8px 14px!important;border:none!important;border-radius:16px!important;'
          + 'background:rgba(255,59,48,0.92)!important;color:#fff!important;'
          + 'font:600 13px/1 -apple-system,BlinkMacSystemFont,sans-serif!important;'
          + 'box-shadow:0 2px 8px rgba(0,0,0,0.25)!important;cursor:pointer!important;'
          + 'pointer-events:auto!important;-webkit-tap-highlight-color:transparent!important;}';
        (document.head || document.documentElement).appendChild(s);
      }

      function cssEscape(value) {
        if (window.CSS && CSS.escape) return CSS.escape(value);
        return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');
      }

      function isIgnorable(el) {
        if (!el || el.nodeType !== 1) return true;
        var tag = (el.tagName || '').toLowerCase();
        if (tag === 'html' || tag === 'body') return true;
        if (el.id === BTN_ID || el.closest('#' + BTN_ID)) return true;
        return false;
      }

      function buildSelector(el) {
        if (!el || el.nodeType !== 1) return '';
        if (el.id && /^[A-Za-z][\\w-]*$/.test(el.id)) {
          var byId = '#' + cssEscape(el.id);
          try {
            if (document.querySelectorAll(byId).length === 1) return byId;
          } catch (e) {}
        }

        var parts = [];
        var cur = el;
        var depth = 0;
        while (cur && cur.nodeType === 1 && depth < 6) {
          var tag = cur.tagName.toLowerCase();
          if (tag === 'html' || tag === 'body') break;
          var part = tag;
          if (cur.id && /^[A-Za-z][\\w-]*$/.test(cur.id)) {
            parts.unshift('#' + cssEscape(cur.id));
            break;
          }
          var cls = (cur.className && typeof cur.className === 'string')
            ? cur.className.trim().split(/\\s+/).filter(function(c) {
                return c && c.indexOf(HIGHLIGHT) === -1 && /^[A-Za-z][\\w-]*$/.test(c);
              }).slice(0, 2)
            : [];
          if (cls.length) {
            part += '.' + cls.map(cssEscape).join('.');
          }
          var parent = cur.parentElement;
          if (parent) {
            var siblings = Array.prototype.filter.call(parent.children, function(n) {
              return n.tagName === cur.tagName;
            });
            if (siblings.length > 1) {
              var idx = siblings.indexOf(cur) + 1;
              part += ':nth-of-type(' + idx + ')';
            }
          }
          parts.unshift(part);
          try {
            var candidate = parts.join(' > ');
            if (document.querySelectorAll(candidate).length === 1) return candidate;
          } catch (e) {}
          cur = parent;
          depth++;
        }
        return parts.join(' > ');
      }

      function labelFor(el) {
        var tag = (el.tagName || '').toLowerCase();
        if (el.id) return tag + '#' + el.id;
        var text = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
        if (text) {
          if (text.length > 24) text = text.slice(0, 24) + '…';
          return tag + ' · ' + text;
        }
        var cls = (el.className && typeof el.className === 'string')
          ? el.className.trim().split(/\\s+/).filter(Boolean)[0]
          : '';
        return cls ? (tag + '.' + cls) : tag;
      }

      function clearHighlight() {
        document.querySelectorAll('.' + HIGHLIGHT).forEach(function(n) {
          n.classList.remove(HIGHLIGHT);
        });
      }

      function removeButton() {
        var b = document.getElementById(BTN_ID);
        if (b && b.parentNode) b.parentNode.removeChild(b);
      }

      function placeButton(el) {
        removeButton();
        var btn = document.createElement('button');
        btn.id = BTN_ID;
        btn.type = 'button';
        btn.textContent = '删除';
        btn.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          if (!selected) return;
          var payload = {
            type: 'delete',
            selector: buildSelector(selected),
            label: labelFor(selected),
            host: location.hostname || '',
            href: location.href || ''
          };
          if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmPageCleaner) {
            webkit.messageHandlers.mmPageCleaner.postMessage(payload);
          }
          clearHighlight();
          removeButton();
          selected = null;
        }, true);
        (document.documentElement || document.body).appendChild(btn);
        var rect = el.getBoundingClientRect();
        var top = Math.max(8, rect.top - 40);
        var left = Math.min(Math.max(8, rect.left), (window.innerWidth || 320) - 72);
        if (rect.top < 48) top = Math.min(rect.bottom + 8, (window.innerHeight || 480) - 40);
        btn.style.top = Math.round(top) + 'px';
        btn.style.left = Math.round(left) + 'px';
      }

      function onClick(e) {
        if (!api.enabled) return;
        var el = e.target;
        if (el && el.closest) {
          var btn = el.closest('#' + BTN_ID);
          if (btn) return;
        }
        while (el && el.nodeType === 1 && isIgnorable(el)) {
          el = el.parentElement;
        }
        if (isIgnorable(el)) return;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        ensureStyle();
        clearHighlight();
        selected = el;
        el.classList.add(HIGHLIGHT);
        placeButton(el);
      }

      function onScroll() {
        if (selected) placeButton(selected);
      }

      var api = {
        enabled: false,
        enable: function() {
          if (api.enabled) return;
          api.enabled = true;
          ensureStyle();
          document.addEventListener('click', onClick, true);
          window.addEventListener('scroll', onScroll, true);
          window.addEventListener('resize', onScroll, true);
        },
        disable: function() {
          if (!api.enabled) return;
          api.enabled = false;
          document.removeEventListener('click', onClick, true);
          window.removeEventListener('scroll', onScroll, true);
          window.removeEventListener('resize', onScroll, true);
          clearHighlight();
          removeButton();
          selected = null;
          var s = document.getElementById(STYLE_ID);
          if (s && s.parentNode) s.parentNode.removeChild(s);
        }
      };

      window.__mmPageCleaner = api;
      api.enable();
    })();
    """
}
