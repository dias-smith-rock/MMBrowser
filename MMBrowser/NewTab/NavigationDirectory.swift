import Foundation

struct NavigationSite: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var urlString: String
    /// Asset catalog name when known (preset logos); nil for user-added sites.
    var logoAssetName: String?

    var url: URL? { URL(string: urlString) }

    init(id: UUID = UUID(), title: String, urlString: String, logoAssetName: String? = nil) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.logoAssetName = logoAssetName
    }
}

struct NavigationCategory: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var sites: [NavigationSite]
    var isHome: Bool

    init(id: UUID = UUID(), title: String, sites: [NavigationSite], isHome: Bool = false) {
        self.id = id
        self.title = title
        self.sites = sites
        self.isHome = isHome
    }
}

/// Built-in seed catalog (also used by “Restore Defaults”).
enum NavigationDirectory {
    static let defaultCategories: [NavigationCategory] = [
        NavigationCategory(
            title: "AI & Tech",
            sites: [
                NavigationSite(title: "ChatGPT", urlString: "https://chatgpt.com", logoAssetName: "nav_chatgpt"),
                NavigationSite(title: "Claude", urlString: "https://claude.ai", logoAssetName: "nav_claude"),
                NavigationSite(title: "Gemini", urlString: "https://gemini.google.com", logoAssetName: "nav_gemini"),
                NavigationSite(title: "GitHub", urlString: "https://github.com", logoAssetName: "nav_github"),
                NavigationSite(title: "Hugging Face", urlString: "https://huggingface.co", logoAssetName: "nav_huggingface")
            ]
        ),
        NavigationCategory(
            title: "Social Media",
            sites: [
                NavigationSite(title: "Facebook", urlString: "https://www.facebook.com", logoAssetName: "nav_facebook"),
                NavigationSite(title: "Instagram", urlString: "https://www.instagram.com", logoAssetName: "nav_instagram"),
                NavigationSite(title: "X", urlString: "https://x.com", logoAssetName: "nav_x"),
                NavigationSite(title: "LinkedIn", urlString: "https://www.linkedin.com", logoAssetName: "nav_linkedin"),
                NavigationSite(title: "Reddit", urlString: "https://www.reddit.com", logoAssetName: "nav_reddit")
            ]
        ),
        NavigationCategory(
            title: "News",
            sites: [
                NavigationSite(title: "BBC", urlString: "https://www.bbc.com", logoAssetName: "nav_bbc"),
                NavigationSite(title: "CNN", urlString: "https://www.cnn.com", logoAssetName: "nav_cnn"),
                NavigationSite(title: "Reuters", urlString: "https://www.reuters.com", logoAssetName: "nav_reuters"),
                NavigationSite(title: "The Guardian", urlString: "https://www.theguardian.com", logoAssetName: "nav_guardian"),
                NavigationSite(title: "TechCrunch", urlString: "https://techcrunch.com", logoAssetName: "nav_techcrunch")
            ]
        ),
        NavigationCategory(
            title: "Music",
            sites: [
                NavigationSite(title: "Spotify", urlString: "https://open.spotify.com", logoAssetName: "nav_spotify"),
                NavigationSite(title: "YouTube Music", urlString: "https://music.youtube.com", logoAssetName: "nav_youtubemusic"),
                NavigationSite(title: "YouTube", urlString: "https://www.youtube.com", logoAssetName: "nav_youtube"),
                NavigationSite(title: "SoundCloud", urlString: "https://soundcloud.com", logoAssetName: "nav_soundcloud"),
                NavigationSite(title: "Bandcamp", urlString: "https://bandcamp.com", logoAssetName: "nav_bandcamp")
            ]
        ),
        NavigationCategory(
            title: "Gossip",
            sites: [
                NavigationSite(title: "TMZ", urlString: "https://www.tmz.com", logoAssetName: "nav_tmz"),
                NavigationSite(title: "People", urlString: "https://people.com", logoAssetName: "nav_people"),
                NavigationSite(title: "BuzzFeed", urlString: "https://www.buzzfeed.com", logoAssetName: "nav_buzzfeed"),
                NavigationSite(title: "Daily Mail", urlString: "https://www.dailymail.co.uk", logoAssetName: "nav_dailymail"),
                NavigationSite(title: "E! News", urlString: "https://www.eonline.com", logoAssetName: "nav_enews")
            ]
        )
    ]

    static func makeSeedCategories(includingHome homeSites: [NavigationSite] = []) -> [NavigationCategory] {
        var result: [NavigationCategory] = [
            NavigationCategory(title: "Home", sites: homeSites, isHome: true)
        ]
        result.append(contentsOf: defaultCategories.map {
            NavigationCategory(
                id: UUID(),
                title: $0.title,
                sites: $0.sites.map {
                    NavigationSite(
                        id: UUID(),
                        title: $0.title,
                        urlString: $0.urlString,
                        logoAssetName: $0.logoAssetName
                    )
                },
                isHome: false
            )
        })
        return result
    }
}
