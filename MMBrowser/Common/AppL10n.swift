import Foundation

/// Lightweight localization for user-facing strings. Uses the preferred language;
/// falls back to English when a translation is missing.
enum AppL10n {
    enum Key: String {
        case hubCloseNoTabsHint
    }

    static func string(_ key: Key) -> String {
        let table = tableForPreferredLanguage()
        return table[key.rawValue] ?? en[key.rawValue] ?? key.rawValue
    }

    private static func tableForPreferredLanguage() -> [String: String] {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return zhHant
        }
        if preferred.hasPrefix("zh") {
            return zhHans
        }
        if preferred.hasPrefix("ja") { return ja }
        if preferred.hasPrefix("ko") { return ko }
        if preferred.hasPrefix("es") { return es }
        if preferred.hasPrefix("pt") { return pt }
        if preferred.hasPrefix("fr") { return fr }
        if preferred.hasPrefix("de") { return de }
        return en
    }

    private static let en: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "Please enter a search term or URL to open a web page"
    ]

    private static let zhHans: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "请输入搜索词或者网址以打开网页"
    ]

    private static let zhHant: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "請輸入搜尋詞或網址以開啟網頁"
    ]

    private static let ja: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "検索語またはURLを入力してページを開いてください"
    ]

    private static let ko: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "검색어 또는 URL을 입력하여 웹페이지를 여세요"
    ]

    private static let es: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "Introduce un término de búsqueda o una URL para abrir una página"
    ]

    private static let pt: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "Digite um termo de pesquisa ou URL para abrir uma página"
    ]

    private static let fr: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "Saisissez un terme de recherche ou une URL pour ouvrir une page"
    ]

    private static let de: [String: String] = [
        Key.hubCloseNoTabsHint.rawValue:
            "Gib einen Suchbegriff oder eine URL ein, um eine Seite zu öffnen"
    ]
}
