import Foundation

/// App-wide localization. English source strings are the lookup keys.
/// Missing translations fall back to English.
enum AppL10n {
    /// Legacy typed keys (kept for existing call sites).
    enum Key: String {
        case hubCloseNoTabsHint = "Please enter a search term or URL to open a web page"
    }

    private static var table: [String: String] = [:]
    private static var loadedCode: String?

    static func reload() {
        loadedCode = nil
        _ = ensureTable()
    }

    static func string(_ key: Key) -> String {
        t(key.rawValue)
    }

    static func t(_ key: String) -> String {
        let table = ensureTable()
        return table[key] ?? key
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: Locale(identifier: LanguageManager.activeLocalizationCode), arguments: arguments)
    }

    private static func ensureTable() -> [String: String] {
        let code = LanguageManager.activeLocalizationCode
        if loadedCode == code, !table.isEmpty { return table }
        loadedCode = code
        table = loadTable(code: code)
        return table
    }

    private static func loadTable(code: String) -> [String: String] {
        if code == "en" || code.hasPrefix("en-") {
            return [:]
        }
        let name = "L10n_\(code)"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            // Try normalized codes (pt → pt-BR already handled by AppLanguage).
            return [:]
        }
        return json
    }
}

extension String {
    /// Translate this English source string using the active in-app language.
    var l10n: String { AppL10n.t(self) }
}
