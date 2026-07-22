import Foundation
import WebKit

/// Minimal AdSense blocker via WKContentRuleList. Enabled by default.
final class AdBlockManager {
    static let shared = AdBlockManager()

    private let enabledKey = "mmbrowser.adblock.enabled"
    private let ruleListID = "MMBrowserAdSenseBlock"
    private let queue = DispatchQueue(label: "mmbrowser.adblock")
    private var cachedList: WKContentRuleList?
    private var isCompiling = false
    private var waiters: [(WKContentRuleList?) -> Void] = []

    /// Defaults to `true` when the key has never been set.
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    private init() {}

    /// Warm up compilation early (e.g. at app launch).
    func prepare() {
        guard isEnabled else { return }
        resolveRuleList { _ in }
    }

    /// Attach compiled rules to a configuration's userContentController, then call `completion` on main.
    func apply(to configuration: WKWebViewConfiguration, completion: @escaping () -> Void) {
        guard isEnabled else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        resolveRuleList { list in
            if let list = list {
                configuration.userContentController.add(list)
            }
            completion()
        }
    }

    private func resolveRuleList(completion: @escaping (WKContentRuleList?) -> Void) {
        queue.async {
            if let cached = self.cachedList {
                DispatchQueue.main.async { completion(cached) }
                return
            }
            self.waiters.append(completion)
            guard !self.isCompiling else { return }
            self.isCompiling = true
            let json = Self.ruleJSON
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: self.ruleListID,
                encodedContentRuleList: json
            ) { [weak self] list, error in
                guard let self = self else { return }
                if let error = error {
                    print("[AdBlock] compile failed: \(error.localizedDescription)")
                }
                self.queue.async {
                    self.cachedList = list
                    self.isCompiling = false
                    let pending = self.waiters
                    self.waiters.removeAll()
                    DispatchQueue.main.async {
                        pending.forEach { $0(list) }
                    }
                }
            }
        }
    }

    /// Compact AdSense / DoubleClick block list + hide leftover slots.
    private static let ruleJSON: String = {
        let domains = [
            "pagead2.googlesyndication.com",
            "pagead.googlesyndication.com",
            "pagead1.googlesyndication.com",
            "googleads.g.doubleclick.net",
            "securepubads.g.doubleclick.net",
            "tpc.googlesyndication.com",
            "www.googleadservices.com",
            "partner.googleadservices.com",
            "adservice.google.com",
            "adservice.google.com.hk",
            "fundingchoicesmessages.google.com",
            "ad.doubleclick.net"
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
