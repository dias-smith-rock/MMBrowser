import UIKit

/// Displays a bundled navigation logo, or fetches a site favicon when none is bundled.
final class FaviconImageView: UIImageView {
    private var loadToken = UUID()

    private static let memoryCache = NSCache<NSString, UIImage>()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFit
        clipsToBounds = true
        backgroundColor = .clear
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setLogo(assetName: String?, urlString: String? = nil, fallbackTitle: String) {
        let token = UUID()
        loadToken = token

        if let assetName, let image = UIImage(named: assetName) {
            self.image = image
            return
        }

        if let urlString, let mapped = Self.bundledAssetName(forURLString: urlString),
           let image = UIImage(named: mapped) {
            self.image = image
            return
        }

        guard let host = Self.host(from: urlString) else {
            self.image = Self.letterImage(for: fallbackTitle)
            return
        }

        let cacheKey = host as NSString
        if let cached = Self.memoryCache.object(forKey: cacheKey) {
            self.image = cached
            return
        }

        self.image = Self.letterImage(for: fallbackTitle)
        Self.fetchFavicon(host: host) { [weak self] image in
            guard let self, self.loadToken == token, let image else { return }
            Self.memoryCache.setObject(image, forKey: cacheKey)
            self.image = image
        }
    }

    // MARK: - Remote

    private static func fetchFavicon(host: String, completion: @escaping (UIImage?) -> Void) {
        let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
        guard let url = URL(string: "https://www.google.com/s2/favicons?sz=128&domain=\(encoded)") else {
            completion(nil)
            return
        }
        session.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }

    private static func host(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return nil
        }
        return host.lowercased()
    }

    /// Prefer high-quality bundled marks when we already ship them.
    private static func bundledAssetName(forURLString urlString: String) -> String? {
        guard let host = host(from: urlString) else { return nil }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        if h == "music.youtube.com" { return "nav_youtubemusic" }
        if h == "youtube.com" || h.hasSuffix(".youtube.com") { return "nav_youtube" }
        if h == "linkedin.com" || h.hasSuffix(".linkedin.com") { return "nav_linkedin" }
        if h == "facebook.com" || h.hasSuffix(".facebook.com") { return "nav_facebook" }
        if h == "instagram.com" || h.hasSuffix(".instagram.com") { return "nav_instagram" }
        if h == "x.com" || h == "twitter.com" || h.hasSuffix(".twitter.com") { return "nav_x" }
        if h == "github.com" || h.hasSuffix(".github.com") { return "nav_github" }
        if h == "chatgpt.com" || h == "chat.openai.com" { return "nav_chatgpt" }
        if h == "claude.ai" || h.hasSuffix(".claude.ai") { return "nav_claude" }
        if h == "gemini.google.com" { return "nav_gemini" }
        if h == "bbc.com" || h == "bbc.co.uk" || h.hasSuffix(".bbc.co.uk") { return "nav_bbc" }
        if h == "cnn.com" || h.hasSuffix(".cnn.com") { return "nav_cnn" }
        if h == "reuters.com" || h.hasSuffix(".reuters.com") { return "nav_reuters" }
        if h == "theguardian.com" || h.hasSuffix(".theguardian.com") { return "nav_guardian" }
        if h == "spotify.com" || h.hasSuffix(".spotify.com") { return "nav_spotify" }
        if h == "soundcloud.com" || h.hasSuffix(".soundcloud.com") { return "nav_soundcloud" }
        if h == "tmz.com" || h.hasSuffix(".tmz.com") { return "nav_tmz" }
        if h == "people.com" || h.hasSuffix(".people.com") { return "nav_people" }
        if h == "buzzfeed.com" || h.hasSuffix(".buzzfeed.com") { return "nav_buzzfeed" }
        if h == "dailymail.co.uk" || h.hasSuffix(".dailymail.co.uk") { return "nav_dailymail" }
        if h == "reddit.com" || h.hasSuffix(".reddit.com") { return "nav_reddit" }
        if h == "huggingface.co" || h.hasSuffix(".huggingface.co") { return "nav_huggingface" }
        if h == "techcrunch.com" || h.hasSuffix(".techcrunch.com") { return "nav_techcrunch" }
        if h == "bandcamp.com" || h.hasSuffix(".bandcamp.com") { return "nav_bandcamp" }
        return nil
    }

    private static func letterImage(for title: String) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let letter = String(title.prefix(1)).uppercased()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: 0, y: 14, width: size.width, height: 36)
            letter.draw(in: rect, withAttributes: attrs)
        }
    }
}
