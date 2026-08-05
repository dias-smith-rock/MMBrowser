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
        // Player / ad UI lives in the main YouTube document.
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
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
        } catch (e) {}
        return pr;
      }

      /** Replace a JSON array value for `key` with `[]` (bracket-balanced, string-aware). */
      function stripJsonArrayField(text, key) {
        var needle = '"' + key + '"';
        var idx = 0;
        var out = text;
        while ((idx = out.indexOf(needle, idx)) !== -1) {
          var colon = out.indexOf(':', idx + needle.length);
          if (colon === -1) break;
          var i = colon + 1;
          while (i < out.length && (out.charCodeAt(i) <= 32)) i++;
          if (out[i] !== '[') { idx = i; continue; }
          var depth = 0;
          var start = i;
          var j = i;
          for (; j < out.length; j++) {
            var ch = out[j];
            if (ch === '"') {
              j++;
              while (j < out.length) {
                if (out[j] === '\\\\') { j += 2; continue; }
                if (out[j] === '"') break;
                j++;
              }
              continue;
            }
            if (ch === '[') depth++;
            else if (ch === ']') {
              depth--;
              if (depth === 0) { j++; break; }
            }
          }
          out = out.slice(0, start) + '[]' + out.slice(j);
          idx = start + 2;
        }
        return out;
      }

      /** Delete `"key": <value>` (object/array/primitive) when value is a simple JSON token or balanced structure. */
      function stripJsonField(text, key) {
        var needle = '"' + key + '"';
        var idx = 0;
        var out = text;
        while ((idx = out.indexOf(needle, idx)) !== -1) {
          var colon = out.indexOf(':', idx + needle.length);
          if (colon === -1) break;
          var i = colon + 1;
          while (i < out.length && (out.charCodeAt(i) <= 32)) i++;
          var startKey = idx;
          // Include a preceding comma when present.
          var pre = startKey - 1;
          while (pre >= 0 && (out.charCodeAt(pre) <= 32)) pre--;
          var dropCommaBefore = pre >= 0 && out[pre] === ',';
          var from = dropCommaBefore ? pre : startKey;
          var j = i;
          var ch = out[j];
          if (ch === '{' || ch === '[') {
            var open = ch;
            var close = ch === '{' ? '}' : ']';
            var depth = 0;
            for (; j < out.length; j++) {
              var c = out[j];
              if (c === '"') {
                j++;
                while (j < out.length) {
                  if (out[j] === '\\\\') { j += 2; continue; }
                  if (out[j] === '"') break;
                  j++;
                }
                continue;
              }
              if (c === open) depth++;
              else if (c === close) {
                depth--;
                if (depth === 0) { j++; break; }
              }
            }
          } else if (ch === '"') {
            j++;
            while (j < out.length) {
              if (out[j] === '\\\\') { j += 2; continue; }
              if (out[j] === '"') { j++; break; }
              j++;
            }
          } else {
            while (j < out.length && /[\\w.+\\-eE]/.test(out[j])) j++;
          }
          // Drop trailing comma if we did not drop a preceding one.
          var k = j;
          while (k < out.length && (out.charCodeAt(k) <= 32)) k++;
          if (!dropCommaBefore && out[k] === ',') j = k + 1;
          out = out.slice(0, from) + out.slice(j);
          idx = from;
        }
        return out;
      }

      function looksLikeAdPayload(text) {
        return text.indexOf('adPlacement') !== -1
          || text.indexOf('playerAds') !== -1
          || text.indexOf('"adSlots"') !== -1
          || text.indexOf('adBreakHeartbeat') !== -1
          || text.indexOf('premiumUpsell') !== -1;
      }

      function isPlayerURL(url) {
        return /\\/youtubei\\/v1\\/player/i.test(url) || /\\/get_video_info/i.test(url);
      }

      /** Prefer light string rewrite; fall back to JSON.parse only if needed. */
      function cleanJSONText(text) {
        if (!text || !looksLikeAdPayload(text)) return text;
        try {
          var light = text;
          light = stripJsonArrayField(light, 'adPlacements');
          light = stripJsonArrayField(light, 'adSlots');
          light = stripJsonArrayField(light, 'playerAds');
          light = stripJsonArrayField(light, 'messages');
          light = stripJsonField(light, 'adBreakHeartbeatParams');
          if (light !== text) return light;
        } catch (e) {}
        try {
          var obj = JSON.parse(text);
          if (obj.playerResponse) obj.playerResponse = cleanPlayerResponse(obj.playerResponse);
          else obj = cleanPlayerResponse(obj);
          return JSON.stringify(obj);
        } catch (e2) {
          return text;
        }
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

      // Fetch: only player / video-info URLs; avoid clone when rewriting.
      try {
        var origFetch = window.fetch;
        if (typeof origFetch === 'function') {
          window.fetch = function() {
            var args = arguments;
            var input = args[0];
            var url = (typeof input === 'string') ? input : (input && input.url) || '';
            var rewrite = isPlayerURL(url);
            return origFetch.apply(this, args).then(function(resp) {
              if (!rewrite) return resp;
              try {
                return resp.text().then(function(t) {
                  var cleaned = cleanJSONText(t);
                  return new Response(cleaned, {
                    status: resp.status,
                    statusText: resp.statusText,
                    headers: resp.headers
                  });
                });
              } catch (e) {
                return resp;
              }
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
          if (this.__mmUrl && isPlayerURL(String(this.__mmUrl))) {
            this.addEventListener('readystatechange', function() {
              if (self.readyState !== 4) return;
              try {
                var t = self.responseText;
                if (!looksLikeAdPayload(t)) return;
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

      function skipAdDom() {
        if (document.hidden) return;
        try {
          var player = document.querySelector('.html5-video-player.ad-showing, .ad-showing.html5-video-player');
          if (!player) return;
          var skip = player.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button, button.ytp-ad-skip-button-container')
            || document.querySelector('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button');
          if (skip) { try { skip.click(); } catch (e) {} }
          var v = player.querySelector('video');
          if (v && isFinite(v.duration) && v.duration > 0) {
            try { v.currentTime = Math.max(v.duration - 0.2, 0); } catch (e) {}
          }
        } catch (e) {}
      }

      var skipTimer = null;
      var playerMO = null;
      function ensurePlayerMO() {
        if (document.hidden) return;
        var player = document.querySelector('.html5-video-player');
        if (!player) return;
        if (player.__mmAdMOAttached) return;
        if (playerMO) {
          try { playerMO.disconnect(); } catch (e) {}
          playerMO = null;
        }
        try {
          var pending = null;
          playerMO = new MutationObserver(function() {
            if (document.hidden) return;
            if (pending) return;
            pending = setTimeout(function() {
              pending = null;
              skipAdDom();
            }, 120);
          });
          playerMO.observe(player, { attributes: true, attributeFilter: ['class'] });
          player.__mmAdMOAttached = true;
        } catch (e) {
          playerMO = null;
        }
      }
      function startSkipLoop() {
        if (skipTimer || document.hidden) return;
        skipTimer = setInterval(function() {
          ensurePlayerMO();
          skipAdDom();
        }, 1400);
        ensurePlayerMO();
      }
      function stopSkipLoop() {
        if (skipTimer) {
          clearInterval(skipTimer);
          skipTimer = null;
        }
        if (playerMO) {
          try { playerMO.disconnect(); } catch (e) {}
          playerMO = null;
        }
      }
      document.addEventListener('visibilitychange', function() {
        if (document.hidden) stopSkipLoop();
        else { startSkipLoop(); skipAdDom(); }
      });
      startSkipLoop();

      // Detect anti-adblock / locked player via DOM only (no body.innerText).
      var degradedSent = false;
      var degradeTimer = null;
      function checkDegraded() {
        if (degradedSent || document.hidden) return;
        try {
          var lock = document.querySelector(
            'ytd-enforcement-message-view-model, .yt-playability-error-supported-renderers'
          );
          if (!lock) return;
          degradedSent = true;
          stopDegradeLoop();
          if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmYouTubeAdShieldDegraded) {
            webkit.messageHandlers.mmYouTubeAdShieldDegraded.postMessage({ type: 'degraded' });
          }
        } catch (e) {}
      }
      function startDegradeLoop() {
        if (degradeTimer || degradedSent || document.hidden) return;
        degradeTimer = setInterval(checkDegraded, 4000);
      }
      function stopDegradeLoop() {
        if (!degradeTimer) return;
        clearInterval(degradeTimer);
        degradeTimer = null;
      }
      document.addEventListener('visibilitychange', function() {
        if (document.hidden) stopDegradeLoop();
        else startDegradeLoop();
      });
      startDegradeLoop();
    })();
    """
}
