import StoreKit
import UIKit

/// System App Store rating prompt (`AppStore.requestReview`).
/// Apple may ignore the call (roughly ≤3 displays / year); we only ask after a calm “aha” moment.
enum AppReviewPrompt {
    private static let lastAskedKey = "review.prompt.lastAskedAt"
    private static let askCountKey = "review.prompt.askCount"
    private static let spaceSwitchCountKey = "review.engagement.spaceSwitchCount"

    /// Calendar days after first launch before we may ask.
    private static var minDaysSinceInstall: Double {
        #if DEBUG
        0
        #else
        2
        #endif
    }

    private static var cooldownDays: Double {
        #if DEBUG
        1
        #else
        90
        #endif
    }

    private static let maxAsks = 3
    private static let minSpaceSwitches = 3
    private static let minSpaces = 2
    private static let presentDelay: TimeInterval = 1.8

    // MARK: - Engagement

    static func recordSpaceSwitch() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: spaceSwitchCountKey) + 1, forKey: spaceSwitchCountKey)
    }

    // MARK: - Request

    /// Ask after a positive Spaces moment (switch / create / Split View), if gates pass.
    static func maybeRequest(
        from host: UIViewController,
        trigger: String,
        spaceCount: Int
    ) {
        guard isEligible(spaceCount: spaceCount) else { return }
        guard host.presentedViewController == nil else { return }
        guard host.view.window?.windowScene != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + presentDelay) { [weak host] in
            guard let host else { return }
            guard host.presentedViewController == nil else { return }
            guard let scene = host.view.window?.windowScene else { return }
            guard isEligible(spaceCount: spaceCount) else { return }

            markAsked()
            AppAnalytics.logReviewPrompt(trigger: trigger)
            AppStore.requestReview(in: scene)
        }
    }

    // MARK: - Gates

    private static func isEligible(spaceCount: Int) -> Bool {
        guard AppSettings.didShowFeatureHighlights else { return false }
        guard !PremiumPaywallGate.isFirstLaunchCalendarDay else { return false }

        let days = Date().timeIntervalSince(AppSettings.firstLaunchDate) / 86_400
        guard days >= minDaysSinceInstall else { return false }

        let switches = UserDefaults.standard.integer(forKey: spaceSwitchCountKey)
        let wowDone = UserDefaults.standard.bool(forKey: ContainerScope.didShowAccountWowKey)
        let engaged = spaceCount >= minSpaces && (switches >= minSpaceSwitches || wowDone)
        guard engaged else { return false }

        let asks = UserDefaults.standard.integer(forKey: askCountKey)
        guard asks < maxAsks else { return false }

        if let last = UserDefaults.standard.object(forKey: lastAskedKey) as? Date {
            let since = Date().timeIntervalSince(last) / 86_400
            guard since >= cooldownDays else { return false }
        }
        return true
    }

    private static func markAsked() {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: lastAskedKey)
        defaults.set(defaults.integer(forKey: askCountKey) + 1, forKey: askCountKey)
    }
}
