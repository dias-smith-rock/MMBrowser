import UIKit
import ObjectiveC

/// Entry gate + short vault session for Passwords.
enum PasswordVaultGate {
    private static var unlockedUntil: Date?
    private static let sessionDuration: TimeInterval = 300

    static var isSessionActive: Bool {
        guard let until = unlockedUntil else { return false }
        return until > Date()
    }

    static func markUnlocked() {
        unlockedUntil = Date().addingTimeInterval(sessionDuration)
    }

    static func invalidate() {
        unlockedUntil = nil
        VaultCrypto.setSessionMasterKey(nil)
    }

    static func unlockIfNeeded(from presenter: UIViewController, completion: @escaping (Bool) -> Void) {
        if isSessionActive, VaultCrypto.isMasterUnlocked {
            completion(true)
            return
        }

        let afterOwnerAuth: () -> Void = {
            ensureMasterUnlocked(from: presenter) { ok in
                if ok { markUnlocked() }
                completion(ok)
            }
        }

        if isSessionActive {
            afterOwnerAuth()
            return
        }

        if AppLockSettings.isEnabled, AppLockSettings.primaryMethod != .none {
            let setup = AppLockSetupViewController(mode: .verifyThen(action: .unlockVault))
            // Setup VC dismisses itself in finish/cancel; only handle the result here.
            let box = UnlockDelegateBox { success in
                if success {
                    afterOwnerAuth()
                } else {
                    completion(false)
                }
            }
            setup.delegate = box
            objc_setAssociatedObject(setup, &AssociatedKeys.box, box, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            setup.modalPresentationStyle = .fullScreen
            presenter.present(setup, animated: true)
        } else {
            AppLockBiometrics.authenticateDeviceOwner(reason: "Unlock Passwords") { success, _ in
                if success {
                    afterOwnerAuth()
                } else {
                    completion(false)
                }
            }
        }
    }

    private static func ensureMasterUnlocked(from presenter: UIViewController, completion: @escaping (Bool) -> Void) {
        guard VaultCrypto.hasMasterPassword else {
            VaultCrypto.setSessionMasterKey(nil)
            completion(true)
            return
        }
        if VaultCrypto.isMasterUnlocked, VaultCrypto.activeKey() != nil {
            completion(true)
            return
        }

        let alert = UIAlertController(title: "Master Password", message: "Enter your master password to open the vault.", preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "Master password"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Unlock", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            if let key = VaultCrypto.unlockMasterPassword(text) {
                VaultCrypto.setSessionMasterKey(key)
                completion(true)
            } else {
                Toast.show("Incorrect master password", from: presenter)
                completion(false)
            }
        })
        presenter.present(alert, animated: true)
    }

    private enum AssociatedKeys {
        static var box: UInt8 = 0
    }
}

private final class UnlockDelegateBox: AppLockSetupViewControllerDelegate {
    private let handler: (Bool) -> Void
    init(handler: @escaping (Bool) -> Void) { self.handler = handler }
    func appLockSetupDidFinish(_ controller: AppLockSetupViewController, success: Bool) {
        handler(success)
    }
}
