import GoogleMobileAds
import UIKit

/// UIKit lifecycle for cold App Open + hot interstitial ads.
@MainActor
final class AdLifecycleCoordinator {
    static let shared = AdLifecycleCoordinator()

    private enum Pending { case cold, hot }

    private var isColdStart = true
    private var wasInBackground = false
    private var pending: Pending?
    private var hasPresentedSinceForeground = false
    private var didBootstrapAds = false
    private var isBootstrapping = false
    private var didFinishLaunchConsent = false
    /// Set after first-run onboarding (and any sheet it presents) is no longer on screen.
    private var isHostReadyForConsent = false

    private init() {}

    /// Call once first-run onboarding has finished or was skipped.
    func noteHostReadyForConsent(from root: UIViewController?) {
        isHostReadyForConsent = true
        startBootstrapIfNeeded(from: root)
    }

    /// Call once the first window is interactive (SceneDelegate after makeKeyAndVisible).
    /// Consent and ATT wait until onboarding is gone so the two presentations do not overlap.
    func startBootstrapIfNeeded(from root: UIViewController?) {
        guard isHostReadyForConsent else { return }
        guard !didFinishLaunchConsent, !isBootstrapping else { return }
        isBootstrapping = true

        Task { @MainActor in
            // Let first frame render before consent / ATT UI.
            try? await Task.sleep(nanoseconds: 400_000_000)
            await waitUntilPresentationIdle(from: root)
            if AdMobConfig.adsEnabled {
                _ = await AdConsentManager.gatherConsentIfNeeded(from: root)
            } else {
                // Still disclose tracking (Analytics / later ads) via Apple's ATT prompt.
                await AdConsentManager.requestTrackingAuthorizationIfNeeded(from: root)
            }
            isBootstrapping = false
            didFinishLaunchConsent = true
            guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
            startMobileAdsSDK()
        }
    }

    /// Onboarding, the follow-up sheet, and their dismiss animations must finish first.
    private func waitUntilPresentationIdle(from root: UIViewController?) async {
        guard let root else { return }
        while isPresenting(root) {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func isPresenting(_ root: UIViewController) -> Bool {
        var current: UIViewController? = root
        while let viewController = current {
            if viewController.isBeingPresented || viewController.isBeingDismissed { return true }
            guard let presented = viewController.presentedViewController else { break }
            current = presented
        }
        return root.presentedViewController != nil
    }

    private func startMobileAdsSDK() {
        guard AdMobConfig.adsEnabled, AdConsentManager.canRequestAds else { return }
        guard !didBootstrapAds else { return }
        didBootstrapAds = true

        MobileAds.shared.start { _ in
            Task { @MainActor in
                AppOpenAdManager.shared.loadAd()
                HotStartAdManager.shared.loadAd()
            }
        }
    }

    func handleBecomeActive(root: UIViewController?) {
        guard AdMobConfig.adsEnabled else { return }
        if isColdStart {
            isColdStart = false
            pending = .cold
        } else if wasInBackground {
            wasInBackground = false
            pending = .hot
        }
        hasPresentedSinceForeground = false
        startBootstrapIfNeeded(from: root)
    }

    func handleEnterBackground() {
        wasInBackground = true
        pending = nil
        if AdConsentManager.canRequestAds {
            HotStartAdManager.shared.loadAd()
        }
    }

    /// Show pending ad after a meaningful user interaction (toolbar / navigation).
    func recordFirstInteraction(source: String) {
        guard AdMobConfig.adsEnabled else { return }
        guard AdConsentManager.canRequestAds, didBootstrapAds else { return }
        guard !hasPresentedSinceForeground, let pending else { return }
        self.pending = nil
        hasPresentedSinceForeground = true
        AppAnalytics.logEvent("ad_trigger", parameters: ["source": source, "kind": "\(pending)"])

        switch pending {
        case .cold:
            AppOpenAdManager.shared.showAdIfAvailable()
        case .hot:
            HotStartAdManager.shared.showAdIfAvailable()
        }
    }
}
