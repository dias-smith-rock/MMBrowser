import AVFoundation
import WebKit

/// Background audio + Picture-in-Picture helpers for cleaner video browsing.
enum MediaPlaybackSupport {
    static let pipHandlerName = "mmMediaPip"

    static func configureAudioSessionIfNeeded() {
        guard AppSettings.backgroundAudioEnabled else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[MediaPlayback] audio session: \(error.localizedDescription)")
        }
    }

    static func apply(to configuration: WKWebViewConfiguration) {
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = AppSettings.pictureInPictureEnabled
        if #available(iOS 15.0, *) {
            // Prefer HTML5 media without forcing user gesture on mute-friendly sites.
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        if AppSettings.backgroundAudioEnabled || AppSettings.pictureInPictureEnabled {
            // Install before page scripts so YouTube cannot observe presentation-mode changes.
            configuration.userContentController.addUserScript(mediaScript)
        }
    }

    /// Call after in-app UI or snapshot work that may interrupt HTML5 video.
    /// Skips while Picture in Picture owns the video so returning to the app does not reclaim it.
    static func resumeMediaIfNeeded(in webView: WKWebView?) {
        guard let webView else { return }
        webView.evaluateJavaScript(resumeJS, completionHandler: nil)
    }

    /// Reinforce PiP after the host app becomes active (YouTube otherwise reclaiming inline).
    static func reinforcePictureInPictureIfNeeded(in webView: WKWebView?) {
        guard let webView, AppSettings.pictureInPictureEnabled else { return }
        webView.evaluateJavaScript(reinforcePipJS, completionHandler: nil)
    }

    /// Enter PiP for the best matching video (used by menu). Prefer the on-page PiP chip
    /// on YouTube Music — `webkitSetPresentationMode` is most reliable inside a page gesture.
    static func enterPictureInPicture(in webView: WKWebView?, completion: ((Bool) -> Void)? = nil) {
        guard let webView, AppSettings.pictureInPictureEnabled else {
            completion?(false)
            return
        }
        webView.evaluateJavaScript(enterPipJS) { result, _ in
            completion?((result as? Bool) ?? false)
        }
    }

    /// Seed page-level prefer flag after navigation (document scripts reset `window` state).
    static func seedStickyPrefer(in webView: WKWebView?) {
        guard let webView, AppSettings.pictureInPictureEnabled, AppSettings.stickyPictureInPicture else { return }
        webView.evaluateJavaScript("window.__mmPreferPip = true;", completionHandler: nil)
    }

    /// After a new page loads, restore sticky PiP intent and try to enter when a video exists.
    static func restoreStickyPictureInPictureIfNeeded(in webView: WKWebView?, completion: ((Bool) -> Void)? = nil) {
        guard let webView, AppSettings.pictureInPictureEnabled, AppSettings.stickyPictureInPicture else {
            completion?(false)
            return
        }
        webView.evaluateJavaScript("window.__mmPreferPip = true; true;") { _, _ in
            webView.evaluateJavaScript(enterPipJS) { result, _ in
                let ok = (result as? Bool) ?? false
                if !ok {
                    reinforcePictureInPictureIfNeeded(in: webView)
                }
                completion?(ok)
            }
        }
    }

    /// Sync sticky PiP intent into the page (survives full document loads via AppSettings).
    static func applyStickyPrefer(in webView: WKWebView?, prefer: Bool) {
        guard let webView else { return }
        let value = prefer ? "true" : "false"
        webView.evaluateJavaScript("window.__mmPreferPip = \(value);", completionHandler: nil)
    }

    private static let enterPipJS = """
    (function() {
      try {
        if (typeof window.__mmEnterPiP === 'function') return !!window.__mmEnterPiP();
        return false;
      } catch (e) { return false; }
    })();
    """

    private static let reinforcePipJS = """
    (function() {
      try {
        var prefer = !!window.__mmPreferPip;
        var inPip = (typeof window.__mmAnyInPiP === 'function') && window.__mmAnyInPiP();
        if (!prefer && !inPip) return;
        window.__mmPreferPip = true;
        if (!inPip && typeof window.__mmEnterPiP === 'function') {
          window.__mmEnterPiP();
          return;
        }
        document.querySelectorAll('video').forEach(function(v) {
          if (v.dataset.mmWantPip !== '1' && v.webkitPresentationMode !== 'picture-in-picture') return;
          v.dataset.mmWantPip = '1';
          if (v.paused && !v.ended) {
            var p = v.play();
            if (p && p.catch) p.catch(function(){});
          }
          if (v.webkitPresentationMode !== 'picture-in-picture') {
            var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
            if (raw) {
              try { raw.call(v, 'picture-in-picture'); } catch (e) {}
            }
          }
        });
      } catch (e) {}
    })();
    """

    private static let resumeJS = """
    (function() {
      try {
        if (typeof window.__mmAnyInPiP === 'function' && window.__mmAnyInPiP()) return;
        if (typeof window.__mmResumeMedia === 'function') { window.__mmResumeMedia(); return; }
        document.querySelectorAll('video').forEach(function(v) {
          if (v.webkitPresentationMode === 'picture-in-picture') return;
          if (document.pictureInPictureElement === v) return;
          if (v.paused && !v.ended && v.currentTime > 0) {
            var p = v.play();
            if (p && p.catch) p.catch(function(){});
          }
        });
      } catch (e) {}
    })();
    """

    /// Soft keep-alive + PiP state bridge.
    /// YouTube listens for `webkitpresentationmodechanged` / `visibilitychange` and forces
    /// inline playback (Premium upsell). We capture those events first, notify native, then
    /// stop propagation so the site cannot dismiss system PiP when the app returns.
    private static var mediaScript: WKUserScript {
        let source = """
        (function() {
          if (window.__mmMediaKeepAlive) return;
          window.__mmMediaKeepAlive = true;

          // Sticky user/system intent to stay in PiP across YouTube "next video" swaps.
          if (typeof window.__mmPreferPip === 'undefined') window.__mmPreferPip = false;
          var reenterToken = 0;

          function postPip(active) {
            try {
              if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmMediaPip) {
                webkit.messageHandlers.mmMediaPip.postMessage({
                  active: !!active,
                  prefer: !!window.__mmPreferPip
                });
              }
            } catch (e) {}
          }

          function isInPiP(v) {
            try {
              if (!v) return false;
              if (document.pictureInPictureElement === v) return true;
              if (v.webkitPresentationMode === 'picture-in-picture') return true;
            } catch (e) {}
            return false;
          }

          /// Actually presenting in system PiP (do not include sticky intent).
          function anyInPiP() {
            try {
              if (document.pictureInPictureElement) return true;
              var vids = document.querySelectorAll('video');
              for (var i = 0; i < vids.length; i++) {
                if (isInPiP(vids[i])) return true;
              }
            } catch (e) {}
            return false;
          }
          window.__mmAnyInPiP = anyInPiP;

          function wantsPip() {
            try {
              return !!window.__mmPreferPip
                || !!document.querySelector('video[data-mm-want-pip="1"]')
                || anyInPiP();
            } catch (e) { return false; }
          }

          function clearPreferPip() {
            window.__mmPreferPip = false;
            reenterToken += 1;
            try {
              document.querySelectorAll('video').forEach(function(v) {
                try { v.dataset.mmWantPip = '0'; } catch (e) {}
              });
            } catch (e) {}
            postPip(false);
            syncPipChip();
          }
          window.__mmClearPreferPip = clearPreferPip;

          function videoSrc(v) {
            try { return (v && (v.currentSrc || v.src)) || ''; } catch (e) { return ''; }
          }

          /// After PiP drops (next video / element swap), re-enter unless the user dismissed.
          function schedulePipReenter(previousVideo) {
            if (!window.__mmPreferPip) return;
            var token = ++reenterToken;
            var prevSrc = videoSrc(previousVideo);
            var delays = [180, 450, 900, 1600, 2600];
            delays.forEach(function(ms, idx) {
              setTimeout(function() {
                if (token !== reenterToken || !window.__mmPreferPip) return;
                if (anyInPiP()) {
                  postPip(true);
                  return;
                }
                var v = pickVideo();
                if (!v) {
                  if (idx === delays.length - 1) clearPreferPip();
                  return;
                }
                var src = videoSrc(v);
                var sameClip = previousVideo
                  && v === previousVideo
                  && src
                  && src === prevSrc
                  && !v.ended;
                if (sameClip) {
                  // Same clip still inline → user closed PiP (wait for last tick).
                  if (idx === delays.length - 1) clearPreferPip();
                  return;
                }
                // New / replaced media — put it back in PiP.
                enterPiP();
              }, ms);
            });
          }

          function unlockVideo(v) {
            if (!v) return;
            try { v.disablePictureInPicture = false; } catch (e) {}
            try {
              if (v.hasAttribute('disablePictureInPicture')) v.removeAttribute('disablePictureInPicture');
            } catch (e) {}
          }

          // Block site JS (YouTube) from forcing the player back to inline while PiP should stay.
          try {
            var proto = HTMLVideoElement.prototype;
            if (proto.webkitSetPresentationMode && !proto.__mmSetPresentationMode) {
              var originalSet = proto.webkitSetPresentationMode;
              proto.__mmSetPresentationMode = originalSet;
              proto.webkitSetPresentationMode = function(mode) {
                try {
                  if (mode === 'inline' && (window.__mmPreferPip || (this.dataset && this.dataset.mmWantPip === '1'))) {
                    return;
                  }
                } catch (e) {}
                return originalSet.call(this, mode);
              };
            }
            try {
              Object.defineProperty(proto, 'disablePictureInPicture', {
                configurable: true,
                get: function() { return false; },
                set: function() {}
              });
            } catch (e) {}
          } catch (e) {}

          function markPlayingState() {
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (!v.paused && !v.ended) v.dataset.mmWantPlay = '1';
              });
            } catch (e) {}
          }

          function resumeVideos() {
            if (wantsPip()) return;
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (isInPiP(v) || v.dataset.mmWantPip === '1') return;
                if (v.dataset.mmWantPlay !== '1') return;
                if (v.paused && !v.ended) {
                  var p = v.play();
                  if (p && p.catch) p.catch(function(){});
                }
              });
            } catch (e) {}
          }

          function keepPipPlaying() {
            try {
              if (window.__mmPreferPip && !anyInPiP()) {
                schedulePipReenter(pickVideo());
              }
              document.querySelectorAll('video').forEach(function(v) {
                if (!window.__mmPreferPip && v.dataset.mmWantPip !== '1' && !isInPiP(v)) return;
                if (window.__mmPreferPip || isInPiP(v)) v.dataset.mmWantPip = '1';
                if (v.paused && !v.ended) {
                  var p = v.play();
                  if (p && p.catch) p.catch(function(){});
                }
              });
            } catch (e) {}
          }

          window.__mmResumeMedia = function() {
            if (wantsPip()) {
              keepPipPlaying();
              return;
            }
            markPlayingState();
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (isInPiP(v) || v.ended) return;
                if (v.dataset.mmWantPlay === '1' || v.currentTime > 0.25) {
                  v.dataset.mmWantPlay = '1';
                  if (v.paused) {
                    var p = v.play();
                    if (p && p.catch) p.catch(function(){});
                  }
                }
              });
            } catch (e) {}
          };

          function bindVideo(v) {
            if (!v || v.dataset.mmPipBound === '1') return;
            v.dataset.mmPipBound = '1';
            unlockVideo(v);
            if (isInPiP(v)) {
              v.dataset.mmWantPip = '1';
              postPip(true);
            }
          }

          function isYouTubeFamily() {
            try {
              var h = (location.hostname || '').toLowerCase();
              return h === 'youtu.be'
                || h.indexOf('youtube.com') !== -1
                || h.indexOf('youtube-nocookie.com') !== -1
                || h.indexOf('music.youtube.com') !== -1;
            } catch (e) { return false; }
          }

          function pickVideo() {
            var vids = Array.prototype.slice.call(document.querySelectorAll('video'));
            if (!vids.length) return null;
            vids.sort(function(a, b) {
              var sa = (!a.paused && !a.ended ? 2000 : 0)
                + ((a.readyState || 0) * 20)
                + Math.min(a.videoWidth || 0, 800)
                + (a.currentTime > 0 ? 50 : 0);
              var sb = (!b.paused && !b.ended ? 2000 : 0)
                + ((b.readyState || 0) * 20)
                + Math.min(b.videoWidth || 0, 800)
                + (b.currentTime > 0 ? 50 : 0);
              return sb - sa;
            });
            return vids[0];
          }

          function enterPiP() {
            var v = pickVideo();
            if (!v) return false;
            window.__mmPreferPip = true;
            unlockVideo(v);
            bindVideo(v);
            v.dataset.mmWantPip = '1';
            v.dataset.mmWantPlay = '1';
            function go() {
              try {
                var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
                if (raw) raw.call(v, 'picture-in-picture');
                else if (typeof v.webkitSetPresentationMode === 'function') v.webkitSetPresentationMode('picture-in-picture');
                else if (v.requestPictureInPicture) v.requestPictureInPicture();
              } catch (e) {}
              postPip(true);
              setTimeout(syncPipChip, 100);
            }
            try {
              if (v.paused) {
                var p = v.play();
                if (p && p.then) p.then(go).catch(go);
                else go();
              } else {
                go();
              }
            } catch (e) { go(); }
            return true;
          }
          window.__mmEnterPiP = enterPiP;

          function postVideoReady() {
            try {
              var v = pickVideo();
              var ready = !!(v && (
                (!v.paused && !v.ended)
                || v.currentTime > 0.05
                || v.readyState >= 2
                || (isYouTubeFamily() && !!v)
              ));
              if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmMediaPip) {
                webkit.messageHandlers.mmMediaPip.postMessage({ videoReady: ready });
              }
            } catch (e) {}
          }

          function ensurePipChip() {
            try { if (window.top !== window) return; } catch (e) { return; }
            var btn = document.getElementById('mm-pip-chip');
            if (btn && btn.isConnected) return;
            if (btn && !btn.isConnected) {
              try { btn.remove(); } catch (e) {}
            }
            btn = document.createElement('button');
            btn.id = 'mm-pip-chip';
            btn.type = 'button';
            btn.textContent = 'PiP';
            btn.setAttribute('aria-label', 'Picture in Picture');
            btn.style.cssText = [
              'position:fixed',
              'top:max(56px, calc(env(safe-area-inset-top) + 44px))',
              'right:12px',
              'z-index:2147483646',
              'padding:8px 12px',
              'border:none',
              'border-radius:16px',
              'background:rgba(20,20,20,0.82)',
              'color:#fff',
              'font:600 13px -apple-system,BlinkMacSystemFont,sans-serif',
              'letter-spacing:0.02em',
              'box-shadow:0 4px 14px rgba(0,0,0,0.35)',
              'display:none',
              '-webkit-tap-highlight-color:transparent',
              'cursor:pointer',
              'pointer-events:auto'
            ].join(';');
            btn.addEventListener('click', function(ev) {
              try { ev.preventDefault(); ev.stopImmediatePropagation(); ev.stopPropagation(); } catch (e) {}
              enterPiP();
            }, true);
            var host = document.body || document.documentElement;
            if (host) host.appendChild(btn);
          }

          function syncPipChip() {
            try {
              // Prefer the native browser PiP control on YouTube; keep the chip as a fallback
              // for non-YouTube pages and when the native button is unavailable.
              ensurePipChip();
              var btn = document.getElementById('mm-pip-chip');
              if (!btn) return;
              var v = pickVideo();
              var show = !!v && !anyInPiP() && !isYouTubeFamily()
                && ((!v.paused && !v.ended) || v.currentTime > 0.2);
              btn.style.display = show ? 'block' : 'none';
              postVideoReady();
            } catch (e) {}
          }

          function scanVideos() {
            try {
              document.querySelectorAll('video').forEach(bindVideo);
              if (anyInPiP()) postPip(true);
              syncPipChip();
            } catch (e) {}
          }

          // Capture at document BEFORE YouTube's listeners. Stopping propagation is what
          // unlocks PiP on YouTube and stops it from dismissing PiP when the app returns.
          document.addEventListener('webkitpresentationmodechanged', function(e) {
            var v = e.target;
            if (v && v.tagName === 'VIDEO') {
              unlockVideo(v);
              if (isInPiP(v)) {
                window.__mmPreferPip = true;
                v.dataset.mmWantPip = '1';
                v.dataset.mmWantPlay = '1';
                postPip(true);
              } else if (window.__mmPreferPip) {
                // Likely next-video swap — keep intent and re-enter on the new media.
                postPip(true);
                schedulePipReenter(v);
              } else {
                v.dataset.mmWantPip = '0';
                postPip(anyInPiP());
              }
            } else if (window.__mmPreferPip) {
              postPip(true);
              schedulePipReenter(null);
            } else {
              postPip(anyInPiP());
            }
            try { e.stopImmediatePropagation(); } catch (err) {
              try { e.stopPropagation(); } catch (err2) {}
            }
          }, true);

          document.addEventListener('enterpictureinpicture', function(e) {
            var v = e.target;
            window.__mmPreferPip = true;
            if (v && v.tagName === 'VIDEO') {
              v.dataset.mmWantPip = '1';
              v.dataset.mmWantPlay = '1';
            }
            postPip(true);
            try { e.stopImmediatePropagation(); } catch (err) { try { e.stopPropagation(); } catch (e2) {} }
          }, true);

          document.addEventListener('leavepictureinpicture', function(e) {
            var v = e.target;
            if (window.__mmPreferPip) {
              postPip(true);
              schedulePipReenter(v && v.tagName === 'VIDEO' ? v : null);
            } else {
              if (v && v.tagName === 'VIDEO') v.dataset.mmWantPip = '0';
              postPip(anyInPiP());
            }
          }, true);

          setInterval(markPlayingState, 800);
          setInterval(scanVideos, 1000);
          scanVideos();

          try {
            var mo = new MutationObserver(function() { scanVideos(); });
            mo.observe(document.documentElement || document, { childList: true, subtree: true });
          } catch (e) {}

          document.addEventListener('play', function(e) {
            var v = e.target;
            if (v && v.tagName === 'VIDEO') {
              bindVideo(v);
              v.dataset.mmWantPlay = '1';
              if (window.__mmPreferPip && !isInPiP(v)) {
                setTimeout(function() {
                  if (window.__mmPreferPip && !anyInPiP()) enterPiP();
                }, 120);
              }
            }
          }, true);

          document.addEventListener('ended', function(e) {
            var v = e.target;
            if (!v || v.tagName !== 'VIDEO') return;
            if (window.__mmPreferPip) schedulePipReenter(v);
          }, true);

          // YouTube SPA next / related navigation.
          document.addEventListener('yt-navigate-finish', function() {
            if (!window.__mmPreferPip) return;
            setTimeout(function() {
              if (window.__mmPreferPip && !anyInPiP()) enterPiP();
            }, 350);
          }, true);

          document.addEventListener('pause', function(e) {
            var v = e.target;
            if (!v || v.tagName !== 'VIDEO') return;
            if (isInPiP(v) || v.dataset.mmWantPip === '1' || wantsPip()) {
              // YouTube often pauses on foreground/background transitions — keep PiP alive.
              setTimeout(keepPipPlaying, 0);
              setTimeout(keepPipPlaying, 120);
              return;
            }
            if (document.visibilityState === 'visible') {
              v.dataset.mmWantPlay = '0';
              return;
            }
            setTimeout(function() {
              if (wantsPip() || isInPiP(v)) {
                keepPipPlaying();
                return;
              }
              if (v.dataset.mmWantPlay === '1' && v.paused && !v.ended) {
                var p = v.play();
                if (p && p.catch) p.catch(function(){});
              }
            }, 0);
          }, true);

          document.addEventListener('visibilitychange', function(e) {
            if (wantsPip()) {
              // YouTube pauses / exits PiP on visibility — swallow and keep playing.
              try { e.stopImmediatePropagation(); } catch (err) { try { e.stopPropagation(); } catch (e2) {} }
              postPip(true);
              keepPipPlaying();
              setTimeout(keepPipPlaying, 80);
              setTimeout(keepPipPlaying, 350);
              return;
            }
            if (document.visibilityState === 'visible') {
              resumeVideos();
            } else {
              markPlayingState();
              resumeVideos();
              setTimeout(resumeVideos, 80);
              setTimeout(resumeVideos, 350);
            }
          }, true);

          // pagehide / pageshow are also used by some players when the app backgrounds.
          window.addEventListener('pagehide', function(e) {
            if (!wantsPip()) return;
            try { e.stopImmediatePropagation(); } catch (err) {}
            keepPipPlaying();
          }, true);
          window.addEventListener('pageshow', function(e) {
            if (!wantsPip()) return;
            try { e.stopImmediatePropagation(); } catch (err) {}
            postPip(true);
            keepPipPlaying();
          }, true);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
