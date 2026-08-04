import Foundation
import FirebaseCore
import FirebaseCrashlytics

enum FirebaseBootstrap {
    private static var didConfigure = false

    /// Configure Firebase once at launch. Safe if `GoogleService-Info.plist` is missing (no-op).
    static func configureIfNeeded() {
        guard !didConfigure else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("[Firebase] GoogleService-Info.plist missing — skip configure. Download it from Firebase Console.")
            #endif
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        didConfigure = true
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        RemoteConfigManager.shared.start()
        AppAnalytics.logAppOpen()
    }
}
