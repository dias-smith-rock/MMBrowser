import Foundation
import FirebaseAnalytics

/// Single facade for product analytics (Firebase). DEBUG probes (PipProbe / XSiteProbe /
/// PageMediaProbe) stay console-only and must not call into this type.
enum AppAnalytics {

    // MARK: - Event names (snake_case, ≤40 chars)

    enum Event {
        static let appOpen = AnalyticsEventAppOpen
        static let screenView = AnalyticsEventScreenView

        static let tabOpen = "tab_open"
        static let tabClose = "tab_close"
        static let pageLoad = "page_load"
        static let navigationError = "navigation_error"
        static let search = "search"
        static let spaceSwitch = "space_switch"
        static let settingsToggle = "settings_toggle"
        static let defaultBrowserTap = "default_browser_tap"
        static let externalOpen = "external_open"
        static let onboardingComplete = "onboarding_complete"
        static let tipShown = "tip_shown"
        static let bookmarkAdd = "bookmark_add"
        static let downloadStart = "download_start"
        static let clearData = "clear_data"
        static let pipEnter = "pip_enter"
        static let pipResult = "pip_result"
        static let consentResult = "consent_result"
        static let attResult = "att_result"
        static let adTrigger = "ad_trigger"
        static let adImpression = "ad_impression_custom"
        static let adClick = "ad_click_custom"

        static let paywallShow = "paywall_show"
        static let purchaseStart = "purchase_start"
        static let purchaseSuccess = "purchase_success"
        static let purchaseFail = "purchase_fail"
        static let restore = "restore"
    }

    // MARK: - Parameter keys

    enum Param {
        static let source = "source"
        static let host = "host"
        static let pathBucket = "path_bucket"
        static let scheme = "scheme"
        static let incognito = "incognito"
        static let engine = "engine"
        static let spaceName = "space_name"
        static let setting = "setting"
        static let enabled = "enabled"
        static let value = "value"
        static let format = "format"
        static let kind = "kind"
        static let tipID = "tip_id"
        static let success = "success"
        static let reason = "reason"
        static let errorDomain = "error_domain"
        static let errorCode = "error_code"
        static let canRequestAds = "can_request_ads"
        static let status = "status"
        static let tabCount = "tab_count"
        static let mediaKind = "media_kind"
        static let productID = "product_id"
    }

    // MARK: - Core helpers

    static func logAppOpen() {
        log(Event.appOpen, parameters: nil)
    }

    static func logScreen(_ name: String, class className: String? = nil) {
        var params: [String: Any] = [AnalyticsParameterScreenName: sanitize(name, limit: 100)]
        if let className {
            params[AnalyticsParameterScreenClass] = sanitize(className, limit: 100)
        }
        log(Event.screenView, parameters: params)
    }

