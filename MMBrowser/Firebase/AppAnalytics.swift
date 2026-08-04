import Foundation
import FirebaseAnalytics

enum AppAnalytics {
    static func logAppOpen() {
        guard FirebaseBootstrapIsReady else { return }
        Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
    }

    static func logScreen(_ name: String, class className: String? = nil) {
        guard FirebaseBootstrapIsReady else { return }
        var params: [String: Any] = [AnalyticsParameterScreenName: name]
        if let className {
            params[AnalyticsParameterScreenClass] = className
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: params)
    }

    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        guard FirebaseBootstrapIsReady else { return }
        Analytics.logEvent(name, parameters: parameters)
    }

    static func logAccountSwitch(accountName: String) {
        logEvent("account_switch", parameters: ["account_name": accountName])
    }

    static func logAdImpression(format: String) {
        logEvent("ad_impression_custom", parameters: ["format": format])
    }

    static func logAdClick(format: String) {
        logEvent("ad_click_custom", parameters: ["format": format])
    }
}

/// Soft gate so Analytics calls no-op before Firebase is configured.
private var FirebaseBootstrapIsReady: Bool {
    Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
}
