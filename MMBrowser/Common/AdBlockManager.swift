import Foundation
import WebKit

final class AdBlockManager {
    static let shared = AdBlockManager()
    static let blockCountHandlerName = "mmBlockCount"

    private let networkRuleListID = "MMBrowserAdNetworkBlock"
    private let cosmeticRuleListID = "MMBrowserAdCosmeticBlock"
    private var cachedNetworkList: WKContentRuleList?
    private var cachedCosmeticList: WKContentRuleList?
    private var isCompiling = false
    private var waiters: [(WKContentRuleList?, WKContentRuleList?) -> Void] = []
    private var compiledFingerprint: String = ""

    var isEnabled: Bool {
        get { AppSettings.trackerProtectionEnabled }
        set { AppSettings.trackerProtectionEnabled = newValue }
    }

    private init() {}

    func prepare() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Always warm the compiled lists when tracker protection is on so the first
            // WebView can attach them synchronously and start loading without waiting.
            guard self.isEnabled else { return }
            self.resolveRuleLists { _, _ in }
        }
    }

    func invalidateCompiledLists() {
        cachedNetworkList = nil
        cachedCosmeticList = nil
        compiledFingerprint = ""
        guard let store = WKContentRuleListStore.default() else {
            prepare()
            return
        }
        store.removeContentRuleList(forIdentifier: networkRuleListID) { _ in }
        store.removeContentRuleList(forIdentifier: cosmeticRuleListID) { _ in }
        prepare()
    }

    /// Attach rule lists without blocking WebView creation.
    /// Uses cache immediately when warm; otherwise starts compile and adds lists when ready
    /// (applies to in-flight / subsequent resource loads on the same configuration).
    func apply(to configuration: WKWebViewConfiguration, completion: @escaping () -> Void) {
        let ucc = configuration.userContentController
        let attachScriptsIfNeeded = {
            if AppSettings.trackerProtectionEnabled, AppSettings.accurateBlockCountEnabled {
                ucc.addUserScript(Self.blockCountUserScript)
            }
        }
        let attachLists: (WKContentRuleList?, WKContentRuleList?) -> Void = { network, cosmetic in
            if let network { ucc.add(network) }
            if let cosmetic { ucc.add(cosmetic) }
        }

        let run: () -> Void = {
            guard self.isEnabled else {
                completion()
                return
            }
            let fingerprint = self.currentFingerprint()
            if let n = self.cachedNetworkList, let c = self.cachedCosmeticList, fingerprint == self.compiledFingerprint {
                attachLists(n, c)
                attachScriptsIfNeeded()
                completion()
                return
            }
            // Do not wait for compile — create the WebView and start navigation now.
            completion()
            self.resolveRuleLists { network, cosmetic in
                attachLists(network, cosmetic)
                attachScriptsIfNeeded()
            }
        }
        if Thread.isMainThread {
            run()
        } else {
            DispatchQueue.main.async(execute: run)
        }
    }

    /// Hot-swap content rule lists on live WebViews (AdBlock + Image Block) without destroying them.
    func refreshContentRuleLists(on webViews: [WKWebView], completion: @escaping () -> Void) {
        let finishApply: (WKContentRuleList?, WKContentRuleList?, WKContentRuleList?) -> Void = { network, cosmetic, image in
            for webView in webViews {
                let ucc = webView.configuration.userContentController
                ucc.removeAllContentRuleLists()
                if let network { ucc.add(network) }
                if let cosmetic { ucc.add(cosmetic) }
                if let image { ucc.add(image) }
            }
            completion()
        }
        DispatchQueue.main.async {
            let withImage: (WKContentRuleList?, WKContentRuleList?) -> Void = { network, cosmetic in
                ImageBlockManager.shared.currentRuleList { image in
                    finishApply(network, cosmetic, image)
                }
            }
            if AppSettings.trackerProtectionEnabled {
                self.resolveRuleLists { network, cosmetic in
                    withImage(network, cosmetic)
                }
            } else {
                withImage(nil, nil)
            }
        }
    }

    private func resolveRuleLists(completion: @escaping (WKContentRuleList?, WKContentRuleList?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let fingerprint = currentFingerprint()
        if let n = cachedNetworkList, let c = cachedCosmeticList, fingerprint == compiledFingerprint {
            completion(n, c)
            return
        }
        waiters.append(completion)
        guard !isCompiling else { return }
        isCompiling = true
        compiledFingerprint = fingerprint

        let networkJSON = Self.encodeRules(Self.networkRules())
        let cosmeticJSON = Self.encodeRules(Self.cosmeticRules())

        guard let store = WKContentRuleListStore.default() else {
            isCompiling = false
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0(nil, nil) }
            return
        }
        store.compileContentRuleList(forIdentifier: networkRuleListID, encodedContentRuleList: networkJSON) { [weak self] networkList, networkError in
            if let networkError = networkError {
                print("[AdBlock] network compile failed: \(networkError.localizedDescription)")
            }
            store.compileContentRuleList(forIdentifier: self?.cosmeticRuleListID ?? "MMBrowserAdCosmeticBlock", encodedContentRuleList: cosmeticJSON) { cosmeticList, cosmeticError in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let cosmeticError = cosmeticError {
                        print("[AdBlock] cosmetic compile failed: \(cosmeticError.localizedDescription)")
                    }
                    self.cachedNetworkList = networkList
                    self.cachedCosmeticList = cosmeticList
                    self.isCompiling = false
                    let pending = self.waiters
                    self.waiters.removeAll()
                    pending.forEach { $0(networkList, cosmeticList) }
                }
            }
        }
    }

    private func currentFingerprint() -> String {
        let f = FilterUpdateManager.shared
        // v2: unless-domain exceptions for Twitter/X first-party consent requests.
        return "v2-\(f.manifestVersion)-\(f.networkDomains.count)-\(f.cosmeticSelectors.count)"
    }

    private static func networkRules() -> [[String: Any]] {
        FilterUpdateManager.shared.networkDomains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            var trigger: [String: Any] = ["url-filter": ".*\(escaped).*"]
            // On X/Twitter pages, allow first-party analytics used by the cookie consent flow.
            let lowered = domain.lowercased()
            if lowered.contains("twitter") || lowered.contains("t.co") {
                trigger["unless-domain"] = ["*x.com", "*twitter.com", "*t.co", "*twimg.com"]
            }
            return [
                "trigger": trigger,
                "action": ["type": "block"]
            ]
        }
    }

    private static func cosmeticRules() -> [[String: Any]] {
        let selectors = FilterUpdateManager.shared.cosmeticSelectors
        // WKContentRuleList has practical selector length limits — chunk.
        var rules: [[String: Any]] = []
        let chunkSize = 40
        var i = 0
        while i < selectors.count {
            let end = min(i + chunkSize, selectors.count)
            let chunk = Array(selectors[i..<end]).joined(separator: ", ")
            rules.append([
                "trigger": ["url-filter": ".*"] as [String: Any],
                "action": [
                    "type": "css-display-none",
                    "selector": chunk
                ] as [String: Any]
            ])
            i = end
        }
        return rules
    }

    private static func encodeRules(_ rules: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: rules, options: [])
        return String(data: data, encoding: .utf8)!
    }

    /// Counts cosmetic ad nodes for the shield badge. Debounced; main frame only.
    private static var blockCountUserScript: WKUserScript {
        let selectors = FilterUpdateManager.shared.cosmeticSelectors
        let json = (try? JSONSerialization.data(withJSONObject: selectors, options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let source = """
        (function() {
          if (window.__mmBlockCountInstalled) return;
          window.__mmBlockCountInstalled = true;
          var SELECTORS = \(json);
          var last = -1;
          var pending = null;
          function countNow() {
            var n = 0;
            try {
              for (var i = 0; i < SELECTORS.length; i++) {
                try { n += document.querySelectorAll(SELECTORS[i]).length; } catch (e) {}
              }
            } catch (e) {}
            if (n !== last) {
              last = n;
              try {
                if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.mmBlockCount) {
                  webkit.messageHandlers.mmBlockCount.postMessage({ count: n });
                }
              } catch (e) {}
            }
          }
          function scheduleCount() {
            if (pending) return;
            pending = setTimeout(function() {
              pending = null;
              countNow();
            }, 750);
          }
          document.addEventListener('DOMContentLoaded', scheduleCount, { once: true });
          setInterval(scheduleCount, 5000);
          try {
            new MutationObserver(scheduleCount).observe(document.documentElement, { childList: true, subtree: true });
          } catch (e) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}
