import Foundation

/// Exactly one tab may own sticky / active PiP. Prevents YouTube + YouTube Music
/// WebViews from fighting over AVAudioSession (play fails, interruption spam).
enum PipSession {
    private(set) weak static var owner: WebViewController?

    static func isOwner(_ controller: WebViewController) -> Bool {
        owner === controller
    }

    /// Claim sticky PiP for this tab; previous owner yields immediately.
    static func claim(_ controller: WebViewController) {
        if owner === controller { return }
        let previous = owner
        owner = controller
        PipProbe.log("session.claim", [
            "host": controller.webView?.url?.host ?? "?",
            "prior": previous?.webView?.url?.host ?? "none"
        ])
        previous?.yieldPipOwnership(reason: "claimedByOtherTab")
    }

    static func releaseIfOwner(_ controller: WebViewController) {
        guard owner === controller else { return }
        owner = nil
        PipProbe.log("session.release", ["host": controller.webView?.url?.host ?? "?"])
    }

    /// Foreground tab started trusted playback — PiP owner must release audio.
    static func handleTrustedUserPlay(from controller: WebViewController) {
        guard let owner, owner !== controller else { return }
        PipProbe.log("session.userPlayTakeover", [
            "from": controller.webView?.url?.host ?? "?",
            "owner": owner.webView?.url?.host ?? "?"
        ])
        owner.yieldPipOwnership(reason: "otherTabUserPlay")
    }
}

/// Lightweight PiP diagnostics. Filter Xcode console with `[PipProbe]`.
enum PipProbe {
    static let dumpTabsNotification = Notification.Name("mmbrowser.pip.probe.dumpTabs")

    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "debug.pip.probe")
        #endif
    }

    /// Ask BrowserViewController to log every tab's PiP flags (cross-tab conflict analysis).
    static func requestTabDump(reason: String) {
        guard isEnabled else { return }
        NotificationCenter.default.post(
            name: dumpTabsNotification,
            object: nil,
            userInfo: ["reason": reason]
        )
    }

    static func log(_ event: String, _ fields: [String: Any] = [:]) {
        guard isEnabled else { return }
        var parts: [String] = ["[PipProbe]", event]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            parts.append("\(key)=\(stringify(value))")
        }
        print(parts.joined(separator: " "))
    }

    static func logJS(_ body: [String: Any]) {
        guard isEnabled else { return }
        let event = (body["event"] as? String) ?? "js"
        var fields = body
        fields.removeValue(forKey: "event")
        fields.removeValue(forKey: "diag")
        log("js.\(event)", fields)
    }

    private static func stringify(_ value: Any) -> String {
        switch value {
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        case let s as String:
            let trimmed = s.replacingOccurrences(of: "\n", with: " ")
            return trimmed.count > 120 ? String(trimmed.prefix(117)) + "..." : trimmed
        case let arr as [Any]:
            return "[\(arr.prefix(8).map(stringify).joined(separator: ","))]"
        case let dict as [String: Any]:
            let inner = dict.keys.sorted().compactMap { k -> String? in
                guard let v = dict[k] else { return nil }
                return "\(k):\(stringify(v))"
            }.joined(separator: ",")
            return "{\(inner)}"
        default:
            return String(describing: value)
        }
    }
}
