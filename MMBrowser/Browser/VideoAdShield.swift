import Foundation
import WebKit

/// Best-effort generic video / overlay / popunder ad reduction for any site.
/// Complements WKContentRuleList network + cosmetic filters (not site-category specific).
enum VideoAdShield {
    static var userScript: WKUserScript {
        WKUserScript(source: bundledScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static func isLikelyAdPopup(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.absoluteString.lowercased()
        if host.isEmpty { return false }
        for domain in knownAdHosts where host == domain || host.hasSuffix("." + domain) {
            return true
        }
        if path.contains("popunder") || path.contains("pop-under") { return true }
        if path.contains("/ads/") || path.contains("adserver") || path.contains("clickunder") {
            return true
        }
        return false
    }

    /// Known third-party ad / popunder networks (used for popup heuristics + script).
    static let knownAdHosts: [String] = [
        "exoclick.com", "syndication.exoclick.com", "ads.exoclick.com", "main.exoclick.com",
        "juicyads.com", "ads.juicyads.com", "js.juicyads.com", "poweredby.jads.co", "jads.co",
        "trafficjunky.com", "ads.trafficjunky.net", "content.trafficjunky.net",
        "popads.net", "serve.popads.net", "popcash.net", "cdn.popcash.net",
        "hilltopads.com", "htopads.com", "adsterra.com", "ads.adsterra.com",
        "tsyndicate.com", "cdn.tsyndicate.com", "clickadu.com", "abertona.com",
        "adxpansion.com", "ads.adxpansion.com",
        "trafficfactory.biz", "a.trafficfactory.biz", "go.trafficfactory.biz",
        "plugrush.com", "onclickads.net", "onclickmax.com",
        "propellerads.com", "propellerclick.com",
        "realsrv.com", "juicytraffic.com",
        "adsbookie.com", "adserver.juicyads.com", "creative.juicyads.com",
        "s.zkcdn.net", "twinred.com", "twinreda.com"
    ]

    private static let bundledScript: String = #"""
    (function() {
      if (window.__mmVideoAdShield) return;
      window.__mmVideoAdShield = true;

      var AD_HOST_RE = /(exoclick|juicyads|jads\.co|trafficjunky|popads|popcash|hilltopads|adsterra|tsyndicate|clickadu|trafficfactory|plugrush|onclickads|onclickmax|propellerads|propellerclick|realsrv|adsbookie|twinred|adxpansion|abertona)/i;
      var SKIP_TEXT_RE = /^(skip(\s*ad)?|skip\s*advertisement|close\s*ad)$/i;
      var SKIP_CONTAINS_RE = /skip\s*(ad|ads|advertisement)|close\s*ad/;

      // Block window.open to known ad / popunder networks (keep auth flows).
      try {
        var nativeOpen = window.open;
        window.open = function(url, name, features) {
          try {
            var raw = (typeof url === 'string') ? url : (url ? String(url) : '');
            var lower = raw.toLowerCase();
            if (!raw || lower === 'about:blank') {
              return nativeOpen.apply(window, arguments);
            }
            if (/accounts\.google|appleid|oauth|login|signin|sso|auth0|facebook\.com\/|twitter\.com\/|x\.com\//i.test(lower)) {
              return nativeOpen.apply(window, arguments);
            }
            if (AD_HOST_RE.test(lower) || /popunder|clickunder|\/ads\/|adserver/i.test(lower)) {
              return null;
            }
            if (/\.(php|ashx)(\?|$)/i.test(lower) && /[?&](utm_|aff|banner|pop|ad)=/i.test(lower) && AD_HOST_RE.test(lower)) {
              return null;
            }
          } catch (e2) {}
          return nativeOpen.apply(window, arguments);
        };
      } catch (e3) {}

      function killNode(n) {
        try { n.remove(); } catch (e) {
          try { n.style.setProperty('display', 'none', 'important'); } catch (e4) {}
        }
      }

      function stripAdFrames(root) {
        try {
          var frames = (root || document).querySelectorAll('iframe, embed, object');
          for (var i = 0; i < frames.length; i++) {
            var f = frames[i];
            var sig = ((f.src || '') + ' ' + (f.id || '') + ' ' + (f.className || '') + ' ' + (f.name || '')).toLowerCase();
            if (AD_HOST_RE.test(sig) || /vast|popunder|ad-iframe|adiframe|bannerad|video[-_]?ad|preroll/i.test(sig)) {
              killNode(f);
            }
          }
        } catch (e5) {}
      }

      function clickSkips(root) {
        try {
          var scope = root || document;
          var sels = [
            '#skip-button', '.skip-button', '.skipAd', '.skip-ad', '.vast-skip-button',
            '[class*="skip-ad"]', '[class*="SkipAd"]', '[class*="skipAd"]',
            '.ad-close', '.close-ad', '[aria-label*="Skip"]', '[aria-label*="skip"]',
            'button[class*="skip"]', 'div[class*="skip"][role="button"]'
          ];
          for (var s = 0; s < sels.length; s++) {
            var list = scope.querySelectorAll(sels[s]);
            for (var j = 0; j < list.length; j++) {
              try { list[j].click(); } catch (e6) {}
            }
          }
          var nodes = scope.querySelectorAll('button, a, div, span');
          for (var i = 0; i < nodes.length; i++) {
            var el = nodes[i];
            var t = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
            if (!t || t.length > 36) continue;
            if (SKIP_TEXT_RE.test(t) || SKIP_CONTAINS_RE.test(t)) {
              try { el.click(); } catch (e7) {}
            }
          }
        } catch (e8) {}
      }

      // Pause secondary overlay videos that clearly load from ad hosts.
      function pauseStrayAdVideos() {
        try {
          var vids = document.querySelectorAll('video');
          if (vids.length < 2) return;
          var main = null;
          var maxArea = 0;
          for (var i = 0; i < vids.length; i++) {
            var r = vids[i].getBoundingClientRect();
            var area = Math.max(0, r.width) * Math.max(0, r.height);
            if (area > maxArea) { maxArea = area; main = vids[i]; }
          }
          for (var k = 0; k < vids.length; k++) {
            var v = vids[k];
            if (v === main) continue;
            var src = '';
            try { src = (v.currentSrc || v.src || '') + ''; } catch (e9) {}
            if (!AD_HOST_RE.test(src)) continue;
            try { v.pause(); v.removeAttribute('src'); v.load(); } catch (e10) {}
            killNode(v);
          }
        } catch (e11) {}
      }

      function sweep(root) {
        stripAdFrames(root);
        clickSkips(root);
        pauseStrayAdVideos();
      }

      function boot() {
        sweep(document);
        try {
          var mo = new MutationObserver(function(muts) {
            for (var i = 0; i < muts.length; i++) {
              var m = muts[i];
              if (m.addedNodes) {
                for (var j = 0; j < m.addedNodes.length; j++) {
                  var n = m.addedNodes[j];
                  if (n && n.nodeType === 1) sweep(n);
                }
              }
            }
          });
          mo.observe(document.documentElement || document, { childList: true, subtree: true });
        } catch (e12) {}
        setInterval(function() { clickSkips(document); pauseStrayAdVideos(); }, 1200);
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot, { once: true });
      } else {
        boot();
      }
      try { stripAdFrames(document); } catch (e13) {}
    })();
    """#
}
