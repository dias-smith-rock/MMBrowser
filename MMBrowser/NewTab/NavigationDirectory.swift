import Foundation

struct NavigationSite {
    let title: String
    let urlString: String
    /// Asset catalog name, e.g. `nav_github`.
    let logoAssetName: String

    var url: URL? { URL(string: urlString) }
}

struct NavigationCategory {
    let title: String
    let sites: [NavigationSite]
}

/// Curated, non-editable homepage directory (5 categories × 5 sites).
enum NavigationDirectory {
    static let categories: [NavigationCategory] = [
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
}
