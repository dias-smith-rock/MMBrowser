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
        FilterUpdateManager.shared.prepare()
        AdBlockManager.shared.prepare()
        MediaPlaybackSupport.configureAudioSessionIfNeeded()
        // Cover crash / force-quit: clear data only — do not close tabs / dismiss UI on launch.
        // Defer so WebKit's run loop is ready; clearing data stores during early launch can crash.
        DispatchQueue.main.async {
            AutoClearManager.performScheduledClear(runSessionCleanup: false)
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AutoClearManager.performScheduledClear()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AutoClearManager.performScheduledClear()
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

