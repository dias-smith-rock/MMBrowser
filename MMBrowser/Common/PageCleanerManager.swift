import Foundation
import WebKit

enum PageCleanerManager {
    static let handlerName = "mmPageCleaner"
    private static let styleID = "mm-page-cleaner"

    private static let hideCSSSuffix =
        "{display:none!important;visibility:hidden!important;"
        + "pointer-events:none!important;}"

    /// Inject / refresh hide CSS for rules matching the current URL.
    static func apply(to webView: WKWebView, url: URL?) {
        guard let url = url, url.host != nil else { return }
        let selectors = PageCleanerStore.shared.rules(matching: url).map(\.selector)
        let css: String
        if selectors.isEmpty {
            css = ""
        } else {
            let unique = Array(NSOrderedSet(array: selectors)) as? [String] ?? selectors
            css = unique.map { "\($0)\(hideCSSSuffix)" }.joined()
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
            (document.documentElement || document.head).appendChild(s);
          }
          s.textContent = css;
          // Re-hide matching nodes that sites force visible again.
          try {
            css.split('}').forEach(function(chunk) {
              var idx = chunk.indexOf('{');
              if (idx <= 0) return;
              var sel = chunk.slice(0, idx).trim();
              if (!sel) return;
              document.querySelectorAll(sel).forEach(function(el) {
                el.style.setProperty('display', 'none', 'important');
                el.setAttribute('hidden', '');
                el.setAttribute('data-mm-cleaned', '1');
              });
            });
          } catch (e) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Hosts that flash cleaned UI before `didFinish` — apply once at `didCommit` too.
    static func shouldApplyEarly(on url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        let keys = [
            "youtube.com", "youtu.be", "youtube-nocookie.com",
            "facebook.com", "fb.com", "instagram.com",
            "x.com", "twitter.com",
            "tiktok.com", "reddit.com", "redd.it"
        ]
        return keys.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func setPickMode(enabled: Bool, on webView: WKWebView) {
        let js = enabled ? enablePickModeJS : disablePickModeJS
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    static func hideSelector(_ selector: String, on webView: WKWebView) {
        let js = """
        (function() {
          var sel = \(jsonString(selector));
          var id = '\(styleID)';
          var rule = sel + \(jsonString(hideCSSSuffix));
          function inject() {
            var s = document.getElementById(id);
            if (!s) {
              s = document.createElement('style');
              s.id = id;
              (document.documentElement || document.head).appendChild(s);
            }
            if ((s.textContent || '').indexOf(sel + '{') === -1) {
              s.textContent = (s.textContent || '') + rule;
            }
          }
          function hideMatches() {
            try {
              document.querySelectorAll(sel).forEach(function(el) {
                el.style.setProperty('display', 'none', 'important');
                el.style.setProperty('visibility', 'hidden', 'important');
                el.setAttribute('hidden', '');
                el.setAttribute('data-mm-cleaned', '1');
              });
            } catch (e) {}
          }
          inject();
          hideMatches();
          // Sites like YouTube rebuild banners shortly after.
          setTimeout(hideMatches, 50);
          setTimeout(hideMatches, 300);
          setTimeout(hideMatches, 1000);
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
      if (window.__mmPageCleaner) {
        try { window.__mmPageCleaner.disable(); } catch (e) {}
        window.__mmPageCleaner = null;
      }

      var STYLE_ID = 'mm-page-cleaner-pick-style';
      var HIDE_STYLE_ID = 'mm-page-cleaner';
      var BTN_ID = 'mm-page-cleaner-delete-btn';
      var HIGHLIGHT = 'mm-page-cleaner-hl';
      var HIDE_CSS = '{display:none!important;visibility:hidden!important;'
        + 'pointer-events:none!important;}';
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
        (document.documentElement || document.head).appendChild(s);
      }

      function cssEscape(value) {
        if (window.CSS && CSS.escape) return CSS.escape(value);
        return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\\\$&');
      }

      function quoteAttr(value) {
        return '"' + String(value).replace(/\\\\/g, '\\\\\\\\').replace(/"/g, '\\\\"') + '"';
      }

      function classNames(el) {
        try {
          return Array.prototype.slice.call(el.classList || []).filter(function(c) {
            return c && c.indexOf(HIGHLIGHT) === -1;
          });
        } catch (e) { return []; }
      }

      function isIgnorable(el) {
        if (!el || el.nodeType !== 1) return true;
        var tag = (el.tagName || '').toLowerCase();
        if (tag === 'html' || tag === 'body') return true;
        if (el.id === BTN_ID || (el.closest && el.closest('#' + BTN_ID))) return true;
        return false;
      }

      function isClickable(el) {
        if (!el || el.nodeType !== 1) return false;
        var tag = (el.tagName || '').toLowerCase();
        if (tag === 'a' || tag === 'button') return true;
        var role = (el.getAttribute('role') || '').toLowerCase();
        if (role === 'button' || role === 'link') return true;
        if (el.getAttribute('onclick') != null) return true;
        if (el.tabIndex >= 0) return true;
        return false;
      }

      /// Prefer the real control (Open App button) over inner text/svg nodes.
      function resolveTarget(el) {
        var cur = el;
        var best = el;
        for (var i = 0; i < 8 && cur && cur.nodeType === 1; i++) {
          var tag = (cur.tagName || '').toLowerCase();
          if (tag === 'html' || tag === 'body') break;
          if (isClickable(cur)) return cur;
          var cls = classNames(cur).join(' ').toLowerCase();
          if (/open.?app|open-in-app|promo|banner|topbar|masthead/.test(cls)) best = cur;
          if ((cur.getAttribute('aria-label') || '').toLowerCase().indexOf('open') !== -1) return cur;
          cur = cur.parentElement;
        }
        return best || el;
      }

      function uniqueMatch(sel) {
        try {
          return document.querySelectorAll(sel).length === 1;
        } catch (e) { return false; }
      }

      function buildSelector(el) {
        if (!el || el.nodeType !== 1) return '';
        var tag = (el.tagName || '').toLowerCase();

        var aria = el.getAttribute('aria-label');
        if (aria) {
          var ariaSel = tag + '[aria-label=' + quoteAttr(aria) + ']';
          if (uniqueMatch(ariaSel)) return ariaSel;
        }

        if (el.id && /^[A-Za-z][\\w-]*$/.test(el.id)) {
          var byId = '#' + cssEscape(el.id);
          if (uniqueMatch(byId)) return byId;
        }

        var href = el.getAttribute('href');
        if (href && href.length < 180) {
          var hrefSel = tag + '[href=' + quoteAttr(href) + ']';
          if (uniqueMatch(hrefSel)) return hrefSel;
          // Partial match for app deep links that change query params.
          var shortHref = href.split('?')[0];
          if (shortHref && shortHref.length > 3) {
            var hrefPrefix = tag + '[href^=' + quoteAttr(shortHref) + ']';
            if (uniqueMatch(hrefPrefix)) return hrefPrefix;
          }
        }

        var text = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
        if (text && text.length <= 40 && (tag === 'button' || tag === 'a' || isClickable(el))) {
          // Attribute fallbacks first; text matching via CSS is limited, so keep structural path.
        }

        var parts = [];
        var cur = el;
        var depth = 0;
        while (cur && cur.nodeType === 1 && depth < 8) {
          var t = cur.tagName.toLowerCase();
          if (t === 'html' || t === 'body') break;
          var part = t;
          if (cur.id && /^[A-Za-z][\\w-]*$/.test(cur.id)) {
            parts.unshift('#' + cssEscape(cur.id));
            break;
          }
          var cls = classNames(cur).filter(function(c) {
            return /^[A-Za-z_][\\w-]*$/.test(c);
          }).slice(0, 3);
          if (cls.length) {
            part += '.' + cls.map(cssEscape).join('.');
          }
          var parent = cur.parentElement;
          if (parent) {
            var siblings = Array.prototype.filter.call(parent.children, function(n) {
              return n.tagName === cur.tagName;
            });
            if (siblings.length > 1) {
              part += ':nth-of-type(' + (siblings.indexOf(cur) + 1) + ')';
            }
          }
          parts.unshift(part);
          var candidate = parts.join(' > ');
          if (uniqueMatch(candidate)) return candidate;
          cur = parent;
          depth++;
        }
        return parts.join(' > ');
      }

      function labelFor(el) {
        var tag = (el.tagName || '').toLowerCase();
        var aria = el.getAttribute('aria-label');
        if (aria) return aria;
        if (el.id) return tag + '#' + el.id;
        var text = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
        if (text) {
          if (text.length > 24) text = text.slice(0, 24) + '…';
          return tag + ' · ' + text;
        }
        var cls = classNames(el)[0];
        return cls ? (tag + '.' + cls) : tag;
      }

      function injectHideRule(sel) {
        if (!sel) return;
        var s = document.getElementById(HIDE_STYLE_ID);
        if (!s) {
          s = document.createElement('style');
          s.id = HIDE_STYLE_ID;
          (document.documentElement || document.head).appendChild(s);
        }
        var rule = sel + HIDE_CSS;
        if ((s.textContent || '').indexOf(sel + '{') === -1) {
          s.textContent = (s.textContent || '') + rule;
        }
      }

      function hideElement(el) {
        if (!el) return;
        el.style.setProperty('display', 'none', 'important');
        el.style.setProperty('visibility', 'hidden', 'important');
        el.style.setProperty('pointer-events', 'none', 'important');
        el.setAttribute('hidden', '');
        el.setAttribute('data-mm-cleaned', '1');
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
        btn.textContent = 'Delete';
        btn.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          if (!selected) return;
          var target = selected;
          var selector = buildSelector(target);
          var rect = target.getBoundingClientRect();
          var vw = Math.max(window.innerWidth || 1, 1);
          var vh = Math.max(window.innerHeight || 1, 1);
          // Clear pick chrome first so the snapshot is clean; hide after native captures.
          clearHighlight();
          removeButton();
          selected = null;
          var payload = {
            type: 'delete',
            selector: selector,
            label: labelFor(target),
            host: location.hostname || '',
            href: location.href || '',
            rect: {
              x: rect.left / vw,
              y: rect.top / vh,
              w: rect.width / vw,
              h: rect.height / vh
            }
          };
          if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmPageCleaner) {
            webkit.messageHandlers.mmPageCleaner.postMessage(payload);
          }
          // Safety net if native never hides (handler missing / crash).
          setTimeout(function() {
            if (!selector) return;
            try {
              if (document.querySelector(selector) && document.querySelector(selector).getAttribute('data-mm-cleaned') === '1') {
                return;
              }
            } catch (err) {}
            injectHideRule(selector);
            hideElement(target);
            var kill = function() {
              try {
                document.querySelectorAll(selector).forEach(hideElement);
              } catch (err2) {}
            };
            setTimeout(kill, 50);
            setTimeout(kill, 300);
            setTimeout(kill, 1000);
          }, 2000);
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
        if (el && el.nodeType === 3) el = el.parentElement;
        if (el && el.closest && el.closest('#' + BTN_ID)) return;
        while (el && el.nodeType === 1 && isIgnorable(el)) {
          el = el.parentElement;
        }
        if (isIgnorable(el)) return;
        el = resolveTarget(el);
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
