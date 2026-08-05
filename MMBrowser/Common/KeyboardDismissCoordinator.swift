import UIKit

/// Window-level tap: dismiss keyboard when the user taps outside any text input.
/// Does not cancel the underlying touch, so buttons / links / table rows still work.
final class KeyboardDismissCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissCoordinator()

    private weak var window: UIWindow?
    private var tapRecognizer: UITapGestureRecognizer?
    private var keyboardVisible = false

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    func attach(to window: UIWindow) {
        if let existing = tapRecognizer {
            existing.view?.removeGestureRecognizer(existing)
            tapRecognizer = nil
        }
        self.window = window
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        tapRecognizer = tap
    }

    @objc private func keyboardWillShow() { keyboardVisible = true }
    @objc private func keyboardWillHide() { keyboardVisible = false }

    @objc private func handleTap() {
        window?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard keyboardVisible else { return false }
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                return false
            }
            // Address-bar chrome (clear / shield / reload) must not dismiss the keyboard
            // before the button action runs — otherwise clear → re-focus restores the URL.
            if current is AddressBarView {
                return false
            }
            // Keep taps on the keyboard / input accessory from dismissing first.
            if String(describing: type(of: current)).contains("UIKeyboard") {
                return false
            }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
