import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        window.rootViewController = BrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
        KeyboardDismissCoordinator.shared.attach(to: window)
        AppLockCoordinator.shared.attach(to: windowScene)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        AdLifecycleCoordinator.shared.startBootstrapIfNeeded(from: window.rootViewController)
    }

    @objc private func themeChanged() {
        window?.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        AdLifecycleCoordinator.shared.handleBecomeActive(root: window?.rootViewController)
    }

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppLockCoordinator.shared.applicationWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AdLifecycleCoordinator.shared.handleEnterBackground()
        AppLockCoordinator.shared.applicationDidEnterBackground()
        PasswordVaultGate.invalidate()
        // Persist tabs/containers before any exit cleanup so force-quit after
        // backgrounding still has a restore point when "close tabs on exit" is off.
        if let browser = window?.rootViewController as? BrowserViewController {
            browser.persistSessionForBackground()
        }
        AutoClearManager.performScheduledClear()
    }
}
