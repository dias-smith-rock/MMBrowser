import AppTrackingTransparency
import UIKit
import UserMessagingPlatform

@MainActor
enum AdConsentManager {
    private static var hasStartedConsentThisSession = false

    static var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    static var isPrivacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// Runs UMP every launch. Returns whether ads may be requested afterward.
    @discardableResult
    static func gatherConsentIfNeeded(from viewController: UIViewController?) async -> Bool {
        guard AdMobConfig.adsEnabled else { return false }
        guard !hasStartedConsentThisSession else { return canRequestAds }
        hasStartedConsentThisSession = true

        let parameters = makeRequestParameters()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                #if DEBUG
                if let error {
                    print("[UMP] requestConsentInfoUpdate: \(error.localizedDescription)")
                }
                #endif
                cont.resume()
            }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ConsentForm.loadAndPresentIfRequired(from: viewController) { error in
                #if DEBUG
                if let error {
                    print("[UMP] loadAndPresentIfRequired: \(error.localizedDescription)")
                }
                #endif
                cont.resume()
            }
        }

        await requestTrackingAuthorizationIfNeeded(from: viewController)
        return canRequestAds
    }

    /// Apple ATT: required before using the advertising identifier for ads.
    /// Skips if UMP already presented ATT (status is no longer `.notDetermined`).
    static func requestTrackingAuthorizationIfNeeded(from viewController: UIViewController?) async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        if let viewController {
            await presentTrackingExplainer(from: viewController)
        }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            ATTrackingManager.requestTrackingAuthorization { _ in
                DispatchQueue.main.async { cont.resume() }
            }
        }
    }

    static var trackingAuthorizationSummary: String {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined: return "Not asked yet"
        case .restricted: return "Restricted"
        case .denied: return "Not allowed"
        case .authorized: return "Allowed"
        @unknown default: return "Unknown"
        }
    }

    private static func presentTrackingExplainer(from viewController: UIViewController) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(
                title: "This app uses tracking",
                message: "XBrowser shows ads. To measure those ads and show more relevant ones, the app may track your activity across other companies’ apps and websites using an advertising identifier.\n\nYou can Allow or Ask App Not to Track on the next screen.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                cont.resume()
            })
            if viewController.presentedViewController == nil {
                viewController.present(alert, animated: true)
            } else {
                cont.resume()
            }
        }
    }

    static func presentPrivacyOptions(from viewController: UIViewController?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ConsentForm.presentPrivacyOptionsForm(from: viewController) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    #if DEBUG
    static func resetForTesting() {
        ConsentInformation.shared.reset()
        hasStartedConsentThisSession = false
    }
    #endif

    private static func makeRequestParameters() -> RequestParameters {
        let parameters = RequestParameters()
        #if DEBUG
        let debugSettings = DebugSettings()
        // Uncomment and set the hash printed by UMP in Xcode logs when testing GDPR forms:
        // debugSettings.testDeviceIdentifiers = ["YOUR_TEST_DEVICE_HASH"]
        // debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif
        return parameters
    }
}
