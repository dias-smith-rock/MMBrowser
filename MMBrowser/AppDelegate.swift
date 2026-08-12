//
//  AppDelegate.swift
//  MMBrowser
//
//  Created by Xgao on 2023/3/24.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppSettings.recordFirstLaunchIfNeeded()
        FirebaseBootstrap.configureIfNeeded()
        FilterUpdateManager.shared.prepare()
        AdBlockManager.shared.prepare()
        ImageBlockManager.shared.prepare()
        MediaPlaybackSupport.configureAudioSessionIfNeeded()
        DownloadLocalNotifications.shared.configure()
        // Warm the download session so background tasks can reconnect.
        _ = DownloadManager.shared
        // Cover crash / force-quit: clear data only — do not close tabs / dismiss UI on launch.
        // Defer so WebKit's run loop is ready; clearing data stores during early launch can crash.
        DispatchQueue.main.async {
            AutoClearManager.performScheduledClear(runSessionCleanup: false)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        DownloadManager.shared.handleEventsForBackgroundURLSession(completionHandler: completionHandler)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AutoClearManager.performScheduledClear()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AutoClearManager.performScheduledClear()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
