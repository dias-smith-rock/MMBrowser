import Foundation
import WebKit

/// Hides Shorts UI and redirects `/shorts/` URLs to classic watch pages.
enum YouTubeShortsFocus {
    static let handlerName = "mmShortsFocus"

    static var isEnabled: Bool { AppSettings.hideShortsEnabled }

    /// If URL is a Shorts page, return a watch URL (or YouTube home) to load instead.
    static func redirectTarget(for url: URL?) -> URL? {
        guard isEnabled, let url = url, YouTubeDarkMode.isYouTube(url) else { return nil }
        let path = url.path.lowercased()
        guard path.hasPrefix("/shorts/") else { return nil }
        let id = url.pathComponents.last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        if id.count >= 6, id != "shorts" {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = "www.youtube.com"
            comps.path = "/watch"
            comps.queryItems = [URLQueryItem(name: "v", value: id)]
            return comps.url
        }
        return URL(string: "https://www.youtube.com/")
    }

    static var userScript: WKUserScript {
        let selectors = FilterUpdateManager.shared.shortsCSSSelectors
        let source = """
        (function() {
          if (window.__mmShortsFocusInstalled) return;
          window.__mmShortsFocusInstalled = true;
          var h = (location.hostname || '').toLowerCase();
          if (h !== 'youtu.be' && h.indexOf('youtube.com') === -1 && h.indexOf('youtube-nocookie.com') === -1) return;

          var SHELF_SELECTORS = \(jsonString(selectors));
          // Do NOT hide bare a[href^='/shorts/'] — that leaves empty card shells
          // (avatar + ⋮) in search/home feeds. Hide the whole item instead.
          var ITEM_SELECTORS = [
            'ytm-video-with-context-renderer',
            'ytm-compact-video-renderer',
            'ytm-media-item',
            'ytd-video-renderer',
            'ytd-rich-item-renderer',
            'ytd-grid-video-renderer',
            'ytm-rich-item-renderer',
            'ytm-item-section-renderer > lazy-list > ytm-video-with-context-renderer',
            'ytm-shorts-lockup-view-model',
            'ytm-reel-item-renderer',
            'ytm-shorts-lockup-view-model-host'
          ];

          function ensureStyle() {
            var style = document.getElementById('mm-shorts-focus-css');
            if (!style) {
              style = document.createElement('style');
              style.id = 'mm-shorts-focus-css';
              (document.documentElement || document.head || document.body).appendChild(style);
            }
            var shelf = SHELF_SELECTORS.length
              ? (SHELF_SELECTORS.join(',') + '{display:none!important;height:0!important;max-height:0!important;overflow:hidden!important;margin:0!important;padding:0!important;}')
              : '';
            style.textContent = shelf + '.mm-hide-shorts-item{display:none!important;height:0!important;max-height:0!important;overflow:hidden!important;margin:0!important;padding:0!important;border:0!important;}';
          }

          function isShortsHref(href) {
            if (!href) return false;
            try {
              var u = new URL(href, location.origin);
              return /\\/shorts\\//i.test(u.pathname);
            } catch (e) {
              return /\\/shorts\\//i.test(String(href));
            }
          }

          function closestItem(el) {
            if (!el || !el.closest) return null;
            return el.closest(ITEM_SELECTORS.join(','));
          }

          function hideLink(a) {
            if (!a || !a.getAttribute) return;
            if (!isShortsHref(a.getAttribute('href') || a.href)) return;
            // Keep bottom/pivot nav tabs — only hide feed cards.
            if (a.closest('ytm-pivot-bar-renderer, ytd-mini-guide-renderer, ytd-guide-renderer, nav, [role="navigation"]')) {
              var tab = a.closest('ytm-pivot-bar-item-renderer, ytd-guide-entry-renderer, ytd-mini-guide-entry-renderer, a');
              if (tab) tab.classList.add('mm-hide-shorts-item');
              return;
            }
            var item = closestItem(a);
            if (item) item.classList.add('mm-hide-shorts-item');
          }

          function hideShortsIn(root) {
            if (!root) return;
            if (root.nodeType === 1 && root.tagName === 'A') {
              hideLink(root);
              return;
            }
            if (!root.querySelectorAll) return;
            var links = root.querySelectorAll('a[href*="/shorts/"]');
            for (var i = 0; i < links.length; i++) hideLink(links[i]);
          }

          function hideShortsItems() {
            hideShortsIn(document);
          }

          function videoIdFromShortsPath(pathname) {
            var m = (pathname || '').match(/\\/shorts\\/([\\w-]{6,})/i);
            return m ? m[1] : null;
          }

          function redirectIfShorts(href) {
            try {
              var u = new URL(href || location.href, location.origin);
              var id = videoIdFromShortsPath(u.pathname);
              if (!id && !/\\/shorts\\/?$/i.test(u.pathname) && u.pathname.toLowerCase().indexOf('/shorts/') !== 0) return false;
              var target = id
                ? ('https://www.youtube.com/watch?v=' + encodeURIComponent(id))
                : 'https://www.youtube.com/';
              if (location.href !== target) {
                location.replace(target);
              }
              return true;
            } catch (e) { return false; }
          }

          function wrapHistory(fn) {
            return function() {
              var ret = fn.apply(this, arguments);
              try { redirectIfShorts(location.href); } catch (e) {}
              return ret;
            };
          }
          try {
            history.pushState = wrapHistory(history.pushState);
            history.replaceState = wrapHistory(history.replaceState);
          } catch (e) {}
          window.addEventListener('popstate', function() { redirectIfShorts(location.href); });

          var scheduled = false;
          var pendingRoots = null;
          var needsFull = false;
          function tick() {
            scheduled = false;
            ensureStyle();
            var full = needsFull;
            var roots = pendingRoots;
            needsFull = false;
            pendingRoots = null;
            if (full || !roots || !roots.length) {
              hideShortsItems();
            } else {
              for (var i = 0; i < roots.length; i++) hideShortsIn(roots[i]);
            }
            redirectIfShorts(location.href);
          }
          function schedule(roots) {
            if (roots && roots.length) {
              if (!needsFull) {
                if (!pendingRoots) pendingRoots = [];
                for (var i = 0; i < roots.length; i++) pendingRoots.push(roots[i]);
              }
            } else {
              needsFull = true;
              pendingRoots = null;
            }
            if (scheduled) return;
            scheduled = true;
            setTimeout(tick, 250);
          }

          ensureStyle();
          redirectIfShorts(location.href);
          schedule();

          try {
            new MutationObserver(function(mutations) {
              var roots = [];
              for (var i = 0; i < mutations.length; i++) {
                var nodes = mutations[i].addedNodes;
                for (var j = 0; j < nodes.length; j++) {
                  var n = nodes[j];
                  if (!n || n.nodeType !== 1) continue;
                  roots.push(n);
                }
              }
              if (roots.length) schedule(roots);
            }).observe(document.documentElement, { childList: true, subtree: true });
          } catch (e) {}
          document.addEventListener('DOMContentLoaded', function() { schedule(); }, { once: true });
        })();
        """
        // Shorts UI lives in the main YouTube document; skip iframe spam.
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    private static func jsonString(_ values: [String]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: values, options: [])
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
