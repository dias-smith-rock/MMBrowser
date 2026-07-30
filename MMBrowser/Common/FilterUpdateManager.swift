import Foundation
import WebKit

/// Remote filter / script hot-update with local cache and bundled fallbacks.
final class FilterUpdateManager {
    static let shared = FilterUpdateManager()

    /// Configurable endpoint; failures fall back to cache / bundled defaults.
    static let manifestURL = URL(string: "https://cdn.jsdelivr.net/gh/mmbrowser/filters@main/manifest.json")!

    enum Health: String {
        case ok = "OK"
        case updateAvailable = "Update available"
        case degraded = "Degraded"
        case offline = "Using bundled filters"
    }

    private let defaults = UserDefaults.standard
    private let cacheFileName = "mmbrowser_filter_manifest.json"
    private(set) var health: Health = .offline
    private(set) var manifestVersion: Int = 0
    private(set) var remoteAllowsYouTubeAdShield: Bool = true
    private(set) var youtubeAdShieldScript: String = ""
    private(set) var shortsCSSSelectors: [String] = []
    private(set) var networkDomains: [String] = []
    private(set) var cosmeticSelectors: [String] = []
    private var isRefreshing = false

    private init() {
        shortsCSSSelectors = Self.sanitizedShortsSelectors(Self.defaultShortsSelectors)
        networkDomains = FilterUpdateManager.defaultNetworkDomains
        cosmeticSelectors = FilterUpdateManager.defaultCosmeticSelectors
        loadFromCacheOrBundle()
    }

    func prepare() {
        loadFromCacheOrBundle()
        refreshIfNeeded()
    }

    func markYouTubeDegraded() {
        health = .degraded
        NotificationCenter.default.post(name: .filterStatusChanged, object: nil)
    }

    func clearDegradedIfNeeded() {
        if health == .degraded {
            health = manifestVersion > 0 ? .ok : .offline
            NotificationCenter.default.post(name: .filterStatusChanged, object: nil)
        }
    }

    var statusSummary: String {
        let v = manifestVersion > 0 ? "v\(manifestVersion)" : "bundled"
        return "\(health.rawValue) · \(v)"
    }

    func refreshIfNeeded(force: Bool = false) {
        let last = defaults.double(forKey: "filters.lastCheck")
        let age = Date().timeIntervalSince1970 - last
        guard force || age > 6 * 60 * 60 else { return }
        refresh(force: force)
    }

