import AppTrackingTransparency
import UIKit

/// App Tracking Transparency (ATT) — requests permission to use the advertising identifier.
enum AppTrackingAuthorization {
    private static var didRequestThisSession = false

    /// Current ATT status (`notDetermined` until the system prompt is shown).
    static var status: ATTrackingManager.AuthorizationStatus {
        ATTrackingManager.trackingAuthorizationStatus
    }

    /// Shows the system ATT prompt once when status is still `notDetermined`.
    /// Call after the first interactive UI is on screen (e.g. `sceneDidBecomeActive`).
    static func requestIfNeeded(completion: ((ATTrackingManager.AuthorizationStatus) -> Void)? = nil) {
        guard #available(iOS 14, *) else {
            completion?(.authorized)
            return
        }
        let current = ATTrackingManager.trackingAuthorizationStatus
        guard current == .notDetermined else {
            completion?(current)
            return
        }
        guard !didRequestThisSession else {
            completion?(current)
            return
        }
        didRequestThisSession = true

        // ATT must run while the app is active; a short delay avoids racing the first layout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard UIApplication.shared.applicationState == .active else {
                didRequestThisSession = false
                completion?(ATTrackingManager.trackingAuthorizationStatus)
                return
            }
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    completion?(status)
                }
            }
        }
    }
}
