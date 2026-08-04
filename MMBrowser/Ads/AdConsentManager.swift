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

        return canRequestAds
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
