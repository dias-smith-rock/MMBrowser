import Foundation

/// In-app UI languages. English remains the source/default locale.
enum AppLanguage: String, CaseIterable, Equatable {
    case system
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case spanish = "es"
    case portuguese = "pt-BR"
    case arabic = "ar"
    case french = "fr"
    case korean = "ko"
    case japanese = "ja"
    case russian = "ru"

    /// Locale identifier used for Bundle / JSON table lookup.
    var localizationCode: String {
        switch self {
        case .system:
            return Self.resolvedSystemCode
        default:
            return rawValue
        }
    }

    var isRTL: Bool { localizationCode.hasPrefix("ar") }

    /// Native-script label for the language picker (not translated).
    var displayName: String {
        switch self {
        case .system: return "System"
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        case .arabic: return "العربية"
        case .french: return "Français"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        case .russian: return "Русский"
        }
    }

    /// English subtitle for System row / accessibility.
    var englishName: String {
        switch self {
        case .system: return "Follow device language"
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .chineseTraditional: return "Chinese (Traditional)"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese (Brazil)"
        case .arabic: return "Arabic"
        case .french: return "French"
        case .korean: return "Korean"
        case .japanese: return "Japanese"
        case .russian: return "Russian"
        }
    }

    static var resolvedSystemCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") || preferred.hasPrefix("zh-mo") {
            return AppLanguage.chineseTraditional.rawValue
        }
        if preferred.hasPrefix("zh") { return AppLanguage.chineseSimplified.rawValue }
        if preferred.hasPrefix("pt") { return AppLanguage.portuguese.rawValue }
        if preferred.hasPrefix("es") { return AppLanguage.spanish.rawValue }
        if preferred.hasPrefix("ar") { return AppLanguage.arabic.rawValue }
        if preferred.hasPrefix("fr") { return AppLanguage.french.rawValue }
        if preferred.hasPrefix("ko") { return AppLanguage.korean.rawValue }
        if preferred.hasPrefix("ja") { return AppLanguage.japanese.rawValue }
        if preferred.hasPrefix("ru") { return AppLanguage.russian.rawValue }
        return AppLanguage.english.rawValue
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("mmbrowser.appLanguageDidChange")
}
