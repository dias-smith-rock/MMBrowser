import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    /// Links received before the browser UI is ready (cold start).
    private var pendingIncomingURLs: [URL] = []

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

        let launchURLs = connectionOptions.urlContexts.map(\.url)
        if !launchURLs.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.openIncomingURLs(launchURLs)
            }
        }
    }

    @objc private func themeChanged() {
        window?.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        openIncomingURLs(URLContexts.map(\.url))
    }

    private func openIncomingURLs(_ urls: [URL]) {
        let webURLs = urls.filter { url in
            let scheme = url.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }
        guard !webURLs.isEmpty else { return }

        guard let browser = window?.rootViewController as? BrowserViewController else {
            pendingIncomingURLs.append(contentsOf: webURLs)
            return
        }

        // Defer until after the current run-loop so tab chrome is laid out.
        DispatchQueue.main.async { [weak self, weak browser] in
            guard let self, let browser else { return }
            for url in webURLs {
                browser.handleIncomingURL(url)
            }
            if !self.pendingIncomingURLs.isEmpty {
                let pending = self.pendingIncomingURLs
                self.pendingIncomingURLs.removeAll()
                for url in pending {
                    browser.handleIncomingURL(url)
                }
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        AdLifecycleCoordinator.shared.handleBecomeActive(root: window?.rootViewController)
        if !pendingIncomingURLs.isEmpty,
           let browser = window?.rootViewController as? BrowserViewController {
            let pending = pendingIncomingURLs
            pendingIncomingURLs.removeAll()
            for url in pending {
                browser.handleIncomingURL(url)
            }
        }
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
