import Foundation
import WebKit

/// Copyright-sensitive hosts where offline A/V must not be saved; page text/images may still be archived.
enum OfflineMediaCopyrightPolicy {
    static func restrictsAudioVideo(on url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        if YouTubeDarkMode.isYouTubeHost(host) { return true }
        if host == "vimeo.com" || host.hasSuffix(".vimeo.com") { return true }
        return false
    }

    static let watchLaterNotice =
        "Due to copyright restrictions, only text and images can be cached — audio and video can’t be saved."

    static let saveVideoBlockedNotice =
        "Due to copyright restrictions, audio and video can’t be cached on this site."
}

struct PageMediaCandidate: Equatable {
    let url: URL
    let mimeType: String?
    let statusID: String?
    let pageURL: String?
    let isHLS: Bool
    let rank: Int
    let discoveredAt: Date

    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: discoveredAt)
        if let statusID, !statusID.isEmpty {
            return "video-\(statusID)-\(stamp).mp4"
        }
        return "video-\(stamp).mp4"
    }
}

/// Discovers downloadable page media via JS playback signals and network hints.
/// Site-agnostic: same rules for every host.
final class PageMediaProbe {
    static let handlerName = "mmPageMedia"

    /// Console filter: `[PageMedia]`. On in DEBUG; release via `defaults write … debug.pageMedia 1`.
    static var isLoggingEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "debug.pageMedia")
        #endif
    }

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        guard isLoggingEnabled else { return }
        var parts: [String] = ["[PageMedia]", event]
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
    private(set) var preferredMediaID: String?
    private(set) var pinnedPlaybackURL: URL?
    private var candidates: [PageMediaCandidate] = []
    private var offeredKeys = Set<String>()
    private var savedIdentityKeys = Set<String>()
    private var lastOfferAt: Date?

    var bestCandidate: PageMediaCandidate? {
        bestOfflineCandidate
    }

    /// Prefer the URL the player is using; otherwise prefer HLS masters over preview MP4s.
    var bestOfflineCandidate: PageMediaCandidate? {
        if let pinned = pinnedPlaybackURL, !Self.isJunkOfflineURL(pinned), !Self.isLikelyPreviewURL(pinned) {
            if let match = candidates.first(where: { Self.dedupeKey(for: $0.url) == Self.dedupeKey(for: pinned) }) {
                return match
            }
            let isHLS = pinned.pathExtension.lowercased() == "m3u8"
                || pinned.absoluteString.lowercased().contains(".m3u8")
            return PageMediaCandidate(
                url: pinned,
                mimeType: isHLS ? "application/vnd.apple.mpegurl" : "video/mp4",
                statusID: statusID,
                pageURL: pageURL,
                isHLS: isHLS,
                rank: 10_000,
                discoveredAt: Date()
            )
        }
        let progressive = bestProgressiveCandidate
        let hls = bestHLSCandidate
        // Many players expose a low-quality progressive preview while the real stream is HLS.
        if let hls {
            if progressive == nil || Self.isLikelyPreviewURL(progressive!.url) || Self.isHLSMasterURL(hls.url) {
                return hls
            }
            if hls.rank >= (progressive?.rank ?? 0) {
                return hls
            }
        }
        return progressive ?? hls
            ?? candidates.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }.first
    }

    /// Generic preview / trailer / thumb MP4 heuristics (capability-based, no site tables).
    static func isLikelyPreviewURL(_ url: URL) -> Bool {
        let full = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        if full.contains("preview") || full.contains("trailer") { return true }
        if path.contains("/preview/") || path.contains("/trailer/") || path.contains("/thumb/") { return true }
        // Very low ladder rungs are almost always preview clips, not the main asset.
        if full.contains("144p") || full.contains("240p") { return true }
        if full.contains("thumb") && (full.contains(".mp4") || full.contains(".webm")) { return true }
        // Tiny bitrate tokens often mark preview renditions.
        if full.contains("_150k") || full.contains("_250k") { return true }
        if full.contains("_360k") && (full.contains("360p") || full.contains("thumb") || full.contains("preview")) {
            return true
        }
        return false
    }

    var bestProgressiveCandidate: PageMediaCandidate? {
        candidates
            .filter { !$0.isHLS && !Self.isCMAFFragmentURL($0.url) && !Self.isJunkOfflineURL($0.url) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }
            .first
    }

    var bestHLSCandidate: PageMediaCandidate? {
        let hls = candidates.filter { $0.isHLS && !Self.isJunkOfflineURL($0.url) }
        let scoped: [PageMediaCandidate]
        if let mediaID = preferredMediaID, !mediaID.isEmpty {
            let matched = hls.filter { Self.mediaID(from: $0.url) == mediaID }
            scoped = matched.isEmpty ? hls : matched
        } else {
            scoped = hls
        }
        let masters = scoped.filter { Self.isHLSMasterURL($0.url) }
        let pool = masters.isEmpty ? scoped : masters
        return pool.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            return lhs.discoveredAt > rhs.discoveredAt
        }.first
    }

    func noteCurrentSrc(_ currentSrc: String?) {
        guard let currentSrc, let url = URL(string: currentSrc),
              Self.isHTTPURL(url), !Self.isJunkOfflineURL(url) else { return }
        // Never pin preview/trailer MP4s as the "real" stream.
        if Self.isLikelyPreviewURL(url) {
            _ = noteMediaURL(url, mimeType: nil)
            return
        }
        pinnedPlaybackURL = url
        if let mediaID = Self.mediaID(from: url) {
            preferredMediaID = mediaID
        }
        _ = noteMediaURL(url, mimeType: nil)
    }

    /// Generic junk filter (ads, previews, player libs) — host patterns only for known ad infra.
    static func isJunkOfflineURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        if isLikelyPreviewURL(url) { return true }
        // Ad / tracker host shapes (not content-site allowlists).
        if host.contains("ads.") || host.hasPrefix("ads") || host.contains("doubleclick")
            || host.contains("googlesyndication") || host.contains("adnxs.") {
            return true
        }
        if path.contains("/ads/") || path.contains("/ad/") || full.contains("advert") { return true }
        if ext == "js" || path.contains("/www-static/") || path.contains("/lib/hls/") { return true }
        return false
    }

    static func mediaID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        for part in parts {
            let base = part.replacingOccurrences(of: ".mp4", with: "")
                .replacingOccurrences(of: ".m3u8", with: "")
            let tokens = base.split(separator: "_").map(String.init)
            guard tokens.count >= 2,
                  let last = tokens.last,
                  last.count >= 7, last.allSatisfy(\.isNumber) else { continue }
            let looksQuality = tokens.contains {
                $0.uppercased().hasSuffix("P") || $0.uppercased().hasSuffix("K")
            }
            if looksQuality { return last }
        }
        for (i, part) in parts.enumerated() where part == "videos" {
            if i + 3 < parts.count,
               parts[i + 1].count == 6, parts[i + 1].allSatisfy(\.isNumber),
               parts[i + 2].count <= 2, parts[i + 2].allSatisfy(\.isNumber),
               parts[i + 3].count >= 7, parts[i + 3].allSatisfy(\.isNumber) {
                return parts[i + 3]
            }
            if i + 4 < parts.count,
               parts[i + 1].count == 4, parts[i + 1].allSatisfy(\.isNumber),
               parts[i + 4].count >= 7, parts[i + 4].allSatisfy(\.isNumber) {
                return parts[i + 4]
            }
        }
        return nil
    }

    static func isHLSMasterURL(_ url: URL) -> Bool {
        let full = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        if full.contains("master.m3u8") || path.hasSuffix("/master.m3u8") { return true }
        if path.contains("/pl/") && path.hasSuffix(".m3u8")
            && !path.contains("/pl/avc1/") && !path.contains("/pl/mp4a/") {
            return true
        }
        return false
    }

    static func isHLSMediaPlaylistURL(_ url: URL) -> Bool {
        let full = url.absoluteString.lowercased()
        let path = url.path.lowercased()
        guard path.hasSuffix(".m3u8") || full.contains(".m3u8") else { return false }
        if isHLSMasterURL(url) { return false }
        return full.contains("index-") || path.contains("/pl/avc1/") || path.contains("/pl/mp4a/")
    }

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
        preferredMediaID = nil
        pinnedPlaybackURL = nil
        candidates.removeAll()
    }

    func clearSessionOffers() {
        offeredKeys.removeAll()
        savedIdentityKeys.removeAll()
        lastOfferAt = nil
    }

    /// Capability-based: any http(s) page can use the offline media pipeline.
    static func isEligiblePage(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Referer/Origin from the page the user is viewing (never a hardcoded site table).
    static func downloadRefererOrigin(for mediaURL: URL, pageURL: String? = nil) -> (referer: String, origin: String) {
        if let page = pageURL, let pageURL = URL(string: page),
           let scheme = pageURL.scheme, let host = pageURL.host {
            return ("\(scheme)://\(host)/", "\(scheme)://\(host)")
        }
        if let scheme = mediaURL.scheme, let host = mediaURL.host {
            return ("\(scheme)://\(host)/", "\(scheme)://\(host)")
        }
        return ("", "")
    }

    /// Cookie hosts derived from media URL + optional page URL (no site allowlists).
    static func relatedCookieHosts(for mediaURL: URL, pageURL: String? = nil) -> [String] {
        var related: [String] = []
        func addHost(_ raw: String?) {
            guard var host = raw?.lowercased(), !host.isEmpty else { return }
            related.append(host)
            if host.hasPrefix("www.") {
                host.removeFirst(4)
                related.append(host)
            }
            // Include apex (last two labels) for CDN/session cookie matching.
            let parts = host.split(separator: ".").map(String.init)
            if parts.count >= 2 {
                related.append(parts.suffix(2).joined(separator: "."))
            }
        }
        addHost(mediaURL.host)
        if let page = pageURL {
            addHost(URL(string: page)?.host)
        }
        return Array(Set(related))
    }

    func notePageContext(pageURL: String?, statusID: String?) {
        if let pageURL, !pageURL.isEmpty {
            let prevPage = self.pageURL
            self.pageURL = pageURL
            if let prevPage, !prevPage.isEmpty,
               Self.videoID(fromPageURL: prevPage) != Self.videoID(fromPageURL: pageURL) {
                preferredMediaID = nil
                pinnedPlaybackURL = nil
                candidates.removeAll()
            }
        }
        let trimmedID = statusID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID = (trimmedID?.isEmpty == false ? trimmedID : nil)
            ?? Self.videoID(fromPageURL: pageURL)
        if let resolvedID, !resolvedID.isEmpty { self.statusID = resolvedID }
    }

    @discardableResult
    func notePlaying(pageURL: String?, statusID: String?, currentSrc: String?) -> Bool {
        isArmed = true
        notePageContext(pageURL: pageURL, statusID: statusID)
        noteCurrentSrc(currentSrc)
        Self.log("probe.playing", [
            "statusID": self.statusID ?? "",
            "page": pageURL ?? "",
            "currentSrc": currentSrc ?? "",
            "mediaID": preferredMediaID ?? "",
            "pinned": pinnedPlaybackURL?.absoluteString ?? "",
            "candidatesBefore": candidates.count
        ])
        return true
    }

    /// Stable id from common watch-page URL shapes (path / query), any host.
    static func videoID(fromPageURL pageURL: String?) -> String? {
        guard let pageURL, let url = URL(string: pageURL) else { return nil }
        let href = url.absoluteString
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = comps.queryItems {
            let idKeys: Set<String> = ["v", "id", "vid", "video_id", "videoId", "viewkey", "watch"]
            if let match = items.first(where: { idKeys.contains($0.name) }),
               let value = match.value, !value.isEmpty, value.count >= 3 {
                return value
            }
        }
        // /status/123, /watch/abc, /video/123, /video123, /video-abc, /v/abc, /embed/abc
        let patterns = [
            #"/status/([0-9]+)"#,
            #"/watch/([a-zA-Z0-9_-]+)"#,
            #"/embed/([a-zA-Z0-9_-]+)"#,
            #"/v/([a-zA-Z0-9_-]+)"#,
            #"/videos?/([a-zA-Z0-9_-]+)"#,
            #"/video-([a-zA-Z0-9]+)"#,
            #"/video([0-9]{5,})"#
        ]
        for pattern in patterns {
            if let m = href.range(of: pattern, options: .regularExpression) {
                let s = String(href[m])
                if let id = s.split(separator: "/").last.map(String.init)?
                    .replacingOccurrences(of: "video-", with: "")
                    .replacingOccurrences(of: "video", with: ""),
                   !id.isEmpty {
                    return id
                }
            }
        }
        return nil
    }

    @discardableResult
    func noteMediaURL(_ url: URL, mimeType: String?) -> PageMediaCandidate? {
        guard Self.isHTTPURL(url) else { return nil }
        if Self.isJunkOfflineURL(url) {
            Self.log("probe.skipJunk", ["url": url.absoluteString])
            return nil
        }
        let mime = (mimeType ?? "").lowercased()
        let mimeOK = mime.hasPrefix("video/") || mime.contains("mpegurl") || mime.isEmpty
        let likely = Self.isLikelyMediaURL(url)
        let mimeLooksVideo = mime.hasPrefix("video/") || mime.contains("mpegurl")
        guard likely || (mimeLooksVideo && mimeOK) else { return nil }

        let isHLS = url.pathExtension.lowercased() == "m3u8"
            || mime.contains("mpegurl")
            || url.absoluteString.lowercased().contains(".m3u8")
        let ext = url.pathExtension.lowercased()
        if ["m4s", "ts", "jpg", "jpeg", "png", "webp", "gif"].contains(ext) { return nil }
        if !isHLS, Self.isCMAFFragmentURL(url) {
            Self.log("probe.skipCMAF", ["url": url.absoluteString])
            return nil
        }

        let mediaID = Self.mediaID(from: url)
        let rank = Self.rank(
            url: url,
            mimeType: mimeType,
            isHLS: isHLS,
            preferredMediaID: preferredMediaID
        )
        let key = Self.dedupeKey(for: url)
        if let existing = candidates.firstIndex(where: { Self.dedupeKey(for: $0.url) == key }) {
            if rank >= candidates[existing].rank {
                let updated = PageMediaCandidate(
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

        let candidate = PageMediaCandidate(
            url: url,
            mimeType: mimeType,
            statusID: statusID,
            pageURL: pageURL,
            isHLS: isHLS,
            rank: rank,
            discoveredAt: Date()
        )
        candidates.append(candidate)
        if candidates.count > 24 {
            candidates.sort { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }
            candidates = Array(candidates.prefix(24))
        }
        Self.log("probe.candidate", [
            "hls": isHLS,
            "rank": candidate.rank,
            "mediaID": mediaID ?? "",
            "preferred": preferredMediaID ?? "",
            "mime": mimeType ?? "",
            "url": url.absoluteString,
            "total": candidates.count,
            "best": bestCandidate?.url.absoluteString ?? ""
        ])
        return candidate
    }

    func candidateForOffer(allowHLS: Bool = true, force: Bool = false) -> PageMediaCandidate? {
        guard isArmed else {
            Self.log("offer.skip", ["why": "notArmed", "candidates": candidates.count])
            return nil
        }
        guard let candidate = allowHLS ? bestCandidate : bestProgressiveCandidate else {
            Self.log("offer.skip", ["why": "noCandidate", "candidates": candidates.count, "allowHLS": allowHLS])
            return nil
        }
        if candidate.isHLS, !allowHLS { return nil }
        if isAlreadySavedOrDownloading(candidate) {
            markOffered(candidate)
            Self.log("offer.skip", [
                "why": "alreadySavedOrDownloading",
                "url": candidate.url.absoluteString,
                "statusID": candidate.statusID ?? ""
            ])
            return nil
        }
        let key = Self.dedupeKey(for: candidate.url)
        if !force, offeredKeys.contains(key) {
            Self.log("offer.skip", ["why": "alreadyOffered", "url": candidate.url.absoluteString])
            return nil
        }
        if !force, let lastOfferAt, Date().timeIntervalSince(lastOfferAt) < 2.5 {
            Self.log("offer.skip", ["why": "throttled"])
            return nil
        }
        return candidate
    }

    func markOffered(_ candidate: PageMediaCandidate) {
        offeredKeys.insert(Self.dedupeKey(for: candidate.url))
        lastOfferAt = Date()
        Self.log("probe.offer", [
            "hls": candidate.isHLS,
            "rank": candidate.rank,
            "file": candidate.suggestedFileName,
            "url": candidate.url.absoluteString
        ])
    }

    func markDownloadStarted(_ candidate: PageMediaCandidate) {
        markOffered(candidate)
        for key in identityKeys(for: candidate) {
            savedIdentityKeys.insert(key)
        }
    }

    func isAlreadySavedOrDownloading(_ candidate: PageMediaCandidate) -> Bool {
        if identityKeys(for: candidate).contains(where: { savedIdentityKeys.contains($0) }) {
            return true
        }
        return DownloadManager.shared.hasActiveOrCompletedOfflineVideo(matching: candidate)
    }

    private func identityKeys(for candidate: PageMediaCandidate) -> [String] {
        var keys: [String] = ["url:" + Self.dedupeKey(for: candidate.url)]
        if let mediaID = Self.mediaID(from: candidate.url), !mediaID.isEmpty {
            keys.append("media:" + mediaID)
        }
        let pageID = Self.videoID(fromPageURL: candidate.pageURL) ?? candidate.statusID
        if let pageID, !pageID.isEmpty {
            keys.append("page:" + pageID.lowercased())
        }
        return keys
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        let scheme = (url.scheme ?? "").lowercased()
        return scheme == "http" || scheme == "https"
    }

    static func urlDedupeKey(for url: URL) -> String {
        dedupeKey(for: url)
    }

    private static func dedupeKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return (components?.string ?? url.absoluteString).lowercased()
    }

    /// True when the URL looks like progressive video or HLS (any host).
    static func isLikelyMediaURL(_ url: URL) -> Bool {
        if isJunkOfflineURL(url) { return false }
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        if ["mp4", "m3u8", "webm", "mov"].contains(ext) { return true }
        if full.contains(".mp4") || full.contains(".m3u8") || full.contains(".webm") { return true }
        if path.contains("/hls/") || full.contains("master.m3u8") || path.hasSuffix(".m3u8") { return true }
        // Path tokens that usually mean a playable stream (not a site allowlist).
        if path.contains("/video/") || path.contains("/videos/") || path.contains("/media/")
            || path.contains("/stream/") || path.contains("/play/") {
            if full.contains(".mp4") || full.contains(".m3u8") || full.contains("mpegurl") {
                return true
            }
        }
        if ["m4s", "ts"].contains(ext) { return false }
        return false
    }

    private static func rank(
        url: URL,
        mimeType: String?,
        isHLS: Bool,
        preferredMediaID: String? = nil
    ) -> Int {
        var score = 0
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        if isHLS {
            if path.contains("/pl/mp4a/") {
                score += 10
            } else if path.contains("/pl/avc1/") {
                score += 60
            } else if path.contains("/pl/") {
                score += 120
            } else if isHLSMasterURL(url) || full.hasSuffix("hls.m3u8") {
                score += 220
            } else if isHLSMediaPlaylistURL(url) {
                score += 90
            } else if path.contains("/hls/") {
                score += 150
            } else {
                score += 40
            }
            if path.contains("1080") || path.contains("1920") || full.contains("1080") { score += 30 }
            else if path.contains("720") || path.contains("1280") || full.contains("720") { score += 20 }
            else if full.contains("480") { score += 8 }
        } else {
            score += 100
            if full.contains("_high") || full.contains("/high/") { score += 35 }
            if full.contains("_low") || full.contains("/low/") || full.contains("240p") { score -= 20 }
            if path.contains("1080") || path.contains("1920") || full.contains("1080") { score += 30 }
            else if path.contains("720") || path.contains("1280") || full.contains("720") { score += 20 }
            if (mimeType ?? "").lowercased().contains("mp4") { score += 10 }
            if url.pathExtension.lowercased() == "mp4" { score += 25 }
            if isLikelyPreviewURL(url) { score -= 400 }
        }
        if let preferred = preferredMediaID, !preferred.isEmpty, mediaID(from: url) == preferred {
            score += 250
        }
        return score
    }

    // MARK: - JS

    static var userScript: WKUserScript {
        WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    static var scriptSourceForEvaluation: String { scriptSource }

    private static let scriptSource = #"""
(function() {
  var scheme = (location.protocol || '').toLowerCase();
  if (scheme !== 'http:' && scheme !== 'https:') return;
  if (window.__mmPageMediaInstalled) return;
  window.__mmPageMediaInstalled = true;

  function post(payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mmPageMedia) {
        window.webkit.messageHandlers.mmPageMedia.postMessage(payload);
      }
    } catch (e) {}
  }

  function videoIDFromHref(href) {
    try {
      var s = String(href || '');
      var q = s.match(/[?&](?:v|id|vid|video_id|videoId|viewkey|watch)=([a-zA-Z0-9_-]{3,})/i);
      if (q) return q[1];
      var patterns = [
        /\/status\/(\d+)/,
        /\/watch\/([a-zA-Z0-9_-]+)/,
        /\/embed\/([a-zA-Z0-9_-]+)/,
        /\/v\/([a-zA-Z0-9_-]+)/,
        /\/videos?\/([a-zA-Z0-9_-]+)/,
        /\/video-([a-zA-Z0-9]+)/,
        /\/video(\d{5,})/
      ];
      for (var i = 0; i < patterns.length; i++) {
        var m = s.match(patterns[i]);
        if (m) return m[1];
      }
    } catch (e) {}
    return null;
  }

  function nearestStatusID(video) {
    var node = video;
    for (var i = 0; i < 12 && node; i++) {
      try {
        var a = node.querySelector && node.querySelector('a[href*="/status/"], a[href*="/video"], a[href*="/watch"], a[href*="/embed/"], a[href*="/v/"], a[href*="?v="], a[href*="viewkey="]');
        if (a && a.href) {
          var id = videoIDFromHref(a.href);
          if (id) return id;
        }
        if (node.tagName === 'A' && node.href) {
          var id2 = videoIDFromHref(node.href);
          if (id2) return id2;
        }
      } catch (e) {}
      node = node.parentElement;
    }
    return videoIDFromHref(location.href);
  }

  function httpSrc(video) {
    try {
      var src = video.currentSrc || video.src || '';
      if (/^https?:/i.test(src)) return src;
      var sources = video.querySelectorAll && video.querySelectorAll('source[src]');
      if (sources) {
        for (var i = 0; i < sources.length; i++) {
          var s = sources[i].getAttribute('src') || '';
          if (/^https?:/i.test(s)) return s;
        }
      }
    } catch (e) {}
    return null;
  }

  function isMediaName(name) {
    var lower = String(name || '').toLowerCase();
    if (!lower || lower.indexOf('http') !== 0) return false;
    // Skip ads / trackers / player libs (capability junk, not site tables).
    if (lower.indexOf('doubleclick') !== -1 || lower.indexOf('googlesyndication') !== -1
        || lower.indexOf('/ads/') !== -1 || lower.indexOf('adnxs.') !== -1) return false;
    if (lower.indexOf('preview') !== -1 || lower.indexOf('trailer') !== -1) {
      if (lower.indexOf('.mp4') !== -1 || lower.indexOf('.webm') !== -1) return false;
    }
    if (lower.indexOf('.js') !== -1 || lower.indexOf('/www-static/') !== -1 || lower.indexOf('/lib/hls/') !== -1) return false;
    if (lower.indexOf('.mp4') !== -1 || lower.indexOf('.m3u8') !== -1
        || lower.indexOf('.webm') !== -1 || lower.indexOf('/hls/') !== -1
        || lower.indexOf('master.m3u8') !== -1) {
      return true;
    }
    return false;
  }

  function collectResourceCandidates() {
    var out = [];
    var seen = {};
    function push(u) {
      if (!u) return;
      u = String(u).replace(/\\u002F/g, '/').replace(/\\\//g, '/').replace(/&amp;/g, '&');
      if (!u || seen[u] || !isMediaName(u)) return;
      seen[u] = 1;
      out.push(u);
    }
    try {
      var entries = performance.getEntriesByType('resource') || [];
      for (var i = 0; i < entries.length; i++) push(entries[i].name);
    } catch (e) {}
    try {
      var html = String(document.documentElement && document.documentElement.innerHTML || '');
      var re = /https?:\/\/[^"'\\\s<>]+(?:\.m3u8|\.mp4|\.webm)[^"'\\\s<>]*/gi;
      var m;
      while ((m = re.exec(html)) && out.length < 50) push(m[0]);
      // Common embedded player JSON keys (quality variants / HLS masters).
      var keys = [
        /"videoUrl"\s*:\s*"(https?:[^"]+)"/gi,
        /"contentUrl"\s*:\s*"(https?:[^"]+)"/gi,
        /"hlsUrl"\s*:\s*"(https?:[^"]+)"/gi,
        /"src"\s*:\s*"(https?:[^"]+\.m3u8[^"]*)"/gi
      ];
      for (var k = 0; k < keys.length; k++) {
        var kr = keys[k];
        var km;
        while ((km = kr.exec(html)) && out.length < 60) push(km[1]);
      }
    } catch (e) {}
    return out.slice(-50);
  }

  function firstVideo() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        if (vids[i]) return vids[i];
      }
    } catch (e) {}
    return null;
  }

  function report(eventName, video, extra) {
    var v = video || firstVideo();
    var resources = collectResourceCandidates();
    var payload = {
      event: eventName || 'playing',
      pageURL: String(location.href || ''),
      statusID: nearestStatusID(v),
      currentSrc: v ? httpSrc(v) : null,
      width: v ? (v.videoWidth || 0) : 0,
      height: v ? (v.videoHeight || 0) : 0,
      fullscreen: 0,
      resources: resources
    };
    if (extra) {
      for (var k in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, k)) payload[k] = extra[k];
      }
    }
    post(payload);
  }

  function bindVideo(video) {
    if (!video || video.__mmPageMediaBound) return;
    video.__mmPageMediaBound = true;
    ['play', 'playing', 'loadeddata', 'timeupdate'].forEach(function(evt) {
      video.addEventListener(evt, function() { report('playing', video); }, true);
    });
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

  document.addEventListener('click', function() {
    setTimeout(function() {
      scan();
      report('playing', firstVideo());
    }, 300);
    setTimeout(function() {
      report('playing', firstVideo());
    }, 1200);
  }, true);

  setTimeout(function() { report('resources', firstVideo()); }, 800);
  setTimeout(function() { report('resources', firstVideo()); }, 2500);

  setInterval(function() {
    try {
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (v && !v.paused && !v.ended && v.readyState >= 2) {
          report('playing', v);
          break;
        }
      }
    } catch (e) {}
  }, 1500);
})();
"""#
}
