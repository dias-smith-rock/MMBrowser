import UIKit

/// Presents the Premium paywall and gates Space creation.
@MainActor
enum PremiumCoordinator {
    private static var isPresentingColdStart = false

    static func presentPaywall(from presenter: UIViewController, source: String) {
        if presenter.presentedViewController is PremiumPaywallViewController { return }
        let top = topMost(from: presenter)
        if top is PremiumPaywallViewController { return }

        let paywall = PremiumPaywallViewController(source: source)
        paywall.modalPresentationStyle = .pageSheet
        if let sheet = paywall.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        paywall.overrideUserInterfaceStyle = .dark
        top.present(paywall, animated: true)
    }

    /// If under the free Space cap (or already Premium), runs `then`. Otherwise shows the paywall.
    static func ensureCanCreateSpace(
        from presenter: UIViewController,
        currentCount: Int,
        then: @escaping () -> Void
    ) {
        if PremiumStore.shared.canCreateSpace(currentCount: currentCount) {
            then()
            return
        }
        presentPaywall(from: presenter, source: "space_limit")
    }

    /// Cold start: at most once per calendar day for non-subscribers.
    static func presentColdStartIfNeeded(from root: UIViewController?) {
        guard let root else { return }
        guard !isPresentingColdStart else { return }
        guard PremiumPaywallGate.shouldAutoPresentColdStart() else { return }

        isPresentingColdStart = true
        Task { @MainActor in
            defer { isPresentingColdStart = false }
            await PremiumStore.shared.refresh()
            guard PremiumPaywallGate.shouldAutoPresentColdStart() else { return }
            // Let onboarding / consent / ads finish first.
            try? await Task.sleep(nanoseconds: 800_000_000)
            await waitUntilPresentationIdle(from: root)
            guard PremiumPaywallGate.shouldAutoPresentColdStart() else { return }
            guard root.presentedViewController == nil else { return }
            presentPaywall(from: root, source: "cold_start")
        }
    }

    private static func waitUntilPresentationIdle(from root: UIViewController) async {
        for _ in 0..<40 {
            if root.presentedViewController == nil { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private static func topMost(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }
}
