import AVFoundation
import WebKit

/// Background audio + Picture-in-Picture helpers for cleaner video browsing.
enum MediaPlaybackSupport {
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
        if AppSettings.backgroundAudioEnabled {
            configuration.userContentController.addUserScript(keepAliveScript)
        }
    }

    /// Call after in-app UI or snapshot work that may interrupt HTML5 video.
    static func resumeMediaIfNeeded(in webView: WKWebView?) {
        guard let webView else { return }
        webView.evaluateJavaScript(resumeJS, completionHandler: nil)
    }

    private static let resumeJS = """
    (function() {
      try {
        if (typeof window.__mmResumeMedia === 'function') { window.__mmResumeMedia(); return; }
        document.querySelectorAll('video').forEach(function(v) {
          if (v.paused && !v.ended && v.currentTime > 0) {
            var p = v.play();
            if (p && p.catch) p.catch(function(){});
          }
        });
      } catch (e) {}
    })();
    """

    /// Soft keep-alive when the page is hidden by in-app UI, and when returning visible.
    private static var keepAliveScript: WKUserScript {
        let source = """
        (function() {
          if (window.__mmMediaKeepAlive) return;
          window.__mmMediaKeepAlive = true;

          function markPlayingState() {
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (!v.paused && !v.ended) v.dataset.mmWantPlay = '1';
              });
            } catch (e) {}
          }

          function resumeVideos() {
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (v.dataset.mmWantPlay !== '1') return;
                if (v.paused && !v.ended) {
                  var p = v.play();
                  if (p && p.catch) p.catch(function(){});
                }
              });
            } catch (e) {}
          }

          window.__mmResumeMedia = function() {
            markPlayingState();
            // Force-resume recently playing media after native interruptions (snapshot / overlays).
            try {
              document.querySelectorAll('video').forEach(function(v) {
                if (v.ended) return;
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

          setInterval(markPlayingState, 800);

          document.addEventListener('play', function(e) {
            var v = e.target;
            if (v && v.tagName === 'VIDEO') v.dataset.mmWantPlay = '1';
          }, true);

          document.addEventListener('pause', function(e) {
            var v = e.target;
            if (!v || v.tagName !== 'VIDEO') return;
            if (document.visibilityState === 'visible') {
              // Likely user/site pause — stop keep-alive for this element.
              v.dataset.mmWantPlay = '0';
              return;
            }
            // Hidden by overlay / background: try to keep playback going.
            setTimeout(function() {
              if (v.dataset.mmWantPlay === '1' && v.paused && !v.ended) {
                var p = v.play();
                if (p && p.catch) p.catch(function(){});
              }
            }, 0);
          }, true);

          document.addEventListener('visibilitychange', function() {
            if (document.visibilityState === 'visible') {
              resumeVideos();
            } else {
              markPlayingState();
              resumeVideos();
              setTimeout(resumeVideos, 80);
              setTimeout(resumeVideos, 350);
            }
          }, true);
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
