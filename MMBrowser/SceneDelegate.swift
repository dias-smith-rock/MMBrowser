import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
        AppLockCoordinator.shared.attach(to: windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {}

    func sceneWillResignActive(_ scene: UIScene) {}

    func sceneWillEnterForeground(_ scene: UIScene) {
        AppLockCoordinator.shared.applicationWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AppLockCoordinator.shared.applicationDidEnterBackground()
    }
}