    func refresh(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isRefreshing else {
            completion?(false)
            return
        }
        isRefreshing = true
        var request = URLRequest(url: Self.manifestURL, timeoutInterval: 15)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshing = false
                defer { completion?(self.health == .ok || self.health == .updateAvailable) }
                guard error == nil,
                      let data = data,
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    if self.manifestVersion == 0 { self.health = .offline }
                    NotificationCenter.default.post(name: .filterStatusChanged, object: nil)
                    return
                }
                self.applyManifest(json, rawData: data, fromRemote: true)
                self.defaults.set(Date().timeIntervalSince1970, forKey: "filters.lastCheck")
            }
        }.resume()
    }

    // MARK: - Load / apply

    private func loadFromCacheOrBundle() {
        if let data = try? Data(contentsOf: cacheURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            applyManifest(json, rawData: data, fromRemote: false)
            health = .ok
            return
        }
        if let url = Bundle.main.url(forResource: "DefaultFilterManifest", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            applyManifest(json, rawData: data, fromRemote: false)
            health = .offline
            return
        }
        applyBundledDefaults()
        health = .offline
    }

    private func applyBundledDefaults() {
        manifestVersion = 1
        remoteAllowsYouTubeAdShield = true
        youtubeAdShieldScript = ""
        shortsCSSSelectors = Self.sanitizedShortsSelectors(Self.defaultShortsSelectors)
        networkDomains = Self.defaultNetworkDomains
        cosmeticSelectors = Self.defaultCosmeticSelectors
    }

    private func applyManifest(_ json: [String: Any], rawData: Data, fromRemote: Bool) {
        let version = json["version"] as? Int ?? 1
        let previous = manifestVersion
        manifestVersion = version
        if let enabled = json["youtubeAdShieldEnabled"] as? Bool {
            remoteAllowsYouTubeAdShield = enabled
        }
        if let script = json["youtubeAdShieldScript"] as? String {
            youtubeAdShieldScript = script
        }
        if let selectors = json["shortsCSSSelectors"] as? [String], !selectors.isEmpty {
            shortsCSSSelectors = Self.sanitizedShortsSelectors(selectors)
        }
        if let domains = json["networkDomains"] as? [String], !domains.isEmpty {
            networkDomains = domains
        }
        if let cosmetics = json["cosmeticSelectors"] as? [String], !cosmetics.isEmpty {
            cosmeticSelectors = cosmetics
        }
        if fromRemote {
            try? rawData.write(to: cacheURL, options: .atomic)
            health = version > previous ? .updateAvailable : .ok
            // After applying a fresh remote config, treat as OK.
            if health == .updateAvailable { health = .ok }
            AdBlockManager.shared.invalidateCompiledLists()
            NotificationCenter.default.post(name: .filterManifestUpdated, object: nil)
        }
        NotificationCenter.default.post(name: .filterStatusChanged, object: nil)
    }

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(cacheFileName)
    }

    // MARK: - Bundled defaults

    /// Whole shelves / sections only — never bare `a[href*="/shorts/"]` (that punches holes in cards).
    static let defaultShortsSelectors: [String] = [
        "ytm-shorts-lockup-view-model",
        "ytm-shorts-lockup-view-model-host",
        "ytm-reel-shelf-renderer",
        "ytd-reel-shelf-renderer",
        "ytd-rich-shelf-renderer[is-shorts]",
        "ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts])",
        "ytm-reel-item-renderer",
        "#shorts-container",
        "ytd-shorts"
    ]

    /// Drop selectors that hide only inner links / attributes and leave empty feed shells.
    static func sanitizedShortsSelectors(_ selectors: [String]) -> [String] {
        let filtered = selectors.filter { raw in
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if s.hasPrefix("a[") { return false }
            if s == "[is-shorts]" || s.hasPrefix("[is-shorts]") { return false }
            return !s.isEmpty
        }
        return filtered.isEmpty ? defaultShortsSelectors : filtered
    }

    static let defaultNetworkDomains: [String] = [
        "pagead2.googlesyndication.com", "pagead.googlesyndication.com", "pagead1.googlesyndication.com",
        "googleads.g.doubleclick.net", "securepubads.g.doubleclick.net", "tpc.googlesyndication.com",
        "www.googleadservices.com", "partner.googleadservices.com", "adservice.google.com",
        "adservice.google.com.hk", "fundingchoicesmessages.google.com", "ad.doubleclick.net",
        "static.doubleclick.net", "adclick.g.doubleclick.net",
        "www.google-analytics.com", "ssl.google-analytics.com", "www.googletagmanager.com",
        "googletagmanager.com", "google-analytics.com", "region1.google-analytics.com",
        "connect.facebook.net", "www.facebook.com/tr", "pixel.facebook.com",
        "static.ads-twitter.com", "analytics.twitter.com", "ads-api.twitter.com",
        "bat.bing.com", "pixel.advertising.com", "ads.linkedin.com", "snap.licdn.com",
        "cdn.taboola.com", "trc.taboola.com", "cds.taboola.com",
        "widgets.outbrain.com", "log.outbrain.com",
        "ads.pubmatic.com", "image2.pubmatic.com",
        "acdn.adnxs.com", "ib.adnxs.com", "secure.adnxs.com",
        "cdn.adsafeprotected.com", "pixel.adsafeprotected.com",
        "ads.yahoo.com", "ups.analytics.yahoo.com",
        "c.amazon-adsystem.com", "aax.amazon-adsystem.com",
        "secure.flashtalking.com", "cdn.flashtalking.com",
        "script.crazyegg.com", "cdn.mouseflow.com",
        "static.hotjar.com", "script.hotjar.com",
        "cdn.segment.com", "api.segment.io",
        "cdn.mxpnl.com", "api.mixpanel.com",
        "js.appboycdn.com", "cdn.branch.io",
        "ads.mopub.com", "ads.inmobi.com",
        "pagead2.googleadservices.com", "ade.googlesyndication.com",
        "adserver.adtechus.com", "aka-cdn.adtechus.com",
        "bs.serving-sys.com", "ds.serving-sys.com",
        "ad.smaato.net", "sdk.starbolt.io",
        "ads.stickyadstv.com", "cdn.stickyadstv.com",
        "gum.criteo.com", "static.criteo.net", "bidder.criteo.com",
        "ep2.facebook.com", "an.facebook.com",
        "ads.reddit.com", "alb.reddit.com",
        "ads-twitter.com", "ads.pinterest.com",
        "log.pinterest.com", "ct.pinterest.com",
        "s0.2mdn.net", "ad.2mdn.net", "dt.adsafeprotected.com",
        "match.adsrvr.org", "insight.adsrvr.org",
        "dsum-sec.casalemedia.com", "js-sec.indexww.com",
        "securepubads.g.doubleclick.net",
        "pagead46.l.doubleclick.net", "cm.g.doubleclick.net",
        "stats.g.doubleclick.net", "adx.g.doubleclick.net"
    ]

    static let defaultCosmeticSelectors: [String] = [
        ".adsbygoogle",
        "ins.adsbygoogle",
        "iframe[id^=\"google_ads_iframe\"]",
        "div[id^=\"google_ads_iframe\"]",
        "div[id^=\"div-gpt-ad\"]",
        ".ad-container",
        ".ad-banner",
        ".ad-slot",
        ".adsbox",
        "#ad-container",
        "[data-ad-slot]",
        "[data-google-query-id]",
        ".dfp-ad",
        ".advertisement",
        ".sponsored-content",
        "aside.ad",
        "div[class*=\"ad-wrapper\"]",
        "div[class*=\"adWrapper\"]",
        "div[id*=\"taboola\"]",
        "div[class*=\"taboola\"]",
        "div[id*=\"outbrain\"]",
        "div[class*=\"OUTBRAIN\"]",
        ".commercial-unit",
        ".js-ad",
        "[aria-label=\"Ads\"]",
        "[aria-label=\"Advertisement\"]"
    ]
}

extension Notification.Name {
    static let filterStatusChanged = Notification.Name("mmbrowser.filters.status")
    static let filterManifestUpdated = Notification.Name("mmbrowser.filters.updated")
}
