import Foundation

struct SearchEngine: Equatable {
    let id: String
    let name: String
    let homeURL: String
    /// Base URL before query items (no `?…`).
    let searchBaseURL: String
    let queryParam: String
    let extraQueryItems: [URLQueryItem]

    static let duckDuckGo = SearchEngine(
        id: "ddg",
        name: "DuckDuckGo",
        homeURL: "https://duckduckgo.com",
        searchBaseURL: "https://duckduckgo.com/",
        queryParam: "q"
    )
    static let google = SearchEngine(
        id: "google",
        name: "Google",
        homeURL: "https://www.google.com",
        searchBaseURL: "https://www.google.com/search",
        queryParam: "q"
    )
    static let bing = SearchEngine(
        id: "bing",
        name: "Bing",
        homeURL: "https://www.bing.com",
        searchBaseURL: "https://www.bing.com/search",
        queryParam: "q"
    )
    static let amazon = SearchEngine(
        id: "amazon",
        name: "Amazon",
        homeURL: "https://www.amazon.com",
        searchBaseURL: "https://www.amazon.com/s",
        queryParam: "k"
    )
    /// Video search works more reliably in WKWebView than the Top tab.
    static let tiktok = SearchEngine(
        id: "tiktok",
        name: "TikTok",
        homeURL: "https://www.tiktok.com",
        searchBaseURL: "https://www.tiktok.com/search/video",
        queryParam: "q"
    )
    static let youTube = SearchEngine(
        id: "youtube",
        name: "YouTube",
        homeURL: "https://www.youtube.com",
        searchBaseURL: "https://www.youtube.com/results",
        queryParam: "search_query"
    )
    static let chatGPT = SearchEngine(
        id: "chatgpt",
        name: "ChatGPT",
        homeURL: "https://chatgpt.com",
        searchBaseURL: "https://chatgpt.com/",
        queryParam: "q"
    )
    /// Open Gemini app with the prompt — Google AI Mode (`udm=50`) is unreliable in WKWebView.
    static let gemini = SearchEngine(
        id: "gemini",
        name: "Gemini",
        homeURL: "https://gemini.google.com/app",
        searchBaseURL: "https://gemini.google.com/app",
        queryParam: "q"
    )

    static let all: [SearchEngine] = [.google, .duckDuckGo, .bing, .amazon, .tiktok, .youTube, .chatGPT, .gemini]
    /// Engines that avoid a signed-in search profile. Brave Search is not in the shipped list.
    static let privacyFriendly: [SearchEngine] = [.duckDuckGo]
    static var general: [SearchEngine] {
        all.filter { engine in !privacyFriendly.contains(where: { $0.id == engine.id }) }
    }

    init(
        id: String,
        name: String,
        homeURL: String,
        searchBaseURL: String,
        queryParam: String,
        extraQueryItems: [URLQueryItem] = []
    ) {
        self.id = id
        self.name = name
        self.homeURL = homeURL
        self.searchBaseURL = searchBaseURL
        self.queryParam = queryParam
        self.extraQueryItems = extraQueryItems
    }

    func searchURL(for query: String) -> URL {
        var components = URLComponents(string: searchBaseURL)
        var items = extraQueryItems
        items.insert(URLQueryItem(name: queryParam, value: query), at: 0)
        components?.queryItems = items
        if let url = components?.url {
            return url
        }
        return URL(string: homeURL) ?? URL(string: "https://www.google.com")!
    }
}

enum SearchEngineManager {
    static var current: SearchEngine {
        let id = AppSettings.searchEngineID
        return SearchEngine.all.first { $0.id == id } ?? .youTube
    }

    static func setCurrent(_ engine: SearchEngine) {
        let previous = AppSettings.searchEngineID
        AppSettings.searchEngineID = engine.id
        NotificationCenter.default.post(name: .searchEngineChanged, object: nil)
        if previous != engine.id {
            AppAnalytics.logSettingsChange(setting: "search_engine", value: engine.id)
        }
    }
}
