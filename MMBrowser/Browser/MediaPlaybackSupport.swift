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
            configuration.userContentController.addUserScript(backgroundKeepAliveScript)
        }
    }

    /// Soft keep-alive: re-play media when page becomes visible again after background.
    private static var backgroundKeepAliveScript: WKUserScript {
        let source = """
        (function() {
          if (window.__mmMediaKeepAlive) return;
          window.__mmMediaKeepAlive = true;
          document.addEventListener('visibilitychange', function() {
            if (document.visibilityState !== 'visible') return;
            try {
              var videos = document.querySelectorAll('video');
              for (var i = 0; i < videos.length; i++) {
                var v = videos[i];
                if (v.paused && !v.ended && v.currentTime > 0) {
                  var p = v.play();
                  if (p && p.catch) p.catch(function(){});
                }
              }
            } catch (e) {}
          });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
