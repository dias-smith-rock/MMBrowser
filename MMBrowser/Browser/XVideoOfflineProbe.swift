import Foundation
import WebKit

struct XVideoOfflineCandidate: Equatable {
    let url: URL
    let mimeType: String?
    let statusID: String?
    let pageURL: String?
    let isHLS: Bool
    let rank: Int
    let discoveredAt: Date

    var suggestedFileName: String {
        // Compact stamp so sanitize truncation never eats ".mp4".
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: discoveredAt)
        if let statusID, !statusID.isEmpty {
            return "x-\(statusID)-\(stamp).mp4"
        }
        return "x-video-\(stamp).mp4"
    }
}

/// Discovers downloadable X/Twitter video URLs via JS playback signals + resource timing / network hints.
final class XVideoOfflineProbe {
    static let handlerName = "mmXVideoOffline"

    /// Console filter: `[XVideoOffline]`. On in DEBUG; release via `defaults write … debug.xvideo.offline 1`.
    static var isLoggingEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "debug.xvideo.offline")
        #endif
    }

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        guard isLoggingEnabled else { return }
        var parts: [String] = ["[XVideoOffline]", event]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            parts.append("\(key)=\(stringify(value))")
        }
        print(parts.joined(separator: " "))
    }

    static func fileProbeSummary(at url: URL) -> [String: Any] {
        var fields: [String: Any] = [
            "path": url.lastPathComponent,
            "exists": FileManager.default.fileExists(atPath: url.path)
        ]
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.int64Value else {
            fields["size"] = -1
            return fields
        }
        fields["size"] = size
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let prefix = handle.readData(ofLength: 32)
            fields["headHex"] = prefix.map { String(format: "%02x", $0) }.joined()
            if prefix.count >= 8 {
                let ftyp = prefix.subdata(in: 4..<8)
                fields["ftyp"] = String(data: ftyp, encoding: .ascii) ?? "?"
            }
            if let text = String(data: prefix.prefix(24), encoding: .utf8) {
                let cleaned = text.replacingOccurrences(of: "\n", with: " ")
                fields["headText"] = String(cleaned.prefix(24))
            }
        }
        return fields
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let s as String:
            if s.count > 160 { return String(s.prefix(140)) + "…(\(s.count))" }
            return s
        case let u as URL:
            return stringify(u.absoluteString)
        case let b as Bool:
            return b ? "1" : "0"
        case let n as NSNumber:
            return n.stringValue
        case let a as [Any]:
            return "[\(a.count)]"
        case let d as [String: Any]:
            return "{\(d.count)}"
        default:
            return String(describing: value)
        }
    }

    private(set) var isArmed = false
    private(set) var statusID: String?
    private(set) var pageURL: String?
    private var candidates: [XVideoOfflineCandidate] = []
    private var offeredKeys = Set<String>()
    private var lastOfferAt: Date?

    var bestCandidate: XVideoOfflineCandidate? {
        bestProgressiveCandidate ?? bestHLSCandidate
            ?? candidates.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }.first
    }

    /// True progressive MP4 only — modern X `/vid/avc1/` URLs are CMAF init segments (~1KB), not full files.
    var bestProgressiveCandidate: XVideoOfflineCandidate? {
        candidates
            .filter { !$0.isHLS && !Self.isCMAFFragmentURL($0.url) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }
            .first
    }

    /// Prefer master playlists (`/pl/<id>.m3u8`) over audio/video variant playlists.
    var bestHLSCandidate: XVideoOfflineCandidate? {
        candidates
            .filter { $0.isHLS }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }
            .first
    }

    /// Modern X CDN objects that look like `.mp4` but are CMAF init / media fragments.
    static func isCMAFFragmentURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/vid/avc1/") || path.contains("/aud/mp4a/") { return true }
        if path.contains("/aud/") && path.hasSuffix(".mp4") { return true }
        return false
    }

    func reset() {
        isArmed = false
        statusID = nil
        pageURL = nil
        candidates.removeAll()
        // Keep offeredKeys for the tab session so we don't re-prompt the same media.
    }

    func clearSessionOffers() {
        offeredKeys.removeAll()
        lastOfferAt = nil
    }

    static func isXPage(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "x.com"
            || host.hasSuffix(".x.com")
            || host == "twitter.com"
            || host.hasSuffix(".twitter.com")
    }

    static func isMediaHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host.contains("twimg.com")
            || host.contains("video.twimg.com")
            || host.contains("pscp.tv")
            || host.contains("periscope.tv")
    }

    static func isLikelyMediaURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard isMediaHost(host) else { return false }
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        if ["mp4", "m3u8", "m4s", "ts"].contains(ext) { return true }
        if path.contains("/amplify_video") || path.contains("/ext_tw_video") || path.contains("/tweet_video") {
            return true
        }
        if path.contains(".mp4") || path.contains(".m3u8") { return true }
        return false
    }

    @discardableResult
    func notePlaying(pageURL: String?, statusID: String?, currentSrc: String?) -> Bool {
        isArmed = true
        if let pageURL, !pageURL.isEmpty { self.pageURL = pageURL }
        if let statusID, !statusID.isEmpty { self.statusID = statusID }
        Self.log("probe.playing", [
            "statusID": statusID ?? "",
            "page": pageURL ?? "",
            "currentSrc": currentSrc ?? "",
            "candidatesBefore": candidates.count
        ])
        if let currentSrc, let url = URL(string: currentSrc), Self.isHTTPURL(url) {
            noteMediaURL(url, mimeType: nil)
        }
        return true
    }

    @discardableResult
    func noteMediaURL(_ url: URL, mimeType: String?) -> XVideoOfflineCandidate? {
        guard Self.isHTTPURL(url) else { return nil }
        let hostOK = Self.isMediaHost(url.host) || Self.isLikelyMediaURL(url)
        let mime = (mimeType ?? "").lowercased()
        let mimeOK = mime.hasPrefix("video/") || mime.contains("mpegurl") || mime.isEmpty
        guard hostOK || mime.hasPrefix("video/") || mime.contains("mpegurl") else { return nil }
        guard mimeOK || Self.isLikelyMediaURL(url) else { return nil }

        let isHLS = url.pathExtension.lowercased() == "m3u8"
            || mime.contains("mpegurl")
            || url.absoluteString.lowercased().contains(".m3u8")
        // Skip tiny HLS segments, CMAF fragments, and thumbs — not offline targets.
        let ext = url.pathExtension.lowercased()
        if ["m4s", "ts", "jpg", "jpeg", "png", "webp", "gif"].contains(ext) { return nil }
        if !isHLS, Self.isCMAFFragmentURL(url) {
            Self.log("probe.skipCMAF", ["url": url.absoluteString])
            return nil
        }

        let key = Self.dedupeKey(for: url)
        if let existing = candidates.firstIndex(where: { Self.dedupeKey(for: $0.url) == key }) {
            // Prefer a richer mime / higher rank replace.
            let rank = Self.rank(url: url, mimeType: mimeType, isHLS: isHLS)
            if rank >= candidates[existing].rank {
                let updated = XVideoOfflineCandidate(
                    url: url,
                    mimeType: mimeType ?? candidates[existing].mimeType,
                    statusID: statusID ?? candidates[existing].statusID,
                    pageURL: pageURL ?? candidates[existing].pageURL,
                    isHLS: isHLS,
                    rank: rank,
                    discoveredAt: Date()
                )
                candidates[existing] = updated
                return updated
            }
            return candidates[existing]
        }

        let candidate = XVideoOfflineCandidate(
            url: url,
            mimeType: mimeType,
            statusID: statusID,
            pageURL: pageURL,
            isHLS: isHLS,
            rank: Self.rank(url: url, mimeType: mimeType, isHLS: isHLS),
            discoveredAt: Date()
        )
        candidates.append(candidate)
        // Keep highest-rank entries so HLS masters aren't evicted by variant noise.
        if candidates.count > 20 {
            candidates.sort { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }
            candidates = Array(candidates.prefix(20))
        }
        Self.log("probe.candidate", [
            "hls": isHLS,
            "rank": candidate.rank,
            "mime": mimeType ?? "",
            "url": url.absoluteString,
            "total": candidates.count,
            "bestProgressive": bestProgressiveCandidate?.url.absoluteString ?? ""
        ])
        return candidate
    }

    /// Returns a candidate suitable for offering Save (progressive MP4, else HLS master).
    func candidateForOffer(allowHLS: Bool = true) -> XVideoOfflineCandidate? {
        guard isArmed else { return nil }
        guard let candidate = allowHLS ? bestCandidate : bestProgressiveCandidate else { return nil }
        if candidate.isHLS, !allowHLS { return nil }
        let key = Self.dedupeKey(for: candidate.url)
        if offeredKeys.contains(key) { return nil }
        if let lastOfferAt, Date().timeIntervalSince(lastOfferAt) < 2.5 { return nil }
        return candidate
    }

    func markOffered(_ candidate: XVideoOfflineCandidate) {
        offeredKeys.insert(Self.dedupeKey(for: candidate.url))
        lastOfferAt = Date()
        Self.log("probe.offer", [
            "hls": candidate.isHLS,
            "rank": candidate.rank,
            "file": candidate.suggestedFileName,
            "url": candidate.url.absoluteString
        ])
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        return scheme == "http" || scheme == "https"
    }

    private static func dedupeKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Drop short-lived query tokens for dedupe, keep path identity.
        components?.query = nil
        components?.fragment = nil
        return (components?.string ?? url.absoluteString).lowercased()
    }

    private static func rank(url: URL, mimeType: String?, isHLS: Bool) -> Int {
        var score = 0
        let path = url.path.lowercased()
        if isHLS {
            // Master `/pl/<token>.m3u8` beats variant `/pl/avc1|mp4a/...`.
            if path.contains("/pl/mp4a/") {
                score += 10
            } else if path.contains("/pl/avc1/") {
                score += 60
            } else if path.contains("/pl/") {
                score += 120
            } else {
                score += 40
            }
            if path.contains("1080") || path.contains("1920") { score += 20 }
            else if path.contains("720") || path.contains("1280") { score += 12 }
        } else {
            score += 100
            if path.contains("1080") || path.contains("1920") { score += 30 }
            else if path.contains("720") || path.contains("1280") { score += 20 }
            if (mimeType ?? "").lowercased().contains("mp4") { score += 10 }
            if url.pathExtension.lowercased() == "mp4" { score += 25 }
        }
        if path.contains("amplify_video") || path.contains("ext_tw_video") || path.contains("tweet_video") {
            score += 15
        }
        return score
    }

    // MARK: - JS

    static var userScript: WKUserScript {
        WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    /// Same payload as `userScript`, for late `evaluateJavaScript` when the page is already loaded.
    static var scriptSourceForEvaluation: String { scriptSource }

    private static let scriptSource = #"""
(function() {
  if (window.__mmXVideoOfflineInstalled) return;
  window.__mmXVideoOfflineInstalled = true;

  function hostOK() {
    var h = (location.hostname || '').toLowerCase();
    return h === 'x.com' || h === 'twitter.com' || h.endsWith('.x.com') || h.endsWith('.twitter.com');
  }
  if (!hostOK()) return;

  function post(payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mmXVideoOffline) {
        window.webkit.messageHandlers.mmXVideoOffline.postMessage(payload);
      }
    } catch (e) {}
  }

  function statusIDFromHref(href) {
    try {
      var m = String(href || '').match(/\/status\/(\d+)/);
      return m ? m[1] : null;
    } catch (e) { return null; }
  }

  function nearestStatusID(video) {
    var node = video;
    for (var i = 0; i < 12 && node; i++) {
      try {
        var a = node.querySelector && node.querySelector('a[href*="/status/"]');
        if (a && a.href) {
          var id = statusIDFromHref(a.href);
          if (id) return id;
        }
        if (node.tagName === 'A' && node.href) {
          var id2 = statusIDFromHref(node.href);
          if (id2) return id2;
        }
      } catch (e) {}
      node = node.parentElement;
    }
    return statusIDFromHref(location.href);
  }

  function httpSrc(video) {
    try {
      var src = video.currentSrc || video.src || '';
      if (/^https?:/i.test(src)) return src;
    } catch (e) {}
    return null;
  }

  function collectResourceCandidates() {
    var out = [];
    try {
      var entries = performance.getEntriesByType('resource') || [];
      for (var i = 0; i < entries.length; i++) {
        var name = String(entries[i].name || '');
        if (!name) continue;
        var lower = name.toLowerCase();
        if (lower.indexOf('twimg.com') === -1 && lower.indexOf('pscp.tv') === -1) continue;
        if (lower.indexOf('.mp4') !== -1 || lower.indexOf('.m3u8') !== -1
            || lower.indexOf('amplify_video') !== -1 || lower.indexOf('ext_tw_video') !== -1
            || lower.indexOf('tweet_video') !== -1) {
          out.push(name);
        }
      }
    } catch (e) {}
    return out.slice(-20);
  }

  function reportPlaying(video) {
    var resources = collectResourceCandidates();
    post({
      event: 'playing',
      pageURL: String(location.href || ''),
      statusID: nearestStatusID(video),
      currentSrc: httpSrc(video),
      width: video.videoWidth || 0,
      height: video.videoHeight || 0,
      resources: resources
    });
  }

  function bindVideo(video) {
    if (!video || video.__mmXOfflineBound) return;
    video.__mmXOfflineBound = true;
    video.addEventListener('playing', function() { reportPlaying(video); }, true);
    video.addEventListener('loadedmetadata', function() {
      if (!video.paused) reportPlaying(video);
    }, true);
  }

  function scan() {
    try {
      document.querySelectorAll('video').forEach(bindVideo);
    } catch (e) {}
  }

  scan();
  try {
    var mo = new MutationObserver(function() { scan(); });
    mo.observe(document.documentElement || document, { childList: true, subtree: true });
  } catch (e) {}

  // Periodic resource sweep while a video is playing.
  setInterval(function() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (v && !v.paused && !v.ended && v.readyState >= 2) {
          reportPlaying(v);
          break;
        }
      }
    } catch (e) {}
  }, 2500);
})();
"""#
}
