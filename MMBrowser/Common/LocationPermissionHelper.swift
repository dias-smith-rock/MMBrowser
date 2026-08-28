import CoreLocation
import UIKit

/// Requests When In Use location access for “Current Location” mode.
final class LocationPermissionHelper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationPermissionHelper()

    private let manager = CLLocationManager()
    private var pending: ((CLAuthorizationStatus) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// Call when the user selects Current Location.
    /// - notDetermined → system permission alert
    /// - denied/restricted → opens the app’s Settings page
    /// - authorized → no-op beyond callback
    func handleCurrentLocationSelection(
        from _: UIViewController,
        completion: @escaping (_ status: CLAuthorizationStatus) -> Void
    ) {
        switch authorizationStatus {
        case .notDetermined:
            pending = completion
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            openAppSettings()
            completion(authorizationStatus)
        case .authorizedAlways, .authorizedWhenInUse:
            completion(authorizationStatus)
        @unknown default:
            completion(authorizationStatus)
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        let callback = pending
        pending = nil
        callback?(status)
    }
}
