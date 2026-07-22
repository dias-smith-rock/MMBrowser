import Foundation

enum DangerousSiteGuard {
    /// Lightweight local blocklist for demo / basic phishing lookalikes.
    private static let blockedHosts: Set<String> = [
        "paypal.com.secure-login.tk",
        "appleid-verify-security.com",
        "microsoft-account-alert.ru",
        "google-secure-login.xyz",
        "bankofamerica-secure-update.com",
        "chase-confirm-login.net"
    ]

    static func isDangerous(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        if blockedHosts.contains(host) { return true }
        // Heuristic: many subdomain + keywords
        let suspicious = ["secure-login", "account-verify", "confirm-login", "update-security"]
        return suspicious.contains { host.contains($0) } && !host.hasSuffix(".google.com") && !host.hasSuffix("apple.com")
    }
}
