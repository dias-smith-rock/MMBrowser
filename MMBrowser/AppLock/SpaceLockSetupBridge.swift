import Foundation

/// Keeps `AppLockSetupViewControllerDelegate` alive for the duration of a space-lock sheet.
final class SpaceLockSetupBridge: AppLockSetupViewControllerDelegate {
    private let onFinish: (Bool) -> Void

    init(onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
    }

    func appLockSetupDidFinish(_ controller: AppLockSetupViewController, success: Bool) {
        onFinish(success)
    }
}
