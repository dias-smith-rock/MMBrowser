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
        let prefix = XVideoOfflineProbe.filePrefix(forPageURL: pageURL, mediaURL: url)
        if let statusID, !statusID.isEmpty {
            return "\(prefix)-\(statusID)-\(stamp).mp4"
        }
        return "\(prefix)-video-\(stamp).mp4"
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
    /// Numeric CDN media id from the actively playing `currentSrc` (e.g. PH `421858811`).
    private(set) var preferredMediaID: String?
    /// Exact playback URL when the player reports an http(s) currentSrc.
    private(set) var pinnedPlaybackURL: URL?
    private var candidates: [XVideoOfflineCandidate] = []
    private var offeredKeys = Set<String>()
    /// Page / media ids already started or completed offline in this tab session.
    private var savedIdentityKeys = Set<String>()
    private var lastOfferAt: Date?

    var bestCandidate: XVideoOfflineCandidate? {
        // Prefer the URL the player is actually using (avoids related-video trailers).
        if let pinned = pinnedPlaybackURL {
            if let match = candidates.first(where: { Self.dedupeKey(for: $0.url) == Self.dedupeKey(for: pinned) }) {
                return match
            }
            let isHLS = pinned.pathExtension.lowercased() == "m3u8"
                || pinned.absoluteString.lowercased().contains(".m3u8")
            return XVideoOfflineCandidate(
                url: pinned,
                mimeType: isHLS ? "application/vnd.apple.mpegurl" : "video/mp4",
                statusID: statusID,
                pageURL: pageURL,
                isHLS: isHLS,
                rank: 10_000,
                discoveredAt: Date()
            )
        }
        let adult = Self.isAdultVideoPageURLString(pageURL)
        if adult {
            // PH/XV/XNXX: real watch streams are HLS; progressive hits are often `_fb` trailers.
            return bestHLSCandidate ?? bestProgressiveCandidate
        }
        return bestProgressiveCandidate ?? bestHLSCandidate
            ?? candidates.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }.first
    }

    /// True progressive MP4 only — modern X `/vid/avc1/` URLs are CMAF init segments (~1KB), not full files.
    var bestProgressiveCandidate: XVideoOfflineCandidate? {
        candidates
            .filter { !$0.isHLS && !Self.isCMAFFragmentURL($0.url) && !Self.isJunkOfflineURL($0.url) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
                return lhs.discoveredAt > rhs.discoveredAt
            }
            .first
    }

    /// Prefer master playlists; when `preferredMediaID` is known, stick to that video.
    var bestHLSCandidate: XVideoOfflineCandidate? {
        let hls = candidates.filter { $0.isHLS && !Self.isJunkOfflineURL($0.url) }
        let scoped: [XVideoOfflineCandidate]
        if let mediaID = preferredMediaID, !mediaID.isEmpty {
            let matched = hls.filter { Self.mediaID(from: $0.url) == mediaID }
            scoped = matched.isEmpty ? hls : matched
        } else {
            scoped = hls
        }
        // Prefer true masters over media playlists (`index-v1-a1.m3u8`).
        let masters = scoped.filter { Self.isHLSMasterURL($0.url) }
        let pool = masters.isEmpty ? scoped : masters
        return pool.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            return lhs.discoveredAt > rhs.discoveredAt
        }.first
    }

    /// Pin the player's currentSrc when it is a real media URL (survives noisy resource scrapes).
    func noteCurrentSrc(_ currentSrc: String?) {
        guard let currentSrc, let url = URL(string: currentSrc),
              Self.isHTTPURL(url), !Self.isJunkOfflineURL(url) else { return }
        pinnedPlaybackURL = url
        if let mediaID = Self.mediaID(from: url) {
            preferredMediaID = mediaID
        }
        _ = noteMediaURL(url, mimeType: nil)
    }

    /// PH related-rail trailers, thumbs, ads, get_media JSON — never offline targets.
    static func isJunkOfflineURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        if path.contains("/video/get_media") { return true }
        if full.contains("_fb.mp4") { return true }
        if host.contains("pix-") || path.contains("/plain/") { return true }
        if host.contains("adtng.com") || host.contains("ads.") || host.contains("doubleclick") {
            return true
        }
        if host.contains("sacdnssedge.com") || host.contains("trafficjunky") { return true }
        // Player libraries / static assets mistaken for media (e.g. hls-v1.5.14.min.js).
        if ext == "js" || path.contains("/www-static/") || path.contains("/lib/hls/") { return true }
        // PH preview thumbs disguised as mp4.
        if full.contains("360p_360k") && full.contains("_fb") { return true }
        return false
    }

    /// CDN folder id like `421858811` from `/videos/YYYYMM/DD/421858811/…` or quality filename.
    static func mediaID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        // Prefer id in quality filename: `720P_4000K_421858811.mp4` / `…mp4/master.m3u8`
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
            // …/videos/YYYYMM/DD/<id>/…  (PornHub)
            if i + 3 < parts.count,
               parts[i + 1].count == 6, parts[i + 1].allSatisfy(\.isNumber),
               parts[i + 2].count <= 2, parts[i + 2].allSatisfy(\.isNumber),
               parts[i + 3].count >= 7, parts[i + 3].allSatisfy(\.isNumber) {
                return parts[i + 3]
            }
            // …/videos/YYYY/MM/DD/<id>/…
            if i + 4 < parts.count,
               parts[i + 1].count == 4, parts[i + 1].allSatisfy(\.isNumber),
               parts[i + 4].count >= 7, parts[i + 4].allSatisfy(\.isNumber) {
                return parts[i + 4]
            }
        }
        return nil
    }

    /// True for top-level HLS masters (not media playlists like `index-v1-a1.m3u8`).
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
        preferredMediaID = nil
        pinnedPlaybackURL = nil
        candidates.removeAll()
        // Keep offeredKeys / savedIdentityKeys for the tab session so we don't re-prompt.
    }

    func clearSessionOffers() {
        offeredKeys.removeAll()
        savedIdentityKeys.removeAll()
        lastOfferAt = nil
    }

    /// X/Twitter + adult video sites that share the offline-save pipeline.
    static func isSupportedPage(_ url: URL?) -> Bool {
        isXTwitterPage(url) || isAdultVideoPage(url)
    }

    static func isXTwitterPage(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "x.com" || host.hasSuffix(".x.com")
            || host == "twitter.com" || host.hasSuffix(".twitter.com")
    }

    /// PornHub / XVideos / XNXX — toast only while the video is fullscreen.
    static func isAdultVideoPage(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        if host == "pornhub.com" || host.hasSuffix(".pornhub.com")
            || host == "pornhubpremium.com" || host.hasSuffix(".pornhubpremium.com") {
            return true
        }
        if host == "xvideos.com" || host.hasSuffix(".xvideos.com") {
            return true
        }
        if host == "xnxx.com" || host.hasSuffix(".xnxx.com") {
            return true
        }
        return false
    }

    static func isAdultVideoPageURLString(_ pageURL: String?) -> Bool {
        guard let pageURL, let url = URL(string: pageURL) else { return false }
        return isAdultVideoPage(url)
    }

    /// Back-compat alias used by older call sites.
    static func isXPage(_ url: URL?) -> Bool { isSupportedPage(url) }

    static func isMediaHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host.contains("twimg.com") || host.contains("pscp.tv") || host.contains("periscope.tv") {
            return true
        }
        // PornHub CDN / site
        if host.contains("phncdn.com") || host.contains("pornhub.com") || host.contains("pornhubpremium.com") {
            return true
        }
        // XVideos / XNXX CDNs (often `*-cdn.com`)
        if host.contains("xvideos-cdn.com") || host.contains("xvideos.com") {
            return true
        }
        if host.contains("xnxx-cdn.com") || host.contains("xnxx.com") {
            return true
        }
        return false
    }

    static func isLikelyMediaURL(_ url: URL) -> Bool {
        if isJunkOfflineURL(url) { return false }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let full = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        let looksVideoFile = ["mp4", "m3u8"].contains(ext)
            || full.contains(".mp4") || full.contains(".m3u8") || path.contains("/hls/")
        if isMediaHost(host) {
            if looksVideoFile { return true }
            if path.contains("/amplify_video") || path.contains("/ext_tw_video") || path.contains("/tweet_video") {
                return true
            }
            if ["m4s", "ts"].contains(ext) { return true }
        }
        // XV/XNXX often rotate CDN hostnames; accept obvious video paths on any https host.
        if looksVideoFile, path.contains("/videos/") || path.contains("/hls/") || full.contains("hls.m3u8") {
            return true
        }
        return false
    }

    /// Filename brand prefix from page or media host.
    static func filePrefix(forPageURL pageURL: String?, mediaURL: URL?) -> String {
        let hosts = [pageURL.flatMap { URL(string: $0)?.host }, mediaURL?.host]
            .compactMap { $0?.lowercased() }
        for host in hosts {
            if host.contains("pornhub") || host.contains("phncdn") { return "ph" }
            if host.contains("xvideos") { return "xv" }
            if host.contains("xnxx") { return "xnxx" }
            if host == "x.com" || host.hasSuffix(".x.com")
                || host.contains("twitter") || host.contains("twimg") { return "x" }
        }
        return "video"
    }

    /// Prefer site-matching Referer/Origin for CDN fetches.
    static func downloadRefererOrigin(for mediaURL: URL, pageURL: String? = nil) -> (referer: String, origin: String) {
        if let page = pageURL, let pageURL = URL(string: page), isSupportedPage(pageURL),
           let scheme = pageURL.scheme, let host = pageURL.host {
            return ("\(scheme)://\(host)/", "\(scheme)://\(host)")
        }
        let host = mediaURL.host?.lowercased() ?? ""
        if host.contains("phncdn") || host.contains("pornhub") {
            return ("https://www.pornhub.com/", "https://www.pornhub.com")
        }
        if host.contains("xvideos") {
            return ("https://www.xvideos.com/", "https://www.xvideos.com")
        }
        if host.contains("xnxx") {
            return ("https://www.xnxx.com/", "https://www.xnxx.com")
        }
        return ("https://x.com/", "https://x.com")
    }

    static func relatedCookieHosts(for mediaURL: URL) -> [String] {
        let host = mediaURL.host?.lowercased() ?? ""
        var related = [host]
        if host.contains("twimg") || host.contains("pscp") || host.contains("periscope") {
            related += ["x.com", "twitter.com", "api.x.com", "api.twitter.com"]
        } else if host.contains("phncdn") || host.contains("pornhub") {
            related += ["pornhub.com", "www.pornhub.com", "pornhubpremium.com", "www.pornhubpremium.com"]
        } else if host.contains("xvideos") {
            related += ["xvideos.com", "www.xvideos.com"]
        } else if host.contains("xnxx") {
            related += ["xnxx.com", "www.xnxx.com"]
        }
        return related
    }

    /// Seeds page/id without arming (used for pre-play resource scrapes).
    func notePageContext(pageURL: String?, statusID: String?) {
        if let pageURL, !pageURL.isEmpty {
            let prevPage = self.pageURL
            self.pageURL = pageURL
            // New watch URL → drop pin so related-rail media cannot stick.
            // Do not clear on transient JS statusID flips (ads overlay a different id).
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

    /// Extract a stable id from common watch-page URLs (X status, PH viewkey, XV/XNXX video id).
    static func videoID(fromPageURL pageURL: String?) -> String? {
        guard let pageURL, let url = URL(string: pageURL) else { return nil }
        let href = url.absoluteString
        if let m = href.range(of: #"/status/(\d+)"#, options: .regularExpression) {
            let s = String(href[m])
            return s.split(separator: "/").last.map(String.init)
        }
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let viewkey = comps.queryItems?.first(where: { $0.name == "viewkey" })?.value,
           !viewkey.isEmpty {
            return viewkey
        }
        if let m = href.range(of: #"/video(\d+)"#, options: .regularExpression) {
            let s = String(href[m])
            return s.replacingOccurrences(of: "/video", with: "")
        }
        if let m = href.range(of: #"/video-([a-zA-Z0-9]+)"#, options: .regularExpression) {
            let s = String(href[m])
            return s.replacingOccurrences(of: "/video-", with: "")
        }
        return nil
    }

    @discardableResult
    func noteMediaURL(_ url: URL, mimeType: String?) -> XVideoOfflineCandidate? {
        guard Self.isHTTPURL(url) else { return nil }
        if Self.isJunkOfflineURL(url) {
            Self.log("probe.skipJunk", ["url": url.absoluteString])
            return nil
        }
        let mime = (mimeType ?? "").lowercased()
        let mimeOK = mime.hasPrefix("video/") || mime.contains("mpegurl") || mime.isEmpty
        let likely = Self.isLikelyMediaURL(url)
        let hostOK = Self.isMediaHost(url.host)
        guard likely || ((hostOK || mime.hasPrefix("video/") || mime.contains("mpegurl")) && mimeOK) else {
            return nil
        }
        guard mimeOK || likely else { return nil }

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
            rank: rank,
            discoveredAt: Date()
        )
        candidates.append(candidate)
        // Keep highest-rank entries; pinned / preferred-id HLS survive trailer noise.
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

    /// Returns a candidate suitable for offering Save (progressive MP4, else HLS master).
    /// - Parameter force: bypass offered/throttle (e.g. after exiting native fullscreen where toast was covered).
    ///   Never bypasses “already downloading / completed”.
    func candidateForOffer(allowHLS: Bool = true, force: Bool = false) -> XVideoOfflineCandidate? {
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

    /// Call when an offline download is started so we never re-toast for the same video.
    func markDownloadStarted(_ candidate: XVideoOfflineCandidate) {
        markOffered(candidate)
        for key in identityKeys(for: candidate) {
            savedIdentityKeys.insert(key)
        }
    }

    func isAlreadySavedOrDownloading(_ candidate: XVideoOfflineCandidate) -> Bool {
        if identityKeys(for: candidate).contains(where: { savedIdentityKeys.contains($0) }) {
            return true
        }
        return DownloadManager.shared.hasActiveOrCompletedOfflineVideo(matching: candidate)
    }

    private func identityKeys(for candidate: XVideoOfflineCandidate) -> [String] {
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

    /// Path identity without query/fragment (signed CDN tokens differ per request).
    static func urlDedupeKey(for url: URL) -> String {
        dedupeKey(for: url)
    }

    private static func dedupeKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Drop short-lived query tokens for dedupe, keep path identity.
        components?.query = nil
        components?.fragment = nil
        return (components?.string ?? url.absoluteString).lowercased()
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
            // X master `/pl/<token>.m3u8` beats variant `/pl/avc1|mp4a/...`.
            if path.contains("/pl/mp4a/") {
                score += 10
            } else if path.contains("/pl/avc1/") {
                score += 60
            } else if path.contains("/pl/") {
                score += 120
            } else if isHLSMasterURL(url) || full.hasSuffix("hls.m3u8") {
                // PH / XV / XNXX masters — always beat media playlists.
                score += 220
            } else if isHLSMediaPlaylistURL(url) {
                // `index-v1-a1.m3u8` etc. — usable fallback, but never preferred over master.
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
            // Related-rail / preview progressive on PH — keep rank low if somehow not filtered.
            if full.contains("_fb.mp4") || full.contains("360p_360k") { score -= 400 }
        }
        if path.contains("amplify_video") || path.contains("ext_tw_video") || path.contains("tweet_video") {
            score += 15
        }
        if full.contains("phncdn.com") || full.contains("xvideos-cdn.com") || full.contains("xnxx-cdn.com") {
            score += 15
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

    /// Same payload as `userScript`, for late `evaluateJavaScript` when the page is already loaded.
    static var scriptSourceForEvaluation: String { scriptSource }

    private static let scriptSource = #"""
(function() {
  function hostOK() {
    var h = (location.hostname || '').toLowerCase();
    return h === 'x.com' || h === 'twitter.com' || h.endsWith('.x.com') || h.endsWith('.twitter.com')
      || h === 'pornhub.com' || h.endsWith('.pornhub.com')
      || h === 'pornhubpremium.com' || h.endsWith('.pornhubpremium.com')
      || h === 'xvideos.com' || h.endsWith('.xvideos.com')
      || h === 'xnxx.com' || h.endsWith('.xnxx.com');
  }
  // Only mark installed after host check — avoid poisoning the flag on blank/iframe docs.
  if (!hostOK()) return;
  if (window.__mmXVideoOfflineInstalled) return;
  window.__mmXVideoOfflineInstalled = true;

  function post(payload) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mmXVideoOffline) {
        window.webkit.messageHandlers.mmXVideoOffline.postMessage(payload);
      }
    } catch (e) {}
  }

  function videoIDFromHref(href) {
    try {
      var s = String(href || '');
      var m = s.match(/\/status\/(\d+)/);
      if (m) return m[1];
      m = s.match(/[?&]viewkey=([a-zA-Z0-9]+)/);
      if (m) return m[1];
      m = s.match(/\/video(\d+)/);
      if (m) return m[1];
      m = s.match(/\/video-([a-zA-Z0-9]+)/);
      if (m) return m[1];
    } catch (e) {}
    return null;
  }

  function nearestStatusID(video) {
    var node = video;
    for (var i = 0; i < 12 && node; i++) {
      try {
        var a = node.querySelector && node.querySelector('a[href*="/status/"], a[href*="viewkey="], a[href*="/video"]');
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
    if (lower.indexOf('/video/get_media') !== -1) return false;
    // Related-rail trailers / thumbs / ads / player libs — never offline targets.
    if (lower.indexOf('_fb.mp4') !== -1) return false;
    if (lower.indexOf('pix-') !== -1 && lower.indexOf('/plain/') !== -1) return false;
    if (lower.indexOf('adtng.com') !== -1 || lower.indexOf('doubleclick') !== -1) return false;
    if (lower.indexOf('sacdnssedge.com') !== -1) return false;
    if (lower.indexOf('.js') !== -1 || lower.indexOf('/www-static/') !== -1 || lower.indexOf('/lib/hls/') !== -1) return false;
    if (lower.indexOf('.mp4') !== -1 || lower.indexOf('.m3u8') !== -1
        || lower.indexOf('/hls/') !== -1 || lower.indexOf('master.m3u8') !== -1
        || lower.indexOf('amplify_video') !== -1 || lower.indexOf('ext_tw_video') !== -1
        || lower.indexOf('tweet_video') !== -1) {
      // Prefer known CDNs, but also allow /videos/ paths used by XV/XNXX rotating hosts.
      if (lower.indexOf('twimg.com') !== -1 || lower.indexOf('pscp.tv') !== -1
          || lower.indexOf('phncdn.com') !== -1 || lower.indexOf('pornhub.com') !== -1
          || lower.indexOf('xvideos') !== -1 || lower.indexOf('xnxx') !== -1
          || lower.indexOf('/videos/') !== -1 || lower.indexOf('-cdn.') !== -1) {
        return true;
      }
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
    // XV / XNXX embed URLs as html5player.setVideoUrlHigh('…') / setVideoHLS('…').
    try {
      var html = String(document.documentElement && document.documentElement.innerHTML || '');
      var setters = [
        /setVideoUrlHigh\s*\(\s*['"]([^'"]+)['"]\s*\)/ig,
        /setVideoUrlLow\s*\(\s*['"]([^'"]+)['"]\s*\)/ig,
        /setVideoHLS\s*\(\s*['"]([^'"]+)['"]\s*\)/ig,
        /setVideoUrl\s*\(\s*['"]([^'"]+)['"]\s*\)/ig,
        /setVideoUrlMedium\s*\(\s*['"]([^'"]+)['"]\s*\)/ig
      ];
      for (var s = 0; s < setters.length; s++) {
        var reS = setters[s];
        var ms;
        while ((ms = reS.exec(html)) && out.length < 40) push(ms[1]);
      }
      var re = /https?:\/\/[^"'\\\s<>]+(?:\.m3u8|\.mp4)[^"'\\\s<>]*/gi;
      var m;
      while ((m = re.exec(html)) && out.length < 50) push(m[0]);
    } catch (e) {}
    try {
      if (window.html5player) {
        var p = window.html5player;
        ['getVideoUrlHigh', 'getVideoUrlLow', 'getVideoHLS', 'getVideoUrl', 'getVideoUrlMedium'].forEach(function(fn) {
          try { if (typeof p[fn] === 'function') push(p[fn]()); } catch (e) {}
        });
        ['videoUrlHigh', 'videoUrlLow', 'videoHLS', 'url_high', 'url_low', 'urlhigh', 'urllow'].forEach(function(k) {
          try { if (p[k]) push(String(p[k])); } catch (e) {}
        });
      }
    } catch (e) {}
    return out.slice(-40);
  }

  function isAdultSite() {
    var h = (location.hostname || '').toLowerCase();
    return h === 'pornhub.com' || h.endsWith('.pornhub.com')
      || h === 'pornhubpremium.com' || h.endsWith('.pornhubpremium.com')
      || h === 'xvideos.com' || h.endsWith('.xvideos.com')
      || h === 'xnxx.com' || h.endsWith('.xnxx.com');
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

  function isVideoFullscreen(video) {
    try {
      if (document.fullscreenElement || document.webkitFullscreenElement) return true;
    } catch (e) {}
    try {
      if (video && (video.webkitDisplayingFullscreen || video.webkitPresentationMode === 'fullscreen')) {
        return true;
      }
    } catch (e) {}
    try {
      var bodyCls = String((document.body && document.body.className) || '');
      var htmlCls = String((document.documentElement && document.documentElement.className) || '');
      if (/fullscreen|full-screen|isfullscreen|mgp_fullscreen|player-fullscreen/i.test(bodyCls + ' ' + htmlCls)) {
        return true;
      }
      if (document.querySelector(
        '.mgp_fullscreen, .mgp_playerElement.mgp_fullscreen, .video-wrapper.fullscreen, .player.is-fullscreen, .mhp1138_fullscreen, [class*="isFullscreen"], [class*="is-fullscreen"]'
      )) {
        return true;
      }
    } catch (e) {}
    // Custom in-page fullscreen (player stretched to viewport; allow browser chrome).
    try {
      var v = video || firstVideo();
      if (!v) return false;
      var r = v.getBoundingClientRect();
      var vw = window.innerWidth || document.documentElement.clientWidth || 0;
      var vh = window.innerHeight || document.documentElement.clientHeight || 0;
      if (vw > 0 && vh > 0 && r.width >= vw * 0.85 && r.height >= vh * 0.55) return true;
      var node = v.parentElement;
      for (var i = 0; i < 10 && node; i++) {
        var cls = String(node.className || '').toLowerCase();
        var id = String(node.id || '').toLowerCase();
        if (cls.indexOf('fullscreen') !== -1 || id.indexOf('fullscreen') !== -1
            || cls.indexOf('full-screen') !== -1 || cls.indexOf('is-fs') !== -1
            || cls.indexOf('mgp_fullscreen') !== -1) {
          return true;
        }
        node = node.parentElement;
      }
    } catch (e) {}
    return false;
  }

  function isFullscreenControl(el) {
    var node = el;
    for (var i = 0; i < 8 && node; i++) {
      try {
        var aria = String((node.getAttribute && (node.getAttribute('aria-label') || node.getAttribute('title') || node.getAttribute('data-title') || '')) || '');
        var cls = String(node.className || '');
        var id = String(node.id || '');
        var blob = (aria + ' ' + cls + ' ' + id).toLowerCase();
        if (/full\s*screen|fullscreen|jbtn-fs|mgp_fullscreen|icon-fullscreen|fs-icon|btn-fullscreen|mhp1138_fullscreen/.test(blob)) {
          return true;
        }
      } catch (e) {}
      node = node.parentElement;
    }
    return false;
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
      fullscreen: isVideoFullscreen(v) ? 1 : 0,
      resources: resources
    };
    if (extra) {
      for (var k in extra) {
        if (Object.prototype.hasOwnProperty.call(extra, k)) payload[k] = extra[k];
      }
    }
    post(payload);
  }

  var lastFullscreenSent = 0;
  function reportFullscreenForced(video, reason) {
    if (!isAdultSite()) return;
    var now = Date.now();
    if (now - lastFullscreenSent < 1500) return;
    lastFullscreenSent = now;
    report('fullscreen', video || firstVideo(), { fullscreen: 1, reason: reason || 'force' });
  }

  function reportFullscreenIfNeeded(video, force) {
    if (!isAdultSite()) return;
    var v = video || firstVideo();
    if (!isVideoFullscreen(v)) return;
    var now = Date.now();
    if (!force && now - lastFullscreenSent < 4000) return;
    lastFullscreenSent = now;
    report('fullscreen', v, { reason: force ? 'detect-force' : 'detect' });
  }

  function bindVideo(video) {
    if (!video || video.__mmXOfflineBound) return;
    video.__mmXOfflineBound = true;
    if (isAdultSite()) {
      // Seed candidates quietly; toast only on fullscreen.
      ['play', 'playing', 'loadeddata'].forEach(function(evt) {
        video.addEventListener(evt, function() { report('resources', video); }, true);
      });
      // Native iOS fullscreen — toast is often covered while FS is up, so also signal exit.
      video.addEventListener('webkitbeginfullscreen', function() {
        reportFullscreenForced(video, 'webkitbegin');
      }, true);
      video.addEventListener('webkitendfullscreen', function() {
        report('fullscreenExit', video, { fullscreen: 0, reason: 'webkitend' });
      }, true);
      try {
        video.addEventListener('webkitpresentationmodechanged', function() {
          if (video.webkitPresentationMode === 'fullscreen') {
            reportFullscreenForced(video, 'presentation');
          } else {
            report('fullscreenExit', video, { fullscreen: 0, reason: 'presentation-exit' });
          }
        }, true);
      } catch (e) {}
    } else {
      ['play', 'playing', 'loadeddata', 'timeupdate'].forEach(function(evt) {
        video.addEventListener(evt, function() { report('playing', video); }, true);
      });
    }
  }

  function scan() {
    try {
      document.querySelectorAll('video').forEach(bindVideo);
    } catch (e) {}
  }

  scan();
  try {
    var mo = new MutationObserver(function() {
      scan();
      reportFullscreenIfNeeded(firstVideo(), false);
    });
    mo.observe(document.documentElement || document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style']
    });
  } catch (e) {}

  ['fullscreenchange', 'webkitfullscreenchange'].forEach(function(evt) {
    document.addEventListener(evt, function() {
      if (document.fullscreenElement || document.webkitFullscreenElement) {
        reportFullscreenForced(firstVideo(), 'doc-fs');
      } else if (isAdultSite()) {
        report('fullscreenExit', firstVideo(), { fullscreen: 0, reason: 'doc-fs-exit' });
      }
    }, true);
  });

  document.addEventListener('click', function(e) {
    var fsTap = isAdultSite() && isFullscreenControl(e.target);
    setTimeout(function() {
      scan();
      if (isAdultSite()) {
        report('resources', firstVideo());
        if (fsTap) {
          reportFullscreenForced(firstVideo(), 'fs-button');
          setTimeout(function() { reportFullscreenIfNeeded(firstVideo(), true); }, 600);
          setTimeout(function() { reportFullscreenIfNeeded(firstVideo(), true); }, 1800);
        } else {
          reportFullscreenIfNeeded(firstVideo(), false);
        }
      } else {
        report('playing', firstVideo());
      }
    }, 300);
    setTimeout(function() {
      if (isAdultSite()) {
        report('resources', firstVideo());
        if (fsTap) reportFullscreenForced(firstVideo(), 'fs-button-late');
        else reportFullscreenIfNeeded(firstVideo(), false);
      } else {
        report('playing', firstVideo());
      }
    }, 1200);
  }, true);

  setTimeout(function() { report('resources', firstVideo()); }, 800);
  setTimeout(function() { report('resources', firstVideo()); }, 2500);

  // Also scrape PH mediaDefinitions / videoUrl JSON blobs.
  try {
    var html = String(document.documentElement && document.documentElement.innerHTML || '');
    var rePH = /"videoUrl"\s*:\s*"(https?:[^"]+)"/gi;
    var pm;
    var extras = [];
    while ((pm = rePH.exec(html)) && extras.length < 20) extras.push(pm[1].replace(/\\u002F/g, '/').replace(/\\\//g, '/'));
    if (extras.length) {
      post({
        event: 'resources',
        pageURL: String(location.href || ''),
        statusID: videoIDFromHref(location.href),
        currentSrc: null,
        resources: extras,
        fullscreen: 0
      });
    }
  } catch (e) {}

  setInterval(function() {
    try {
      if (isAdultSite()) {
        reportFullscreenIfNeeded(firstVideo(), false);
        return;
      }
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
