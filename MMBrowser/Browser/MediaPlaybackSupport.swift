import AVFoundation
import UIKit
import WebKit

/// Background audio + Picture-in-Picture helpers for cleaner video browsing.
enum MediaPlaybackSupport {
    static let pipHandlerName = "mmMediaPip"

    static func configureAudioSessionIfNeeded() {
        guard AppSettings.backgroundAudioEnabled || AppSettings.pictureInPictureEnabled else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // Avoid `.allowAirPlay` here — with `.playback` + `.default` it can return OSStatus -50.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            // Retry without mode if the first combination is rejected on some iOS builds.
            do {
                try session.setCategory(.playback)
                try session.setActive(true)
            } catch {
                print("[MediaPlayback] audio session: \(error.localizedDescription)")
            }
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
            configuration.userContentController.addUserScript(makeMediaScript())
        }
    }

    /// Re-assert playback after the app backgrounds (YouTube Music pauses on visibilitychange).
    static func keepBackgroundMediaAlive(in webView: WKWebView?) {
        guard let webView else { return }
        guard AppSettings.backgroundAudioEnabled || AppSettings.stickyPictureInPicture else { return }
        configureAudioSessionIfNeeded()
        webView.evaluateJavaScript(keepBackgroundAliveJS, completionHandler: nil)
        // YTM often pauses again a beat after the first resume — kick a few more times.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            webView.evaluateJavaScript(keepBackgroundAliveJS, completionHandler: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            webView.evaluateJavaScript(keepBackgroundAliveJS, completionHandler: nil)
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

    /// Enter PiP for the best matching video (menu / native floating button).
    static func enterPictureInPicture(in webView: WKWebView?, completion: ((Bool) -> Void)? = nil) {
        guard let webView, AppSettings.pictureInPictureEnabled else {
            PipProbe.log("enter.native.skip", [
                "reason": webView == nil ? "nilWebView" : "pipDisabled",
                "sticky": AppSettings.stickyPictureInPicture
            ])
            completion?(false)
            return
        }
        let host = webView.url?.host ?? "?"
        PipProbe.log("enter.native.begin", [
            "host": host,
            "sticky": AppSettings.stickyPictureInPicture,
            "isMusic": YouTubeDarkMode.isYouTubeMusic(webView.url)
        ])
        PipProbe.requestTabDump(reason: "enter.native.begin")
        webView.evaluateJavaScript(enterPipJS) { result, error in
            let ok = (result as? Bool) ?? false
            PipProbe.log("enter.native.done", [
                "host": host,
                "ok": ok,
                "error": error?.localizedDescription ?? "",
                "sticky": AppSettings.stickyPictureInPicture
            ])
            completion?(ok)
        }
    }

    /// Snapshot page PiP state into console (async).
    static func probePageState(in webView: WKWebView?, reason: String) {
        guard PipProbe.isEnabled, let webView else { return }
        webView.evaluateJavaScript(pageProbeJS) { result, error in
            if let error {
                PipProbe.log("page.probe.error", ["reason": reason, "error": error.localizedDescription])
                return
            }
            if let dict = result as? [String: Any] {
                PipProbe.log("page.probe", ["reason": reason].merging(dict) { _, new in new })
            } else {
                PipProbe.log("page.probe.raw", ["reason": reason, "result": "\(result ?? "nil")"])
            }
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

    /// Clear sticky intent and exit system PiP (used when another tab takes audio focus).
    static func releasePictureInPicture(in webView: WKWebView?) {
        guard let webView else { return }
        webView.evaluateJavaScript(releasePipJS, completionHandler: nil)
    }

    private static let releasePipJS = """
    (function() {
      try {
        // Block reclaim while system PiP teardown is still in flight.
        window.__mmPipSuppressed = true;
        window.__mmPreferPip = false;
        if (typeof window.__mmClearPreferPip === 'function') window.__mmClearPreferPip();
        document.querySelectorAll('video').forEach(function(v) {
          try { v.dataset.mmWantPip = '0'; } catch (e) {}
          try { v.dataset.mmWantPlay = '0'; } catch (e) {}
          try {
            if (v.webkitPresentationMode === 'picture-in-picture') {
              var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
              if (raw) raw.call(v, 'inline');
              else if (v.webkitSetPresentationMode) v.webkitSetPresentationMode('inline');
            }
          } catch (e) {}
          try {
            if (document.pictureInPictureElement === v && document.exitPictureInPicture) {
              document.exitPictureInPicture();
            }
          } catch (e) {}
          try {
            if (!v.paused && !v.ended) v.pause();
          } catch (e) {}
        });
        // Keep suppress long enough that scan/presentation churn cannot re-claim audio.
        setTimeout(function() {
          try {
            if (typeof window.__mmAnyInPiP === 'function' && window.__mmAnyInPiP()) {
              document.querySelectorAll('video').forEach(function(v) {
                try {
                  var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
                  if (raw && v.webkitPresentationMode === 'picture-in-picture') raw.call(v, 'inline');
                } catch (e) {}
              });
            }
          } catch (e) {}
        }, 200);
        setTimeout(function() { window.__mmPipSuppressed = false; }, 2500);
      } catch (e) {}
    })();
    """

    private static let enterPipJS = """
    (function() {
      try {
        window.__mmPipSuppressed = false;
        if (typeof window.__mmEnterPiP === 'function') return !!window.__mmEnterPiP('native');
        return false;
      } catch (e) { return false; }
    })();
    """

    private static let pageProbeJS = """
    (function() {
      try {
        var vids = (typeof window.__mmPipVideoSnapshot === 'function')
          ? window.__mmPipVideoSnapshot()
          : [];
        return {
          host: location.hostname || '',
          path: (location.pathname || '').slice(0, 80),
          prefer: !!window.__mmPreferPip,
          inPip: !!(window.__mmAnyInPiP && window.__mmAnyInPiP()),
          keepAlive: !!window.__mmMediaKeepAlive,
          bgAudio: !!window.__mmBackgroundAudio,
          videoCount: vids.length,
          videos: vids
        };
      } catch (e) {
        return { error: String(e) };
      }
    })();
    """

    private static let reinforcePipJS = """
    (function() {
      try {
        var prefer = !!window.__mmPreferPip;
        var inPip = (typeof window.__mmAnyInPiP === 'function') && window.__mmAnyInPiP();
        if (!prefer && !inPip) return;
        // After a manual PiP close, page script clears prefer shortly — do not force re-enter.
        if (!inPip && typeof window.__mmTryReenterOrClear === 'function') {
          window.__mmTryReenterOrClear('reinforce');
          return;
        }
        if (!prefer) return;
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

    private static let keepBackgroundAliveJS = """
    (function() {
      try {
        window.__mmBackgroundAudio = true;
        if (window.__mmPreferPip) {
          document.querySelectorAll('video').forEach(function(v) {
            try {
              v.dataset.mmWantPlay = '1';
              if (!v.ended && v.paused) {
                var p = v.play();
                if (p && p.catch) p.catch(function(){});
              }
            } catch (e) {}
          });
        }
        if (typeof window.__mmKeepBackgroundMedia === 'function') {
          window.__mmKeepBackgroundMedia();
          return;
        }
        document.querySelectorAll('video').forEach(function(v) {
          if (v.ended) return;
          if (!v.paused || v.dataset.mmWantPlay === '1' || v.currentTime > 0.05) {
            v.dataset.mmWantPlay = '1';
            if (v.paused) {
              var p = v.play();
              if (p && p.catch) p.catch(function(){});
            }
          }
        });
      } catch (e) {}
    })();
    """

    /// Soft keep-alive + PiP state bridge.
    /// YouTube listens for `webkitpresentationmodechanged` / `visibilitychange` and forces
    /// inline playback (Premium upsell). We capture those events first, notify native, then
    /// stop propagation so the site cannot dismiss system PiP when the app returns.
    private static func makeMediaScript() -> WKUserScript {
        let bgFlag = AppSettings.backgroundAudioEnabled ? "true" : "false"
        let source = """
        (function() {
          if (window.__mmMediaKeepAlive) return;
          window.__mmMediaKeepAlive = true;
          window.__mmBackgroundAudio = \(bgFlag);

          // Sticky user/system intent to stay in PiP across YouTube "next video" swaps.
          if (typeof window.__mmPreferPip === 'undefined') window.__mmPreferPip = false;
          var reenterToken = 0;
          // Snapshot taken on PiP leave — used to tell "user closed PiP" from "next video swap".
          var pipLeftAt = 0;
          var pipLeftVideo = null;
          var pipLeftSrc = '';
          var pipLeftTime = 0;

          var lastPostedActive = null;
          var lastPostedPrefer = null;
          if (typeof window.__mmPipSuppressed === 'undefined') window.__mmPipSuppressed = false;

          function postPip(active) {
            try {
              // Never claim active unless the page is actually in system PiP.
              // False active:true made every sticky tab fight for AVAudioSession.
              if (window.__mmPipSuppressed) {
                active = false;
                window.__mmPreferPip = false;
              }
              var reallyActive = !window.__mmPipSuppressed && anyInPiP();
              var nextActive = !!active && reallyActive;
              var prefer = !!window.__mmPreferPip && !window.__mmPipSuppressed;
              if (lastPostedActive === nextActive && lastPostedPrefer === prefer) return;
              lastPostedActive = nextActive;
              lastPostedPrefer = prefer;
              if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmMediaPip) {
                webkit.messageHandlers.mmMediaPip.postMessage({
                  active: nextActive,
                  prefer: prefer
                });
              }
            } catch (e) {}
          }

          function postUserPlay() {
            try {
              if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmMediaPip) {
                webkit.messageHandlers.mmMediaPip.postMessage({ userPlay: true });
              }
            } catch (e) {}
          }

          function retryPlayAfterTakeover(v) {
            if (!v) return;
            [160, 400, 700].forEach(function(ms) {
              setTimeout(function() {
                try {
                  if (!v || v.ended) return;
                  if (!v.paused) return;
                  var p = v.play();
                  if (p && p.catch) p.catch(function(){});
                } catch (e) {}
              }, ms);
            });
          }

          function notePipLeft(v) {
            pipLeftAt = Date.now();
            pipLeftVideo = (v && v.tagName === 'VIDEO') ? v : null;
            pipLeftSrc = videoSrc(pipLeftVideo);
            try { pipLeftTime = pipLeftVideo ? (pipLeftVideo.currentTime || 0) : 0; } catch (e) { pipLeftTime = 0; }
          }

          /// Same continuous clip still playing inline shortly after leave → user closed PiP.
          function looksLikeUserDismiss() {
            if (!pipLeftAt) return false;
            var age = Date.now() - pipLeftAt;
            // Ignore sub-200ms glitches (WebKit / YouTube false leaves on foreground).
            if (age < 200 || age > 4500) return false;
            if (anyInPiP()) return false;
            var v = pickVideo();
            if (!v || v.ended) return false;
            var src = videoSrc(v);
            var t = 0;
            try { t = v.currentTime || 0; } catch (e) {}
            var sameEl = !!(pipLeftVideo && v === pipLeftVideo);
            var sameSrc = !!(src && pipLeftSrc && src === pipLeftSrc);
            // Time keeps advancing (or stays near leave point) — not a fresh track start.
            var continuous = (t + 0.35 >= pipLeftTime) && (t < pipLeftTime + 6);
            var freshStart = t < 1.2 && pipLeftTime > 2.5;
            if (freshStart) return false;
            if (isYouTubeMusic() && (Date.now() - lastTrackChangeAt) < 5000) return false;
            return (sameEl || sameSrc) && continuous;
          }

          function tryReenterOrClear(reason) {
            if (window.__mmPipSuppressed) return;
            // Music has no usable HTML PiP surface.
            if (isYouTubeMusic()) return;
            if (!window.__mmPreferPip || anyInPiP()) return;
            if (looksLikeUserDismiss()) {
              postDiag('prefer.userDismiss', { reason: String(reason || ''), video: videoProbe(pickVideo()) });
              clearPreferPip();
              return;
            }
            enterPiP(reason);
          }
          window.__mmTryReenterOrClear = tryReenterOrClear;

          function postDiag(event, extra) {
            try {
              var payload = {
                diag: true,
                event: String(event || 'event'),
                host: (location.hostname || ''),
                isMusic: isYouTubeMusic(),
                prefer: !!window.__mmPreferPip,
                inPip: anyInPiP()
              };
              if (extra && typeof extra === 'object') {
                for (var k in extra) {
                  if (Object.prototype.hasOwnProperty.call(extra, k)) payload[k] = extra[k];
                }
              }
              if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmMediaPip) {
                webkit.messageHandlers.mmMediaPip.postMessage(payload);
              }
            } catch (e) {}
          }

          function videoProbe(v) {
            if (!v) return null;
            var mode = '';
            var support = null;
            try { mode = v.webkitPresentationMode || ''; } catch (e) { mode = '?'; }
            try {
              support = (typeof v.webkitSupportsPresentationMode === 'function')
                ? !!v.webkitSupportsPresentationMode('picture-in-picture')
                : null;
            } catch (e) { support = null; }
            return {
              paused: !!v.paused,
              ended: !!v.ended,
              t: Math.round((v.currentTime || 0) * 10) / 10,
              rs: v.readyState || 0,
              vw: v.videoWidth || 0,
              vh: v.videoHeight || 0,
              cw: v.clientWidth || 0,
              ch: v.clientHeight || 0,
              mode: mode,
              support: support,
              srcLen: (videoSrc(v) || '').length,
              wantPip: v.dataset ? v.dataset.mmWantPip : '',
              wantPlay: v.dataset ? v.dataset.mmWantPlay : ''
            };
          }
          window.__mmPipVideoSnapshot = function() {
            try {
              return collectVideos(document, []).slice(0, 6).map(videoProbe);
            } catch (e) { return []; }
          };

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

          function isYouTubeMusic() {
            try {
              var h = (location.hostname || '').toLowerCase();
              return h === 'music.youtube.com' || h.indexOf('music.youtube.com') !== -1;
            } catch (e) { return false; }
          }

          /// Keep media alive across app background (YTM pauses on visibilitychange).
          function wantsKeepAlive() {
            try {
              if (!window.__mmBackgroundAudio) return false;
              if (isYouTubeMusic()) return true;
              return !!document.querySelector('video[data-mm-want-play="1"]');
            } catch (e) { return false; }
          }

          /// Skip forced play while the element is still buffering — otherwise pause
          /// handlers fight WebKit/YouTube stalls and audio stutters (play↔pause loop).
          function canForcePlay(v) {
            try {
              if (!v || v.ended) return false;
              // HAVE_CURRENT_DATA (2): enough to decode a frame; below that play() often fails/stalls.
              if ((v.readyState || 0) < 2) return false;
            } catch (e) { return false; }
            return true;
          }

          function isLikelyBufferingPause(v) {
            try {
              // Only suppress while the page is foreground and not already in system PiP.
              // Background / real PiP still need aggressive resume (YTM visibility pauses).
              if (document.visibilityState !== 'visible') return false;
              if (isInPiP(v)) return false;
              var rs = v.readyState || 0;
              // HAVE_FUTURE_DATA (3)+ usually means a deliberate pause, not a stall.
              if (rs < 3) return true;
              if (v.networkState === 2) return true; // NETWORK_LOADING
            } catch (e) {}
            return false;
          }

          function forceResumePlaying() {
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (v.ended) return;
                if (v.dataset.mmWantPlay !== '1' && v.paused && v.currentTime < 0.05) return;
                v.dataset.mmWantPlay = '1';
                if (v.paused && canForcePlay(v)) {
                  var p = v.play();
                  if (p && p.catch) p.catch(function(){});
                }
              });
            } catch (e) {}
          }
          window.__mmKeepBackgroundMedia = function() {
            forceResumePlaying();
            setTimeout(forceResumePlaying, 80);
            setTimeout(forceResumePlaying, 300);
            setTimeout(forceResumePlaying, 800);
          };

          function clearPreferPip() {
            postDiag('prefer.clear', { videos: window.__mmPipVideoSnapshot ? window.__mmPipVideoSnapshot() : [] });
            window.__mmPreferPip = false;
            reenterToken += 1;
            pipLeftAt = 0;
            pipLeftVideo = null;
            pipLeftSrc = '';
            pipLeftTime = 0;
            lastPostedActive = null;
            lastPostedPrefer = null;
            try {
              document.querySelectorAll('video').forEach(function(v) {
                try { v.dataset.mmWantPip = '0'; } catch (e) {}
              });
            } catch (e) {}
            postPip(false);
          }
          window.__mmClearPreferPip = clearPreferPip;

          function videoSrc(v) {
            try { return (v && (v.currentSrc || v.src)) || ''; } catch (e) { return ''; }
          }

          // YouTube Music reuses the same <video> / MSE blob URL across songs (URL bar unchanged).
          var mediaEpoch = 0;
          var lastTrackChangeAt = 0;

          function noteTrackChange(reason) {
            mediaEpoch += 1;
            lastTrackChangeAt = Date.now();
            postDiag('track.change', { reason: String(reason || ''), epoch: mediaEpoch, title: ytMusicPlayerTitle() });
            // Music: no PiP — only clear ghost HTML presentation mode.
            if (isYouTubeMusic()) {
              exitInvisibleMusicHtmlPip();
              return;
            }
            if (window.__mmPipSuppressed || !window.__mmPreferPip) return;
            var v = pickVideo();
            if (anyInPiP()) {
              // Same PiP session can go stale after an in-page song swap — re-assert.
              postDiag('track.reassert', { reason: String(reason || '') });
              if (v) requestPiPOnVideo(v);
              postPip(true);
              return;
            }
            // loadstart/emptied during the first buffer are not a "next track" — defer
            // sticky re-enter until the element can actually play without thrashing.
            if (v && isLikelyBufferingPause(v)) {
              postDiag('track.defer', { reason: String(reason || ''), video: videoProbe(v) });
              return;
            }
            postDiag('track.reenter', { reason: String(reason || '') });
            schedulePipReenter(v);
            setTimeout(function() {
              if (window.__mmPreferPip && !anyInPiP()) enterPiP('track:' + reason);
            }, 150);
          }

          function ytMusicPlayerTitle() {
            try {
              var el = document.querySelector(
                'ytmusic-player-bar .title, .ytmusic-player-bar .title, .title.style-scope.ytmusic-player-bar'
              );
              return el ? String(el.textContent || '').trim() : '';
            } catch (e) { return ''; }
          }

          /// After PiP drops (next video / element swap), re-enter unless the user dismissed.
          function schedulePipReenter(previousVideo) {
            if (!window.__mmPreferPip || isYouTubeMusic()) return;
            var token = ++reenterToken;
            var prevSrc = videoSrc(previousVideo);
            var delays = [120, 280, 550, 1000, 1800];
            delays.forEach(function(ms, idx) {
              setTimeout(function() {
                if (token !== reenterToken || !window.__mmPreferPip) return;
                if (anyInPiP()) {
                  postPip(true);
                  return;
                }
                // User closed the PiP window while the same clip kept playing.
                if (looksLikeUserDismiss()) {
                  postDiag('prefer.userDismiss', { reason: 'reenterTick', idx: idx });
                  clearPreferPip();
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
                  // Same clip still inline → user closed PiP (wait one tick for false leaves).
                  if (idx >= 1) clearPreferPip();
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
            if (wantsPip()) {
              keepPipPlaying();
              return;
            }
            if (wantsKeepAlive() && document.visibilityState === 'hidden') {
              forceResumePlaying();
              return;
            }
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
              if (window.__mmPipSuppressed || isYouTubeMusic()) return;
              if (window.__mmPreferPip && !anyInPiP()) {
                if (looksLikeUserDismiss()) {
                  clearPreferPip();
                  return;
                }
                // Do not schedule re-enter / play kicks during initial buffer stalls.
                var candidate = pickVideo();
                if (candidate && isLikelyBufferingPause(candidate)) return;
                schedulePipReenter(candidate);
              }
              document.querySelectorAll('video').forEach(function(v) {
                if (!window.__mmPreferPip && v.dataset.mmWantPip !== '1' && !isInPiP(v)) return;
                if (window.__mmPreferPip || isInPiP(v)) v.dataset.mmWantPip = '1';
                if (v.paused && !v.ended && canForcePlay(v) && !isLikelyBufferingPause(v)) {
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
                  if (v.paused && canForcePlay(v) && !isLikelyBufferingPause(v)) {
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

          function collectVideos(root, out) {
            if (!root) return out;
            try {
              root.querySelectorAll('video').forEach(function(v) { out.push(v); });
            } catch (e) {}
            try {
              var all = root.querySelectorAll('*');
              for (var i = 0; i < all.length; i++) {
                var sr = all[i].shadowRoot;
                if (sr) collectVideos(sr, out);
              }
            } catch (e) {}
            return out;
          }

          function pickVideo() {
            var vids = collectVideos(document, []);
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

          function videoHasVisibleSize(v) {
            if (!v) return false;
            try {
              var vw = v.videoWidth || 0;
              var vh = v.videoHeight || 0;
              var cw = v.clientWidth || 0;
              var ch = v.clientHeight || 0;
              return (vw >= 16 && vh >= 16) || (cw >= 16 && ch >= 16);
            } catch (e) { return false; }
          }

          /// YTM HTML <video> is often 0×0 — webkit PiP can latch with no window. Exit it.
          function exitInvisibleMusicHtmlPip() {
            if (!isYouTubeMusic()) return false;
            var exited = false;
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (!isInPiP(v) || videoHasVisibleSize(v)) return;
                try {
                  var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
                  if (raw) raw.call(v, 'inline');
                  else if (v.webkitSetPresentationMode) v.webkitSetPresentationMode('inline');
                  exited = true;
                } catch (e) {}
                try { v.dataset.mmWantPip = '0'; } catch (e) {}
              });
            } catch (e) {}
            if (exited) {
              postDiag('music.exitInvisibleHtmlPip', {});
              clearPreferPip();
            }
            return exited;
          }

          function prepareVideoForPiP(v) {
            if (!v) return;
            unlockVideo(v);
            bindVideo(v);
            v.dataset.mmWantPip = '1';
            v.dataset.mmWantPlay = '1';
            try {
              v.setAttribute('playsinline', '');
              v.setAttribute('webkit-playsinline', '');
              v.playsInline = true;
            } catch (e) {}
          }

          /// Must stay synchronous when called from a tap — awaiting play() drops the user-gesture token.
          function requestPiPOnVideo(v) {
            if (!v) {
              postDiag('request.fail', { why: 'nilVideo' });
              return false;
            }
            prepareVideoForPiP(v);
            var support = null;
            try {
              if (typeof v.webkitSupportsPresentationMode === 'function') {
                support = !!v.webkitSupportsPresentationMode('picture-in-picture');
              }
            } catch (e) {}
            var path = '';
            var err = '';
            try {
              var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
              if (raw) {
                raw.call(v, 'picture-in-picture');
                path = 'rawSetPresentationMode';
              }
            } catch (e) { err = String(e); }
            if (!path) {
              try {
                if (typeof v.webkitSetPresentationMode === 'function') {
                  v.webkitSetPresentationMode('picture-in-picture');
                  path = 'webkitSetPresentationMode';
                }
              } catch (e) { err = String(e); }
            }
            if (!path) {
              try {
                if (v.requestPictureInPicture) {
                  var req = v.requestPictureInPicture();
                  if (req && req.catch) req.catch(function(e2) {
                    postDiag('request.pipApi.reject', { error: String(e2) });
                  });
                  path = 'requestPictureInPicture';
                }
              } catch (e) { err = String(e); }
            }
            var modeAfter = '';
            try { modeAfter = v.webkitPresentationMode || ''; } catch (e) { modeAfter = '?'; }
            postDiag('request.pip', {
              path: path || 'none',
              support: support,
              modeAfter: modeAfter,
              inPip: anyInPiP(),
              error: err,
              video: videoProbe(v)
            });
            return !!path;
          }

          function enterPiP(reason) {
            var why = reason || 'direct';
            if (window.__mmPipSuppressed) {
              postDiag('enter.fail', { reason: why, why: 'suppressed' });
              return false;
            }
            // YTM has no usable HTML video / PiP surface.
            if (isYouTubeMusic()) {
              exitInvisibleMusicHtmlPip();
              return false;
            }
            var v = pickVideo();
            if (!v) {
              postDiag('enter.fail', { reason: why, why: 'noVideo', videoCount: collectVideos(document, []).length });
              return false;
            }
            window.__mmPreferPip = true;
            // Kick play without awaiting — keeps tap gesture valid for PiP below.
            try {
              if (v.paused) {
                var p = v.play();
                if (p && p.catch) p.catch(function(){});
              }
            } catch (e) {}

            prepareVideoForPiP(v);
            try { void v.offsetWidth; } catch (e) {}

            var claimed = requestPiPOnVideo(v);
            var inPipNow = anyInPiP();
            postDiag('enter.attempt', {
              reason: why,
              claimed: claimed,
              inPipNow: inPipNow,
              video: videoProbe(v)
            });
            postPip(true);
            setTimeout(function() {
              var still = anyInPiP();
              if (!still && window.__mmPreferPip) {
                postDiag('enter.retry', { reason: why });
                prepareVideoForPiP(pickVideo() || v);
                requestPiPOnVideo(pickVideo() || v);
              }
              setTimeout(function() {
                postDiag('enter.result', {
                  reason: why,
                  inPip: anyInPiP(),
                  prefer: !!window.__mmPreferPip,
                  video: videoProbe(pickVideo())
                });
              }, 280);
            }, 200);
            return inPipNow || claimed;
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

          function removeLegacyPipChip() {
            try {
              var btn = document.getElementById('mm-pip-chip');
              if (btn) btn.remove();
            } catch (e) {}
          }

          function scanVideos() {
            try {
              collectVideos(document, []).forEach(bindVideo);
              removeLegacyPipChip();
              // Music: no PiP — exit ghost HTML presentation mode if any.
              if (isYouTubeMusic()) {
                exitInvisibleMusicHtmlPip();
              }
              if (window.__mmPipSuppressed) {
                if (anyInPiP()) postPip(false);
              } else if (anyInPiP()) {
                postPip(true);
              }
              postVideoReady();
            } catch (e) {}
          }

          // YTM / MSE: track changes rarely navigate; watch media lifecycle + player title.
          ['emptied', 'loadstart', 'loadedmetadata', 'loadeddata', 'durationchange'].forEach(function(type) {
            document.addEventListener(type, function(e) {
              var v = e.target;
              if (!v || v.tagName !== 'VIDEO') return;
              noteTrackChange(type);
            }, true);
          });

          document.addEventListener('playing', function(e) {
            var v = e.target;
            if (!v || v.tagName !== 'VIDEO') return;
            if (isYouTubeMusic()) {
              exitInvisibleMusicHtmlPip();
              return;
            }
            if (!window.__mmPreferPip) return;
            if (anyInPiP()) return;
            // New decode pipeline after song tap — restore PiP (not after user closed PiP).
            setTimeout(function() { tryReenterOrClear('playing:80'); }, 80);
            setTimeout(function() { tryReenterOrClear('playing:400'); }, 400);
          }, true);

          // Capture at document BEFORE YouTube's listeners. Stopping propagation is what
          // unlocks PiP on YouTube and stops it from dismissing PiP when the app returns.
          document.addEventListener('webkitpresentationmodechanged', function(e) {
            var v = e.target;
            if (v && v.tagName === 'VIDEO') {
              unlockVideo(v);
              if (isInPiP(v)) {
                // Music 0×0 / invisible video: HTML PiP has no window — force inline.
                if (isYouTubeMusic() && !videoHasVisibleSize(v)) {
                  exitInvisibleMusicHtmlPip();
                  try { e.stopImmediatePropagation(); } catch (err) {
                    try { e.stopPropagation(); } catch (err2) {}
                  }
                  return;
                }
                if (window.__mmPipSuppressed) {
                  // Another tab took audio — finish tearing down instead of reclaiming.
                  try {
                    var raw = HTMLVideoElement.prototype.__mmSetPresentationMode;
                    if (raw) raw.call(v, 'inline');
                  } catch (err) {}
                  postPip(false);
                } else {
                  pipLeftAt = 0;
                  window.__mmPreferPip = true;
                  v.dataset.mmWantPip = '1';
                  v.dataset.mmWantPlay = '1';
                  postPip(true);
                }
              } else if (window.__mmPreferPip && !window.__mmPipSuppressed) {
                // Left PiP — may be next-video swap or user closing the PiP window.
                notePipLeft(v);
                postDiag('presentation.leave', { keepPrefer: true, video: videoProbe(v) });
                // Report inactive immediately so native does not reinforce a closed PiP.
                postPip(false);
                schedulePipReenter(v);
              } else {
                postDiag('presentation.leave', { keepPrefer: false, video: videoProbe(v) });
                v.dataset.mmWantPip = '0';
                postPip(anyInPiP());
              }
            } else if (window.__mmPreferPip) {
              notePipLeft(null);
              postPip(false);
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
            if (window.__mmPipSuppressed) {
              try {
                if (document.exitPictureInPicture) document.exitPictureInPicture();
              } catch (err) {}
              postPip(false);
              try { e.stopImmediatePropagation(); } catch (err2) { try { e.stopPropagation(); } catch (e3) {} }
              return;
            }
            pipLeftAt = 0;
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
              notePipLeft(v && v.tagName === 'VIDEO' ? v : null);
              // Must not post active:true — that made native re-enter after a manual close.
              postPip(false);
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
              if (isYouTubeMusic()) {
                exitInvisibleMusicHtmlPip();
              }
              // Trusted = user gesture. Lets native release PiP on another tab so audio can start.
              if (e.isTrusted && document.visibilityState === 'visible') {
                postUserPlay();
                // First tap often loses the AVAudioSession race while the other tab exits PiP.
                retryPlayAfterTakeover(v);
              }
              // Music has no PiP reenter path.
              if (isYouTubeMusic()) return;
              if (window.__mmPreferPip && !isInPiP(v)) {
                // Song taps on YTM often only fire play (no navigation).
                setTimeout(function() { tryReenterOrClear('play:60'); }, 60);
                setTimeout(function() { tryReenterOrClear('play:300'); }, 300);
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
            setTimeout(function() { tryReenterOrClear('yt-navigate-finish'); }, 350);
          }, true);

          document.addEventListener('pause', function(e) {
            var v = e.target;
            if (!v || v.tagName !== 'VIDEO') return;
            if (window.__mmPipSuppressed) return;
            // Initial load / stall: WebKit pauses while readyState is low. Forcing play()
            // here (especially with sticky PiP prefer) causes audible play↔pause thrashing.
            if (isLikelyBufferingPause(v)) return;
            if (isInPiP(v) || v.dataset.mmWantPip === '1' || wantsPip()) {
              // YouTube often pauses on foreground/background transitions — keep PiP alive.
              setTimeout(keepPipPlaying, 0);
              setTimeout(keepPipPlaying, 120);
              return;
            }
            // Only auto-resume when the page is already hidden (app background / lock).
            // While visible, allow the user to pause normally.
            if (document.visibilityState === 'hidden' && (wantsKeepAlive() || v.dataset.mmWantPlay === '1')) {
              setTimeout(forceResumePlaying, 0);
              setTimeout(forceResumePlaying, 120);
              setTimeout(forceResumePlaying, 400);
              return;
            }
            if (document.visibilityState === 'visible') {
              v.dataset.mmWantPlay = '0';
            }
          }, true);

          document.addEventListener('visibilitychange', function(e) {
            var keep = wantsPip() || wantsKeepAlive();
            if (keep && document.visibilityState === 'hidden') {
              // YouTube Music pauses on visibility — swallow and keep playing.
              try { e.stopImmediatePropagation(); } catch (err) { try { e.stopPropagation(); } catch (e2) {} }
              if (anyInPiP()) postPip(true);
              markPlayingState();
              forceResumePlaying();
              keepPipPlaying();
              setTimeout(forceResumePlaying, 80);
              setTimeout(forceResumePlaying, 350);
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
            if (!wantsPip() && !wantsKeepAlive()) return;
            try { e.stopImmediatePropagation(); } catch (err) {}
            markPlayingState();
            forceResumePlaying();
            keepPipPlaying();
          }, true);
          window.addEventListener('pageshow', function(e) {
            if (!wantsPip() && !wantsKeepAlive()) return;
            try { e.stopImmediatePropagation(); } catch (err) {}
            if (anyInPiP()) postPip(true);
            forceResumePlaying();
            keepPipPlaying();
          }, true);

          document.addEventListener('freeze', function() {
            if (!wantsKeepAlive() && !wantsPip()) return;
            forceResumePlaying();
          }, true);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
