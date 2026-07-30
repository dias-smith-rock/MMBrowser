import UIKit

final class AppLockCoordinator {
    static let shared = AppLockCoordinator()

    private weak var windowScene: UIWindowScene?
    private var lockWindow: UIWindow?
    private var privacyWindow: UIWindow?
    private var backgroundedAt: Date?
    private(set) var isLocked = false
    private var isPresentingPrompt = false

    private init() {}

    func attach(to scene: UIWindowScene) {
        windowScene = scene
        if AppLockSettings.isEnabled {
            lockNow(reason: "cold_start")
        }
    }

    func applicationDidEnterBackground() {
        backgroundedAt = Date()
        if AppLockSettings.isEnabled {
            showPrivacyCover()
        }
    }

    func applicationWillEnterForeground() {
        hidePrivacyCover()
        guard AppLockSettings.isEnabled else { return }

        let elapsed: TimeInterval
        if let backgroundedAt = backgroundedAt {
            elapsed = Date().timeIntervalSince(backgroundedAt)
        } else {
            elapsed = .greatestFiniteMagnitude
        }

        if elapsed >= AppLockSettings.gracePeriod.timeInterval {
            lockNow(reason: "foreground_after_grace")
        }
    }

    func lockNow(reason: String) {
        guard AppLockSettings.isEnabled else { return }
        guard !isLocked else {
            ensureLockWindowVisible()
            return
        }
        isLocked = true
        presentLockWindow()
    }

    func unlock() {
        isLocked = false
        dismissLockWindow()
        hidePrivacyCover()
    }

    func disableLockAndUnlock() {
        AppLockSecretStore.clearSecrets()
        AppLockSettings.clearAllFlags()
        unlock()
    }

    /// Called when a non-NTP webpage finishes loading.
    func noteWebpageFinished(url: URL?) {
        guard let url = url else { return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else { return }
        // Skip about:blank etc.
        guard url.host != nil else { return }

        if !AppLockSettings.hasSeenFirstWebpage {
            AppLockSettings.hasSeenFirstWebpage = true
        }

        guard AppLockSettings.shouldShowSetupPrompt else { return }
        DispatchQueue.main.async { [weak self] in
            self?.presentSetupPromptIfNeeded()
        }
    }

    private func presentSetupPromptIfNeeded() {
        guard AppLockSettings.shouldShowSetupPrompt, !isPresentingPrompt, !isLocked else { return }
        guard let root = windowScene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        isPresentingPrompt = true
        let prompt = AppLockPromptViewController()
        prompt.modalPresentationStyle = .pageSheet
        prompt.onFinished = { [weak self] in
            self?.isPresentingPrompt = false
        }
        top.present(prompt, animated: true)
    }

    // MARK: - Windows

    private func presentLockWindow() {
        guard let scene = windowScene else { return }
        let lock = AppLockViewController()
        lock.delegate = self
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = lock
        window.makeKeyAndVisible()
        lockWindow = window
    }

    private func ensureLockWindowVisible() {
        lockWindow?.makeKeyAndVisible()
    }

    private func dismissLockWindow() {
        lockWindow?.isHidden = true
        lockWindow = nil
        windowScene?.windows.first?.makeKeyAndVisible()
    }

    private func showPrivacyCover() {
        guard let scene = windowScene, privacyWindow == nil else { return }
        let cover = UIViewController()
        cover.view.backgroundColor = BrowserTheme.background
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        cover.view.addSubview(blur)
        blur.frame = cover.view.bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let label = UILabel()
        label.text = "MMBrowser"
        label.textColor = .white
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        cover.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: cover.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: cover.view.centerYAnchor)
        ])
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 2
        window.rootViewController = cover
        window.makeKeyAndVisible()
        privacyWindow = window
    }

    private func hidePrivacyCover() {
        privacyWindow?.isHidden = true
        privacyWindow = nil
        if isLocked {
            lockWindow?.makeKeyAndVisible()
        } else {
            windowScene?.windows.first?.makeKeyAndVisible()
        }
    }
}

extension AppLockCoordinator: AppLockViewControllerDelegate {
    func appLockDidUnlock(_ controller: AppLockViewController) {
        unlock()
    }

    func appLockDidDisableLock(_ controller: AppLockViewController) {
        disableLockAndUnlock()
    }
}
