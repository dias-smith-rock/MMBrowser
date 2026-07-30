import LocalAuthentication
import UIKit

enum AppLockBiometrics {
    enum Availability {
        case available(biometry: LABiometryType)
        case unavailable(reason: String)
    }

    static func availability() -> Availability {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if ok {
            return .available(biometry: context.biometryType)
        }
        let reason: String
        if let error = error {
            switch error.code {
            case LAError.biometryNotEnrolled.rawValue:
                reason = "No Face ID / Touch ID enrolled on this device"
            case LAError.biometryNotAvailable.rawValue:
                reason = "Biometrics not available on this device"
            case LAError.passcodeNotSet.rawValue:
                reason = "Device passcode is not set"
            default:
                reason = error.localizedDescription
            }
        } else {
            reason = "Biometrics unavailable"
        }
        return .unavailable(reason: reason)
    }

    static var biometryDisplayName: String {
        switch availability() {
        case .available(let type):
            switch type {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            default: return "Biometrics"
            }
        case .unavailable:
            return "Biometrics"
        }
    }

    static var systemImageName: String {
        switch availability() {
        case .available(let type):
            switch type {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            default: return "lock.fill"
            }
        case .unavailable:
            return "lock.fill"
        }
    }

    static func authenticate(reason: String, completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async {
                completion(false, error?.localizedDescription ?? "Biometrics unavailable")
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
            DispatchQueue.main.async {
                if success {
                    completion(true, nil)
                } else {
                    completion(false, evalError?.localizedDescription)
                }
            }
        }
    }
}
