import Foundation
import WebKit

/// Best-effort YouTube pre-roll / mid-roll reduction via player JSON rewriting.
/// Fragile by nature — remote kill-switch and script updates live in FilterUpdateManager.
enum YouTubeAdShield {
    static let handlerName = "mmYouTubeAdShield"
    static let degradedHandlerName = "mmYouTubeAdShieldDegraded"

    static var isEffectivelyEnabled: Bool {
        AppSettings.youtubeAdShieldEnabled && FilterUpdateManager.shared.remoteAllowsYouTubeAdShield
    }

    static var userScript: WKUserScript {
        let remote = FilterUpdateManager.shared.youtubeAdShieldScript
        let source = remote.isEmpty ? bundledScript : remote
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    /// Bundled fallback when CDN has not supplied a script yet.
    private static let bundledScript: String = """
    (function() {
      if (window.__mmYTAdShieldInstalled) return;
      window.__mmYTAdShieldInstalled = true;
      var h = (location.hostname || '').toLowerCase();
      if (h !== 'youtu.be' && h.indexOf('youtube.com') === -1 && h.indexOf('youtube-nocookie.com') === -1) return;

      function cleanPlayerResponse(pr) {
        if (!pr || typeof pr !== 'object') return pr;
        try {
          if (pr.adPlacements) pr.adPlacements = [];
          if (pr.adSlots) pr.adSlots = [];
          if (pr.playerAds) pr.playerAds = [];
          if (pr.adBreakHeartbeatParams) delete pr.adBreakHeartbeatParams;
          if (pr.playerConfig && pr.playerConfig.audioConfig) {
            pr.playerConfig.audioConfig.autoplayPolicy = 'ALWAYS_AUTOPLAY';
          }
          var pv = pr.playerConfig && pr.playerConfig.attsConfig;
          if (pv) { try { pv.useFuse = false; } catch (e) {} }
          if (pr.auxiliaryUi && pr.auxiliaryUi.messageRenderers) {
            delete pr.auxiliaryUi.messageRenderers.premiumUpsellDialogRenderer;
          }
          if (pr.messages) pr.messages = [];
          var vd = pr.videoDetails;
          if (vd) {
            vd.isLive = vd.isLive || false;
          }
        } catch (e) {}
        return pr;
      }

      function cleanJSONText(text) {
        try {
          var obj = JSON.parse(text);
          if (obj.playerResponse) obj.playerResponse = cleanPlayerResponse(obj.playerResponse);
          if (obj.adPlacements) obj = cleanPlayerResponse(obj);
          return JSON.stringify(obj);
        } catch (e) { return text; }
      }

      // ytInitialPlayerResponse
      try {
        var desc = Object.getOwnPropertyDescriptor(window, 'ytInitialPlayerResponse');
        if (!desc || desc.configurable) {
          var _pr = window.ytInitialPlayerResponse;
          Object.defineProperty(window, 'ytInitialPlayerResponse', {
            configurable: true,
            get: function() { return _pr; },
            set: function(v) { _pr = cleanPlayerResponse(v); }
          });
          if (_pr) _pr = cleanPlayerResponse(_pr);
        } else if (window.ytInitialPlayerResponse) {
          cleanPlayerResponse(window.ytInitialPlayerResponse);
        }
      } catch (e) {}

      // ytInitialData path for home ads (best-effort)
      try {
        if (window.ytInitialData) {
          // leave structure; shorts handled elsewhere
        }
      } catch (e) {}

      // Fetch / XHR youtubei player
      try {
        var origFetch = window.fetch;
        if (typeof origFetch === 'function') {
          window.fetch = function() {
            var args = arguments;
            var input = args[0];
            var url = (typeof input === 'string') ? input : (input && input.url) || '';
            return origFetch.apply(this, args).then(function(resp) {
              try {
                if (/\\/youtubei\\/v1\\/player/i.test(url) || /\\/get_video_info/i.test(url)) {
                  return resp.clone().text().then(function(t) {
                    var cleaned = cleanJSONText(t);
                    return new Response(cleaned, {
                      status: resp.status,
                      statusText: resp.statusText,
                      headers: resp.headers
                    });
                  });
                }
              } catch (e) {}
              return resp;
            });
          };
        }
      } catch (e) {}

      try {
        var XO = XMLHttpRequest.prototype.open;
        var XS = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(method, url) {
          this.__mmUrl = url;
          return XO.apply(this, arguments);
        };
        XMLHttpRequest.prototype.send = function() {
          var self = this;
          if (this.__mmUrl && /\\/youtubei\\/v1\\/player/i.test(String(this.__mmUrl))) {
            this.addEventListener('readystatechange', function() {
              if (self.readyState !== 4) return;
              try {
                var t = self.responseText;
                var cleaned = cleanJSONText(t);
                if (cleaned !== t) {
                  Object.defineProperty(self, 'responseText', { get: function() { return cleaned; } });
                  Object.defineProperty(self, 'response', { get: function() { return cleaned; } });
                }
              } catch (e) {}
            });
          }
          return XS.apply(this, arguments);
        };
      } catch (e) {}

      // Skip UI when .ad-showing appears
      function skipAdDom() {
        try {
          var player = document.querySelector('.html5-video-player.ad-showing, .ad-showing');
          if (!player) return;
          var skip = document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, button[class*="skip"]');
          if (skip) { try { skip.click(); } catch (e) {} }
          var v = player.querySelector('video');
          if (v && isFinite(v.duration) && v.duration > 0) {
            try { v.currentTime = Math.max(v.duration - 0.2, 0); } catch (e) {}
          }
          try {
            if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmYouTubeAdShield) {
              webkit.messageHandlers.mmYouTubeAdShield.postMessage({ type: 'skipped' });
            }
          } catch (e) {}
        } catch (e) {}
      }
      setInterval(skipAdDom, 700);

      // Detect anti-adblock / locked player
      var degradedSent = false;
      function checkDegraded() {
        if (degradedSent) return;
        try {
          var lock = document.querySelector('ytd-enforcement-message-view-model, .yt-playability-error-supported-renderers');
          var text = (document.body && document.body.innerText) || '';
          if (lock || /ad blocker|blockers are not allowed|video player will resume/i.test(text)) {
            degradedSent = true;
            if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmYouTubeAdShieldDegraded) {
              webkit.messageHandlers.mmYouTubeAdShieldDegraded.postMessage({ type: 'degraded' });
            }
          }
        } catch (e) {}
      }
      setInterval(checkDegraded, 2500);
    })();
    """
}
