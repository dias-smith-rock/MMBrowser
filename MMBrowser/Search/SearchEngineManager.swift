import Foundation

struct SearchEngine: Equatable {
    let id: String
    let name: String
    let queryURL: String
    let homeURL: String

    static let duckDuckGo = SearchEngine(id: "ddg", name: "DuckDuckGo", queryURL: "https://duckduckgo.com/?q=%@", homeURL: "https://duckduckgo.com")
    static let google = SearchEngine(id: "google", name: "Google", queryURL: "https://www.google.com/search?q=%@", homeURL: "https://www.google.com")
    static let bing = SearchEngine(id: "bing", name: "Bing", queryURL: "https://www.bing.com/search?q=%@", homeURL: "https://www.bing.com")
    static let sogou = SearchEngine(id: "sogou", name: "Sogou", queryURL: "https://www.sogou.com/web?query=%@", homeURL: "https://www.sogou.com")

    static let all: [SearchEngine] = [.duckDuckGo, .google, .bing, .sogou]

    func searchURL(for query: String) -> URL {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: String(format: queryURL, q))!
    }
}

enum SearchEngineManager {
    static var current: SearchEngine {
        let id = AppSettings.searchEngineID
        return SearchEngine.all.first { $0.id == id } ?? .duckDuckGo
    }

    static func setCurrent(_ engine: SearchEngine) {
        AppSettings.searchEngineID = engine.id
        NotificationCenter.default.post(name: .searchEngineChanged, object: nil)
    }
}
