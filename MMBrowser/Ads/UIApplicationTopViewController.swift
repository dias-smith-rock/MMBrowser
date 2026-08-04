import UIKit

extension UIApplication {
    var mmb_topViewController: UIViewController? {
        let scene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let root = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        return root?.mmb_topMost
    }
}

extension UIViewController {
    var mmb_topMost: UIViewController {
        if let presented = presentedViewController {
            return presented.mmb_topMost
        }
        if let nav = self as? UINavigationController, let visible = nav.visibleViewController {
            return visible.mmb_topMost
        }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController {
            return selected.mmb_topMost
        }
        return self
    }
}