    /// Generic escape hatch — prefer typed helpers below.
    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        log(name, parameters: parameters)
    }

    // MARK: - Browser journeys

    static func logTabOpen(source: String, incognito: Bool, tabCount: Int) {
        log(Event.tabOpen, parameters: [
            Param.source: sanitize(source),
            Param.incognito: incognito,
            Param.tabCount: min(tabCount, 100)
        ])
    }

    static func logTabClose(source: String, incognito: Bool, tabCount: Int) {
        log(Event.tabClose, parameters: [
            Param.source: sanitize(source),
            Param.incognito: incognito,
            Param.tabCount: min(tabCount, 100)
        ])
    }

    /// Throttled page load — host + coarse path only (no query / fragments).
    static func logPageLoad(url: URL?, incognito: Bool, source: String = "webview") {
        guard let url else { return }
        let host = privacyHost(url)
        let key = "page_load|\(host)|\(incognito)"
        guard Throttle.allow(key, interval: 2.0) else { return }
        var params: [String: Any] = [
            Param.host: host,
            Param.incognito: incognito,
            Param.source: sanitize(source),
            Param.scheme: sanitize(url.scheme ?? "unknown", limit: 16)
        ]
        if let bucket = privacyPathBucket(url) {
            params[Param.pathBucket] = bucket
        }
        log(Event.pageLoad, parameters: params)
    }

    static func logNavigationError(url: URL?, domain: String, code: Int) {
        let host = privacyHost(url)
        let key = "nav_err|\(host)|\(domain)|\(code)"
        guard Throttle.allow(key, interval: 5.0) else { return }
        log(Event.navigationError, parameters: [
            Param.host: host,
            Param.errorDomain: sanitize(domain, limit: 40),
            Param.errorCode: code
        ])
    }

    /// Search query text is never logged — only the engine id.
    static func logSearch(engineID: String, source: String = "address_bar") {
        log(Event.search, parameters: [
            Param.engine: sanitize(engineID),
            Param.source: sanitize(source)
        ])
    }

    static func logSpaceSwitch(spaceName: String, source: String) {
        log(Event.spaceSwitch, parameters: [
            Param.spaceName: sanitize(spaceName),
            Param.source: sanitize(source)
        ])
    }

    /// Back-compat wrapper used by older call sites.
    static func logAccountSwitch(accountName: String) {
        logSpaceSwitch(spaceName: accountName, source: "chip")
    }

    static func logSettingsToggle(setting: String, enabled: Bool) {
        log(Event.settingsToggle, parameters: [
            Param.setting: sanitize(setting),
            Param.enabled: enabled
        ])
    }

    static func logSettingsChange(setting: String, value: String) {
        log(Event.settingsToggle, parameters: [
            Param.setting: sanitize(setting),
            Param.value: sanitize(value)
        ])
    }

    static func logDefaultBrowserTap(source: String) {
        log(Event.defaultBrowserTap, parameters: [
            Param.source: sanitize(source)
        ])
    }

    static func logExternalOpen(url: URL?) {
        log(Event.externalOpen, parameters: [
            Param.host: privacyHost(url),
            Param.scheme: sanitize(url?.scheme ?? "unknown", limit: 16)
        ])
    }

    static func logOnboardingComplete() {
        log(Event.onboardingComplete, parameters: nil)
    }

    static func logTipShown(tipID: String) {
        log(Event.tipShown, parameters: [
            Param.tipID: sanitize(tipID)
        ])
    }

    static func logBookmarkAdd(host: String?) {
        log(Event.bookmarkAdd, parameters: [
            Param.host: sanitize(host ?? "unknown")
        ])
    }

    static func logDownloadStart(mediaKind: String, host: String?) {
        log(Event.downloadStart, parameters: [
            Param.mediaKind: sanitize(mediaKind),
            Param.host: sanitize(host ?? "unknown")
        ])
    }

    static func logClearData(kinds: [String]) {
        log(Event.clearData, parameters: [
            Param.kind: sanitize(kinds.sorted().joined(separator: ","), limit: 100)
        ])
    }

    static func logPipEnter(source: String, host: String?) {
        log(Event.pipEnter, parameters: [
            Param.source: sanitize(source),
            Param.host: sanitize(host ?? "unknown")
        ])
    }

    static func logPipResult(source: String, success: Bool, host: String?, reason: String? = nil) {
        var params: [String: Any] = [
            Param.source: sanitize(source),
            Param.success: success,
            Param.host: sanitize(host ?? "unknown")
        ]
        if let reason {
            params[Param.reason] = sanitize(reason)
        }
        log(Event.pipResult, parameters: params)
    }

    static func logConsentResult(canRequestAds: Bool) {
        log(Event.consentResult, parameters: [
            Param.canRequestAds: canRequestAds
        ])
    }

    static func logATTResult(status: String) {
        log(Event.attResult, parameters: [
            Param.status: sanitize(status)
        ])
    }

    static func logAdTrigger(source: String, kind: String) {
        log(Event.adTrigger, parameters: [
            Param.source: sanitize(source),
            Param.kind: sanitize(kind)
        ])
    }

    static func logAdImpression(format: String) {
        log(Event.adImpression, parameters: [
            Param.format: sanitize(format)
        ])
    }

    static func logAdClick(format: String) {
        log(Event.adClick, parameters: [
            Param.format: sanitize(format)
        ])
    }

    static func logPaywallShow(source: String) {
        log(Event.paywallShow, parameters: [
            Param.source: sanitize(source)
        ])
    }

    static func logPurchaseStart(productID: String, source: String) {
        log(Event.purchaseStart, parameters: [
            Param.productID: sanitize(productID),
            Param.source: sanitize(source)
        ])
    }

    static func logPurchaseSuccess(productID: String, source: String) {
        log(Event.purchaseSuccess, parameters: [
            Param.productID: sanitize(productID),
            Param.source: sanitize(source)
        ])
    }

    static func logPurchaseFail(productID: String, source: String, reason: String) {
        log(Event.purchaseFail, parameters: [
            Param.productID: sanitize(productID),
            Param.source: sanitize(source),
            Param.reason: sanitize(reason)
        ])
    }

    static func logRestore(success: Bool, source: String) {
        log(Event.restore, parameters: [
            Param.success: success,
            Param.source: sanitize(source)
        ])
    }

    // MARK: - Privacy / sanitization

    /// Host only; strips leading `www.`. Never returns query or userinfo.
    static func privacyHost(_ url: URL?) -> String {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return "unknown" }
        if host.hasPrefix("www.") {
            return sanitize(String(host.dropFirst(4)))
        }
        return sanitize(host)
    }

    /// Coarse first path segment for high-traffic sites (e.g. `/watch`, `/shorts`).
    static func privacyPathBucket(_ url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        guard !path.isEmpty, path != "/" else { return nil }

        if host.contains("youtube.com") || host == "youtu.be" {
            if path.hasPrefix("/watch") { return "watch" }
            if path.hasPrefix("/shorts") { return "shorts" }
            if path.hasPrefix("/results") { return "results" }
            if path.hasPrefix("/channel") || path.hasPrefix("/@") { return "channel" }
            if path.hasPrefix("/playlist") { return "playlist" }
            return "other"
        }
        if host == "x.com" || host.hasSuffix(".x.com") || host.contains("twitter.com") {
            if path.hasPrefix("/i/") { return "i" }
            if path.hasPrefix("/search") { return "search" }
            if path.hasPrefix("/home") { return "home" }
            if path.split(separator: "/").count == 1 { return "profile" }
            return "other"
        }
        // Generic: first segment only (no ids beyond a short allowlist).
        let segment = path.split(separator: "/").first.map(String.init) ?? ""
        guard !segment.isEmpty, segment.count <= 24, !segment.contains("@") else { return "other" }
        if segment.allSatisfy({ $0.isNumber || $0 == "-" }) { return "id" }
        return sanitize(segment, limit: 24)
    }

    // MARK: - Internals

    private static func log(_ name: String, parameters: [String: Any]?) {
        guard Gate.isReady else { return }
        let trimmedName = String(name.prefix(40))
        guard let parameters else {
            Analytics.logEvent(trimmedName, parameters: nil)
            return
        }
        var safe: [String: Any] = [:]
        safe.reserveCapacity(min(parameters.count, 25))
        for (key, value) in parameters {
            guard safe.count < 25 else { break }
            let k = String(key.prefix(40))
            switch value {
            case let s as String:
                safe[k] = String(s.prefix(100))
            case let b as Bool:
                safe[k] = b
            case let i as Int:
                safe[k] = i
            case let i64 as Int64:
                safe[k] = i64
            case let d as Double:
                safe[k] = d
            case let n as NSNumber:
                safe[k] = n
            default:
                safe[k] = String(describing: value).prefix(100)
            }
        }
        Analytics.logEvent(trimmedName, parameters: safe)
    }

    private static func sanitize(_ value: String, limit: Int = 40) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        return String(trimmed.prefix(limit))
    }

    private enum Gate {
        static var isReady: Bool {
            FirebaseBootstrap.isConfigured
        }
    }

    /// In-process debounce for high-churn events (SPA redirects, error storms).
    private enum Throttle {
        private static var lastFire: [String: CFAbsoluteTime] = [:]
        private static let lock = NSLock()

        static func allow(_ key: String, interval: CFAbsoluteTime) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let now = CFAbsoluteTimeGetCurrent()
            if let previous = lastFire[key], now - previous < interval {
                return false
            }
            lastFire[key] = now
            // Bound memory for long sessions.
            if lastFire.count > 200 {
                let cutoff = now - 60
                lastFire = lastFire.filter { $0.value >= cutoff }
            }
            return true
        }
    }
}
