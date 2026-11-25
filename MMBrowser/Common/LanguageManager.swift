import UIKit

/// Applies the in-app UI language (including RTL) and rebuilds the root UI when it changes.
enum LanguageManager {
    static var current: AppLanguage {
        AppSettings.appLanguage
    }

    static var activeLocalizationCode: String {
        current.localizationCode
    }

    static func bootstrap() {
        applyLayoutDirection(isRTL: current.isRTL)
        AppL10n.reload()
    }

    @MainActor
    static func setLanguage(_ language: AppLanguage) {
        guard language != AppSettings.appLanguage else { return }
        AppSettings.appLanguage = language
        AppL10n.reload()
        applyLayoutDirection(isRTL: language.isRTL)
        NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        rebuildRootInterface()
    }

    private static func applyLayoutDirection(isRTL: Bool) {
        let attribute: UISemanticContentAttribute = isRTL ? .forceRightToLeft : .forceLeftToRight
        UIView.appearance().semanticContentAttribute = attribute
        UINavigationBar.appearance().semanticContentAttribute = attribute
        UITabBar.appearance().semanticContentAttribute = attribute
        UISearchBar.appearance().semanticContentAttribute = attribute
        UITextField.appearance().semanticContentAttribute = attribute
        UITextView.appearance().semanticContentAttribute = attribute
    }

    @MainActor
    private static func rebuildRootInterface() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let delegate = windowScene.delegate as? SceneDelegate,
              let window = delegate.window
        else { return }

        let browser = BrowserViewController()
        window.rootViewController = browser
        window.makeKeyAndVisible()
        KeyboardDismissCoordinator.shared.attach(to: window)
        AppLockCoordinator.shared.attach(to: windowScene)
        window.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
    }
}
