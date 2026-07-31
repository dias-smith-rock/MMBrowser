import UIKit

enum BuiltinThemePacks {
    static let all: [ThemePack] = [defaultPack, minimal, cute, steady, feminine]

    static func pack(id: String) -> ThemePack {
        all.first { $0.id == id } ?? defaultPack
    }

    // MARK: - Shared default icon map (SF Symbols)

    private static let defaultIcons: [ThemeIconKey: ThemeIconRef] = [
        .toolbarBack: .symbol("chevron.left"),
        .toolbarForward: .symbol("chevron.right"),
        .toolbarNewTab: .symbol("plus"),
        .toolbarTabs: .symbol("square.on.square"),
        .toolbarMenu: .symbol("line.3.horizontal"),
        .addressScreenshot: .symbol("camera"),
        .addressCleaner: .symbol("wand.and.stars"),
        .menuSettings: .symbol("gear"),
        .menuBookmarks: .symbol("star"),
        .menuHistory: .symbol("clock"),
        .menuReadingList: .symbol("book"),
        .menuDownloads: .symbol("arrow.down.circle"),
        .menuReader: .symbol("doc.text"),
        .menuReload: .symbol("arrow.clockwise"),
        .menuFind: .symbol("magnifyingglass"),
        .menuShare: .symbol("square.and.arrow.up"),
        .menuDesktop: .symbol("desktopcomputer"),
        .menuIncognito: .symbol("eye.slash"),
        .menuAddBookmark: .symbol("star"),
        .menuAddReadingList: .symbol("book"),
        .menuSharePDF: .symbol("doc.richtext"),
        .menuScreenshot: .symbol("camera"),
        .menuLongScreenshot: .symbol("camera.viewfinder")
    ]

    private static func icons(
        base: [ThemeIconKey: ThemeIconRef] = defaultIcons,
        overrides: [ThemeIconKey: ThemeIconRef]
    ) -> [ThemeIconKey: ThemeIconRef] {
        var map = base
        overrides.forEach { map[$0.key] = $0.value }
        return map
    }

    // MARK: Packs

    static let defaultPack = ThemePack(
        id: "default",
        name: "Default",
        isLight: false,
        colors: ThemeColors(
            background: ThemeHex.color("212121"),
            elevated: ThemeHex.color("2E2E2E"),
            card: ThemeHex.color("333333"),
            secondaryCard: ThemeHex.color("3D3D3D"),
            accent: ThemeHex.color("8AB5FA"),
            textPrimary: .white,
            textSecondary: UIColor(white: 0.72, alpha: 1),
            privateBackground: ThemeHex.color("14121F"),
            privateElevated: ThemeHex.color("241F33")
        ),
        icons: defaultIcons
    )

    /// Light, sparse chrome.
    static let minimal = ThemePack(
        id: "minimal",
        name: "Minimal",
        isLight: true,
        colors: ThemeColors(
            background: ThemeHex.color("F5F5F7"),
            elevated: ThemeHex.color("FFFFFF"),
            card: ThemeHex.color("FFFFFF"),
            secondaryCard: ThemeHex.color("ECECEF"),
            accent: ThemeHex.color("1C1C1E"),
            textPrimary: ThemeHex.color("1C1C1E"),
            textSecondary: ThemeHex.color("6C6C70"),
            privateBackground: ThemeHex.color("E8E8ED"),
            privateElevated: ThemeHex.color("FFFFFF")
        ),
        icons: icons(overrides: [
            .toolbarBack: .symbol("chevron.backward"),
            .toolbarForward: .symbol("chevron.forward"),
            .toolbarNewTab: .symbol("plus"),
            .toolbarTabs: .symbol("square"),
            .toolbarMenu: .symbol("line.3.horizontal"),
            .addressCleaner: .symbol("sparkle")
        ])
    )

    /// Light warm / playful. Uses asset keys when present, else SF Symbol fallbacks.
    static let cute = ThemePack(
        id: "cute",
        name: "Cute",
        isLight: true,
        colors: ThemeColors(
            background: ThemeHex.color("FFF6F8"),
            elevated: ThemeHex.color("FFFFFF"),
            card: ThemeHex.color("FFFFFF"),
            secondaryCard: ThemeHex.color("FFE4EC"),
            accent: ThemeHex.color("FF6B9D"),
            textPrimary: ThemeHex.color("4A3040"),
            textSecondary: ThemeHex.color("9A7080"),
            privateBackground: ThemeHex.color("F3E0E8"),
            privateElevated: ThemeHex.color("FFFFFF")
        ),
        icons: icons(overrides: [
            .toolbarBack: .asset("theme_cute_back"),
            .toolbarForward: .asset("theme_cute_forward"),
            .toolbarNewTab: .asset("theme_cute_newtab"),
            .toolbarTabs: .asset("theme_cute_tabs"),
            .toolbarMenu: .symbol("line.3.horizontal"),
            .addressScreenshot: .symbol("camera.fill"),
            .addressCleaner: .symbol("sparkles"),
            .menuIncognito: .symbol("eye.slash.fill"),
            .menuShare: .symbol("heart")
        ])
    )

    static let steady = ThemePack(
        id: "steady",
        name: "Steady",
        isLight: false,
        colors: ThemeColors(
            background: ThemeHex.color("1A1D18"),
            elevated: ThemeHex.color("242820"),
            card: ThemeHex.color("2C3127"),
            secondaryCard: ThemeHex.color("353B2F"),
            accent: ThemeHex.color("C6A75E"),
            textPrimary: ThemeHex.color("F2EDE3"),
            textSecondary: ThemeHex.color("A8A295"),
            privateBackground: ThemeHex.color("12150F"),
            privateElevated: ThemeHex.color("1E2219")
        ),
        icons: icons(overrides: [
            .toolbarBack: .asset("theme_steady_back"),
            .toolbarForward: .asset("theme_steady_forward"),
            .toolbarNewTab: .asset("theme_steady_newtab"),
            .toolbarTabs: .asset("theme_steady_tabs"),
            .toolbarMenu: .symbol("line.3.horizontal"),
            .addressCleaner: .symbol("wand.and.rays")
        ])
    )

    static let feminine = ThemePack(
        id: "feminine",
        name: "Feminine",
        isLight: true,
        colors: ThemeColors(
            background: ThemeHex.color("FBF4F7"),
            elevated: ThemeHex.color("FFFFFF"),
            card: ThemeHex.color("FFFFFF"),
            secondaryCard: ThemeHex.color("F3E2EA"),
            accent: ThemeHex.color("C97B9B"),
            textPrimary: ThemeHex.color("4D3444"),
            textSecondary: ThemeHex.color("8E6F7D"),
            privateBackground: ThemeHex.color("EFE0E7"),
            privateElevated: ThemeHex.color("FFFFFF")
        ),
        icons: icons(overrides: [
            .toolbarBack: .asset("theme_feminine_back"),
            .toolbarForward: .asset("theme_feminine_forward"),
            .toolbarNewTab: .asset("theme_feminine_newtab"),
            .toolbarTabs: .asset("theme_feminine_tabs"),
            .toolbarMenu: .symbol("line.3.horizontal"),
            .addressScreenshot: .symbol("camera.macro"),
            .addressCleaner: .symbol("leaf.fill"),
            .menuBookmarks: .symbol("heart.fill"),
            .menuShare: .symbol("square.and.arrow.up")
        ])
    )
}
