import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    /// Links received before the browser UI is ready (cold start).
    private var pendingIncomingURLs: [URL] = []

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        configureWindowSceneSizing(windowScene)
        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        window.rootViewController = BrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
        KeyboardDismissCoordinator.shared.attach(to: window)
        AppLockCoordinator.shared.attach(to: windowScene)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
        Task { await PremiumStore.shared.refresh() }

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

    /// Prefer compact window controls so top-leading chrome (Settings) is not covered on iPadOS 26+.
    @available(iOS 26.0, *)
    func preferredWindowingControlStyle(for windowScene: UIWindowScene) -> UIWindowScene.WindowingControlStyle {
        .minimal
    }

    private func configureWindowSceneSizing(_ windowScene: UIWindowScene) {
        if let restrictions = windowScene.sizeRestrictions {
            if PlatformSupport.isMacInterface {
                restrictions.minimumSize = CGSize(width: 900, height: 600)
            } else if UIDevice.current.userInterfaceIdiom == .pad {
                // Prefer a large window when iPadOS windowing is enabled (system may clamp).
                let screen = windowScene.screen.bounds.size
                restrictions.minimumSize = CGSize(
                    width: max(520, floor(screen.width * 0.72)),
                    height: max(640, floor(screen.height * 0.72))
                )
            }
            restrictions.maximumSize = CGSize(width: 10_000, height: 10_000)
        }
        #if targetEnvironment(macCatalyst)
        guard PlatformSupport.isMacInterface else { return }
        let preferred = PlatformSupport.preferredMacWindowSize
        let frame = CGRect(origin: .zero, size: preferred)
        windowScene.requestGeometryUpdate(UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)) { _ in }
        #endif
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        openIncomingURLs(URLContexts.map(\.url))
    }

    private func openIncomingURLs(_ urls: [URL]) {
        let webURLs = urls.compactMap(Self.webURL(from:))
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
        if !pendingIncomingURLs.isEmpty,
           let browser = window?.rootViewController as? BrowserViewController {
            let pending = pendingIncomingURLs
            pendingIncomingURLs.removeAll()
            for url in pending {
                browser.handleIncomingURL(url)
            }
        }
        // ATT system prompt — requires active UI; only shows while status is notDetermined.
        AppTrackingAuthorization.requestIfNeeded()
    }

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppLockCoordinator.shared.applicationWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppLockCoordinator.shared.applicationDidEnterBackground()
        PasswordVaultGate.invalidate()
        SpaceLockStore.revokeAllUnlocks()
        // Persist tabs/containers before any exit cleanup so force-quit after
        // backgrounding still has a restore point when "close tabs on exit" is off.
        if let browser = window?.rootViewController as? BrowserViewController {
            browser.persistSessionForBackground()
        }
        AutoClearManager.performScheduledClear()
    }

    /// Maps an incoming URL to a browsable `http`/`https` URL.
    /// Supports direct web schemes (when default-browser entitlement is restored)
    /// and `xbrowser://open?url=` / `xbrowser:https://…` deep links.
    private static func webURL(from url: URL) -> URL? {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" {
            return url
        }
        guard scheme == "xbrowser" else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let nested = URL(string: queryURL),
           let nestedScheme = nested.scheme?.lowercased(),
           nestedScheme == "http" || nestedScheme == "https" {
            return nested
        }

        // xbrowser:https://example.com  or  xbrowser://https://example.com
        var residual = url.absoluteString
        if residual.lowercased().hasPrefix("xbrowser:") {
            residual = String(residual.dropFirst("xbrowser:".count))
        }
        while residual.hasPrefix("/") { residual = String(residual.dropFirst()) }
        guard let nested = URL(string: residual),
              let nestedScheme = nested.scheme?.lowercased(),
              nestedScheme == "http" || nestedScheme == "https" else {
            return nil
        }
        return nested
    }
}
