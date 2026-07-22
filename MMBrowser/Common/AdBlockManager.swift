import Foundation
import WebKit

final class AdBlockManager {
    static let shared = AdBlockManager()

    private let ruleListID = "MMBrowserAdSenseBlock"
    private var cachedList: WKContentRuleList?
    private var isCompiling = false
    private var waiters: [(WKContentRuleList?) -> Void] = []

    var isEnabled: Bool {
        get { AppSettings.trackerProtectionEnabled }
        set { AppSettings.trackerProtectionEnabled = newValue }
    }

    private init() {}

    func prepare() {
        guard isEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.resolveRuleList { _ in }
        }
    }

    func apply(to configuration: WKWebViewConfiguration, completion: @escaping () -> Void) {
        let finish: (WKContentRuleList?) -> Void = { list in
            if let list = list {
                configuration.userContentController.add(list)
            }
            completion()
        }
        guard isEnabled else {
            DispatchQueue.main.async { finish(nil) }
            return
        }
        DispatchQueue.main.async {
            self.resolveRuleList(completion: finish)
        }
    }

    private func resolveRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let cached = cachedList {
            completion(cached)
            return
        }
        waiters.append(completion)
        guard !isCompiling else { return }
        isCompiling = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: ruleListID,
            encodedContentRuleList: Self.ruleJSON
        ) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("[AdBlock] compile failed: \(error.localizedDescription)")
                }
                self.cachedList = list
                self.isCompiling = false
                let pending = self.waiters
                self.waiters.removeAll()
                pending.forEach { $0(list) }
            }
        }
    }

    private static let ruleJSON: String = {
        let domains = [
            "pagead2.googlesyndication.com", "pagead.googlesyndication.com", "pagead1.googlesyndication.com",
            "googleads.g.doubleclick.net", "securepubads.g.doubleclick.net", "tpc.googlesyndication.com",
            "www.googleadservices.com", "partner.googleadservices.com", "adservice.google.com",
            "adservice.google.com.hk", "fundingchoicesmessages.google.com", "ad.doubleclick.net",
            "www.google-analytics.com", "ssl.google-analytics.com", "www.googletagmanager.com",
            "connect.facebook.net", "static.ads-twitter.com", "analytics.twitter.com",
            "bat.bing.com", "pixel.advertising.com"
        ]
        var rules: [[String: Any]] = domains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return [
                "trigger": ["url-filter": ".*\(escaped).*"],
                "action": ["type": "block"]
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": [
                "type": "css-display-none",
                "selector": ".adsbygoogle, ins.adsbygoogle, iframe[id^=\"google_ads_iframe\"], div[id^=\"google_ads_iframe\"]"
            ]
        ])
        let data = try! JSONSerialization.data(withJSONObject: rules, options: [])
        return String(data: data, encoding: .utf8)!
    }()
}
