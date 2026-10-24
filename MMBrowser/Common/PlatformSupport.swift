import UIKit

/// Cross-platform helpers for iPhone / iPad / Mac Catalyst.
enum PlatformSupport {
    /// Running as a Mac Catalyst (or Designed for iPad on Mac) desktop session.
    static var isMacInterface: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        // "Designed for iPad" on Apple Silicon still reports as phone/pad idiom.
        if ProcessInfo.processInfo.isiOSAppOnMac { return true }
        return false
        #endif
    }

    static var supportsSystemPictureInPicture: Bool {
        #if targetEnvironment(macCatalyst)
        // System PiP APIs exist but behave poorly in many Catalyst builds — prefer in-window float.
        return false
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac { return false }
        return true
        #endif
    }

    static var supportsScreenBrightnessGestures: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return !ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    static var supportsHaptics: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return !ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    /// Preferred default window size when launching on Mac.
    static var preferredMacWindowSize: CGSize {
        CGSize(width: 1280, height: 840)
    }

    /// Configure popover anchoring required on Mac / iPad for action sheets & share sheets.
    static func configurePopover(
        _ controller: UIViewController,
        sourceView: UIView?,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil
    ) {
        guard let pop = controller.popoverPresentationController else { return }
        if let barButtonItem {
            pop.barButtonItem = barButtonItem
            return
        }
        guard let sourceView else { return }
        pop.sourceView = sourceView
        if let sourceRect {
            pop.sourceRect = sourceRect
        } else {
            pop.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 1, height: 1)
        }
        pop.permittedArrowDirections = []
    }
}

extension UIImpactFeedbackGenerator {
    /// No-op on Mac where haptics are unavailable / meaningless.
    func impactOccurredIfSupported() {
        guard PlatformSupport.supportsHaptics else { return }
        impactOccurred()
    }
}
