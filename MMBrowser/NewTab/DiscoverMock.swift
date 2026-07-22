import Foundation

struct DiscoverItem {
    let title: String
    let source: String
    let timeText: String
    let urlString: String
    let accentColorHex: UInt32
}

enum DiscoverMock {
    static let items: [DiscoverItem] = [
        DiscoverItem(
            title: "SpaceX launches 24 Starlink satellites to expand global coverage",
            source: "Tech Daily",
            timeText: "20h",
            urlString: "https://www.google.com/search?q=SpaceX+Starlink+launch",
            accentColorHex: 0x3B82F6
        ),
        DiscoverItem(
            title: "iOS browsers adopt new privacy APIs for smarter tracking protection",
            source: "Mobile Weekly",
            timeText: "1d",
            urlString: "https://www.google.com/search?q=iOS+browser+privacy+APIs",
            accentColorHex: 0x10B981
        ),
        DiscoverItem(
            title: "How AI assistants are changing everyday search habits",
            source: "Insight Hub",
            timeText: "2d",
            urlString: "https://www.google.com/search?q=AI+search+habits",
            accentColorHex: 0xF59E0B
        ),
        DiscoverItem(
            title: "Open source web engines push performance gains on mobile",
            source: "Dev News",
            timeText: "3d",
            urlString: "https://www.google.com/search?q=mobile+web+engine+performance",
            accentColorHex: 0xEF4444
        )
    ]
}
