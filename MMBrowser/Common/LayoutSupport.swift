import UIKit

/// Layout helpers for resizable scenes (iPhone Duo fold/unfold, Split View, iPhone Mirroring).
/// Prefer the view / window size over `UIScreen.main` — Duo’s app size changes at runtime.
enum LayoutSupport {
    /// Display scale from the nearest trait environment, falling back to the main screen.
    static func displayScale(in view: UIView? = nil) -> CGFloat {
        if let scale = view?.traitCollection.displayScale, scale > 0 { return scale }
        if let scale = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.scale,
           scale > 0 {
            return scale
        }
        return UIScreen.main.scale
    }

    /// Available width for UI that must track the current window (not the physical screen).
    static func windowWidth(relativeTo view: UIView?) -> CGFloat {
        if let w = view?.window?.bounds.width, w > 1 { return w }
        if let w = view?.bounds.width, w > 1 { return w }
        if let w = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .coordinateSpace.bounds.width,
           w > 1 {
            return w
        }
        return 390
    }

    /// True when the available space is wide enough for a “regular width” (tablet-like) layout.
    /// Prefer this over `userInterfaceIdiom == .pad` — Duo’s inner display can be regular width.
    static func prefersRegularWidthLayout(in traits: UITraitCollection, bounds: CGSize) -> Bool {
        if PlatformSupport.isMacInterface { return true }
        if traits.horizontalSizeClass == .regular { return true }
        return bounds.width >= 600
    }

    /// Prefer left/right Split View when each pane can stay usable (~320pt+).
    /// Covers iPhone Duo unfolded, iPad, and wide landscape; phone portrait stays top/bottom.
    static func prefersSideBySideSplit(bounds: CGSize) -> Bool {
        bounds.width >= 640
    }

    /// Top chrome guide that clears iPadOS / macOS window controls (traffic lights).
    static func topChromeLayoutGuide(in view: UIView) -> UILayoutGuide {
        if #available(iOS 26.0, *) {
            return view.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        }
        return view.safeAreaLayoutGuide
    }
}
