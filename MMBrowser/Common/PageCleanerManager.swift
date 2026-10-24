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

    /// Replace visible text on the first match for `selector` (session-only).
    static func setText(_ text: String, selector: String, on webView: WKWebView) {
        let js = """
        (function() {
          var sel = \(jsonString(selector));
          var next = \(jsonString(text));
          if (!window.__mmPageCleanerTextEdits) window.__mmPageCleanerTextEdits = {};
          function readText(el) {
            if (!el) return '';
            var tag = (el.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea') return String(el.value || '');
            return String(el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
          }
          function apply(el) {
            if (!el || el.nodeType !== 1) return;
            if (window.__mmPageCleanerTextEdits[sel] === undefined) {
              window.__mmPageCleanerTextEdits[sel] = readText(el);
            }
            var tag = (el.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea') {
              el.value = next;
              try {
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
              } catch (e) {}
              return;
            }
            if (el.isContentEditable) {
              el.textContent = next;
              return;
            }
            // Rewrite direct text nodes only — keep sibling elements (icons / other labels).
            var textNodes = [];
            for (var i = 0; i < el.childNodes.length; i++) {
              var n = el.childNodes[i];
              if (n.nodeType === 3 && String(n.textContent || '').replace(/\\s+/g, '').length) {
                textNodes.push(n);
              }
            }
            if (textNodes.length > 0) {
              textNodes[0].textContent = next;
              for (var j = 1; j < textNodes.length; j++) textNodes[j].textContent = '';
              return;
            }
            if (!el.children || el.children.length === 0) {
              el.textContent = next;
              return;
            }
            // Prefer a single leaf text host so we don't wipe nested controls.
            var leaf = null;
            try {
              var nodes = el.querySelectorAll('*');
              for (var k = 0; k < nodes.length; k++) {
                var c = nodes[k];
                if (c.children && c.children.length === 0) {
                  var t = (c.innerText || c.textContent || '').replace(/\\s+/g, ' ').trim();
                  if (t) { leaf = c; break; }
                }
              }
            } catch (e2) {}
            if (leaf) {
              leaf.textContent = next;
            } else {
              el.innerText = next;
            }
          }
          try {
            var match = document.querySelector(sel);
            if (match) apply(match);
          } catch (e3) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Undo hide CSS + session text edits on the current document (before a reload).
    static func clearSessionEdits(on webView: WKWebView) {
        let js = """
        (function() {
          var edits = window.__mmPageCleanerTextEdits || {};
          function applyText(el, next) {
            if (!el) return;
            var tag = (el.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea') {
              el.value = next;
              return;
            }
            if (!el.children || el.children.length === 0) {
              el.textContent = next;
              return;
            }
            el.innerText = next;
          }
          Object.keys(edits).forEach(function(sel) {
            try {
              var el = document.querySelector(sel);
              if (el) applyText(el, edits[sel]);
            } catch (e) {}
          });
          window.__mmPageCleanerTextEdits = {};
          var s = document.getElementById('\(styleID)');
          if (s && s.parentNode) s.parentNode.removeChild(s);
          try {
            document.querySelectorAll('[data-mm-cleaned]').forEach(function(el) {
              el.removeAttribute('data-mm-cleaned');
              el.removeAttribute('hidden');
              el.style.removeProperty('display');
              el.style.removeProperty('visibility');
              el.style.removeProperty('pointer-events');
            });
          } catch (e2) {}
        })();
        """
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
      var BAR_ID = 'mm-page-cleaner-action-bar';
      var BTN_ID = 'mm-page-cleaner-delete-btn';
      var EDIT_BTN_ID = 'mm-page-cleaner-edit-btn';
      var RESET_BTN_ID = 'mm-page-cleaner-reset-btn';
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
          + '#' + BAR_ID + '{position:fixed!important;z-index:2147483647!important;'
          + 'display:flex!important;flex-direction:row!important;align-items:center!important;'
          + 'gap:6px!important;pointer-events:auto!important;}'
          + '#' + BAR_ID + ' button{padding:8px 14px!important;border:none!important;'
          + 'border-radius:16px!important;color:#fff!important;'
          + 'font:600 13px/1 -apple-system,BlinkMacSystemFont,sans-serif!important;'
          + 'box-shadow:0 2px 8px rgba(0,0,0,0.25)!important;cursor:pointer!important;'
          + 'pointer-events:auto!important;-webkit-tap-highlight-color:transparent!important;}'
          + '#' + BTN_ID + '{background:rgba(255,59,48,0.92)!important;}'
          + '#' + EDIT_BTN_ID + '{background:rgba(10,132,255,0.95)!important;}'
          + '#' + RESET_BTN_ID + '{background:rgba(142,142,147,0.95)!important;}';
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
        if (el.id === BAR_ID || el.id === BTN_ID || el.id === EDIT_BTN_ID || el.id === RESET_BTN_ID) return true;
        if (el.closest && el.closest('#' + BAR_ID)) return true;
        return false;
      }

      function directText(el) {
        if (!el) return '';
        var parts = [];
        for (var i = 0; i < el.childNodes.length; i++) {
          var n = el.childNodes[i];
          if (n.nodeType === 3) {
            var t = String(n.textContent || '').replace(/\\s+/g, ' ').trim();
            if (t) parts.push(t);
          }
        }
        return parts.join(' ');
      }

      function currentText(el) {
        if (!el) return '';
        var tag = (el.tagName || '').toLowerCase();
        if (tag === 'input' || tag === 'textarea') return String(el.value || '');
        var own = directText(el);
        if (own) return own;
        if (!el.children || el.children.length === 0) {
          return String(el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
        }
        return String(el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
      }

      function post(payload) {
        if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmPageCleaner) {
          webkit.messageHandlers.mmPageCleaner.postMessage(payload);
        }
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

      function isDecorative(el) {
        if (!el || el.nodeType !== 1) return true;
        var tag = (el.tagName || '').toLowerCase();
        return tag === 'svg' || tag === 'path' || tag === 'img' || tag === 'use'
          || tag === 'br' || tag === 'hr' || tag === 'canvas';
      }

      /// Prefer the smallest text host under the tap (e.g. status label), not the whole row link.
      function resolveTarget(el, clientX, clientY) {
        var candidates = [];
        try {
          if (typeof clientX === 'number' && typeof clientY === 'number'
              && document.elementsFromPoint) {
            candidates = document.elementsFromPoint(clientX, clientY) || [];
          }
        } catch (e) {}
        if ((!candidates || !candidates.length) && el) candidates = [el];

        var best = null;
        var bestArea = Infinity;
        for (var i = 0; i < candidates.length; i++) {
          var node = candidates[i];
          if (isIgnorable(node) || isDecorative(node)) continue;
          var tag = (node.tagName || '').toLowerCase();
          if (tag === 'html' || tag === 'body') continue;

          var own = directText(node);
          var leaf = (!node.children || node.children.length === 0)
            ? String(node.innerText || node.textContent || '').replace(/\\s+/g, ' ').trim()
            : '';
          var text = own || leaf;
          if (!text) continue;

          var all = String(node.innerText || '').replace(/\\s+/g, ' ').trim();
          // Skip fat wrappers whose visible text is much broader than this node's own text.
          if (own && all.length > own.length * 2 + 10) continue;
          if (!own && leaf && all.length > leaf.length * 2 + 10) continue;

          var r = node.getBoundingClientRect();
          if (r.width < 2 || r.height < 2) continue;
          var area = r.width * r.height;
          if (area < bestArea) {
            bestArea = area;
            best = node;
          }
        }
        if (best) return best;

        // Decorative / empty hit: fall back to clickable ancestor (whole control).
        var cur = el;
        for (var j = 0; j < 8 && cur && cur.nodeType === 1; j++) {
          var t = (cur.tagName || '').toLowerCase();
          if (t === 'html' || t === 'body') break;
          if (isClickable(cur)) return cur;
          var cls = classNames(cur).join(' ').toLowerCase();
          if (/open.?app|open-in-app|promo|banner|topbar|masthead/.test(cls)) return cur;
          cur = cur.parentElement;
        }
        return el;
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

      function removeActionBar() {
        var b = document.getElementById(BAR_ID);
        if (b && b.parentNode) b.parentNode.removeChild(b);
      }

      function placeActionBar(el) {
        removeActionBar();
        var bar = document.createElement('div');
        bar.id = BAR_ID;

        var del = document.createElement('button');
        del.id = BTN_ID;
        del.type = 'button';
        del.textContent = 'Delete';
        del.addEventListener('click', function(e) {
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
          removeActionBar();
          selected = null;
          post({
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
          });
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

        var edit = document.createElement('button');
        edit.id = EDIT_BTN_ID;
        edit.type = 'button';
        edit.textContent = 'Edit';
        edit.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          if (!selected) return;
          var target = selected;
          var selector = buildSelector(target);
          post({
            type: 'edit',
            selector: selector,
            label: labelFor(target),
            text: currentText(target),
            host: location.hostname || '',
            href: location.href || ''
          });
        }, true);

        var reset = document.createElement('button');
        reset.id = RESET_BTN_ID;
        reset.type = 'button';
        reset.textContent = 'Reset';
        reset.addEventListener('click', function(e) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          clearHighlight();
          removeActionBar();
          selected = null;
          post({
            type: 'reset',
            host: location.hostname || '',
            href: location.href || ''
          });
        }, true);

        bar.appendChild(del);
        bar.appendChild(edit);
        bar.appendChild(reset);
        (document.documentElement || document.body).appendChild(bar);
        var rect = el.getBoundingClientRect();
        var barWidth = 230;
        var top = Math.max(8, rect.top - 40);
        var left = Math.min(Math.max(8, rect.left), (window.innerWidth || 320) - barWidth);
        if (rect.top < 48) top = Math.min(rect.bottom + 8, (window.innerHeight || 480) - 40);
        bar.style.top = Math.round(top) + 'px';
        bar.style.left = Math.round(left) + 'px';
      }

      function onClick(e) {
        if (!api.enabled) return;
        var el = e.target;
        if (el && el.nodeType === 3) el = el.parentElement;
        if (el && el.closest && el.closest('#' + BAR_ID)) return;
        while (el && el.nodeType === 1 && isIgnorable(el)) {
          el = el.parentElement;
        }
        if (isIgnorable(el)) return;
        el = resolveTarget(el, e.clientX, e.clientY);
        if (isIgnorable(el)) return;
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        ensureStyle();
        clearHighlight();
        selected = el;
        el.classList.add(HIGHLIGHT);
        placeActionBar(el);
      }

      function onScroll() {
        if (selected) placeActionBar(selected);
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
          removeActionBar();
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
