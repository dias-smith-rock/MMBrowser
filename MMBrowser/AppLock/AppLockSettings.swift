import Foundation

enum AppLockPrimaryMethod: String {
    case none
    case pin
    case pattern
}

/// Background grace before requiring unlock again.
enum AppLockGracePeriod: Int, CaseIterable {
    case fiveSeconds = 5
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600

    var timeInterval: TimeInterval { TimeInterval(rawValue) }

    var displayName: String {
        switch self {
        case .fiveSeconds: return "5 Seconds"
        case .fifteenSeconds: return "15 Seconds"
        case .thirtySeconds: return "30 Seconds"
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minutes"
        case .tenMinutes: return "10 Minutes"
        }
    }

    /// Compact label for table detail (e.g. "30s", "1m").
    var shortDisplayName: String {
        switch self {
        case .fiveSeconds: return "5s"
        case .fifteenSeconds: return "15s"
        case .thirtySeconds: return "30s"
        case .oneMinute: return "1m"
        case .fiveMinutes: return "5m"
        case .tenMinutes: return "10m"
        }
    }
}

enum AppLockSettings {
    private static let d = UserDefaults.standard
    private static let defaultGrace = AppLockGracePeriod.thirtySeconds

    /// Master switch: true when any unlock method is configured and lock is on.
    static var isEnabled: Bool {
        get { d.bool(forKey: "applock.enabled") }
        set { d.set(newValue, forKey: "applock.enabled") }
    }

    /// How long the app may stay in background before requiring unlock again.
    static var gracePeriod: AppLockGracePeriod {
        get {
            let raw = d.object(forKey: "applock.grace.seconds") as? Int
            if let raw, let value = AppLockGracePeriod(rawValue: raw) {
                return value
            }
            return defaultGrace
        }
        set { d.set(newValue.rawValue, forKey: "applock.grace.seconds") }
    }

    static var primaryMethod: AppLockPrimaryMethod {
        get { AppLockPrimaryMethod(rawValue: d.string(forKey: "applock.primary") ?? "") ?? .none }
        set { d.set(newValue.rawValue, forKey: "applock.primary") }
    }

    static var biometricsEnabled: Bool {
        get { d.bool(forKey: "applock.biometrics") }
        set { d.set(newValue, forKey: "applock.biometrics") }
    }

    /// User tapped "Not now" on the first-webpage prompt.
    static var setupPromptDismissed: Bool {
        get { d.bool(forKey: "applock.prompt.dismissed") }
        set { d.set(newValue, forKey: "applock.prompt.dismissed") }
    }

    /// User completed setup at least once from the prompt (or settings).
    static var setupPromptCompleted: Bool {
        get { d.bool(forKey: "applock.prompt.completed") }
        set { d.set(newValue, forKey: "applock.prompt.completed") }
    }

    static var hasSeenFirstWebpage: Bool {
        get { d.bool(forKey: "applock.first.webpage") }
        set { d.set(newValue, forKey: "applock.first.webpage") }
    }

    static var shouldShowSetupPrompt: Bool {
        !isEnabled && !setupPromptDismissed && !setupPromptCompleted
    }

    static func clearAllFlags() {
        isEnabled = false
        primaryMethod = .none
        biometricsEnabled = false
    }
}
