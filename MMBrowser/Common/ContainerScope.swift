import Foundation

/// Shared container identifiers and helpers for per-account library data.
enum ContainerScope {
    static let libraryMigratedV4Key = "mmbrowser.library.migrated.v4"
    static let containersMigratedV5Key = "mmbrowser.containers.migrated.v5"
    static let containersMigratedV6Key = "mmbrowser.containers.migrated.v6"
    static let didShowAccountWowKey = "mmbrowser.onboarding.accountWow.v1"
    /// After skipping the Split View demo, nudge once via the account chip.
    static let needsAccountChipTipKey = "mmbrowser.onboarding.accountChipTip.v1"
    static let didShowAccountChipTipKey = "mmbrowser.onboarding.accountChipTipShown.v1"

    static func loadContainers() -> [BrowserContainer] {
        guard let data = UserDefaults.standard.data(forKey: "mmbrowser.containers"),
              let saved = try? JSONDecoder().decode([BrowserContainer].self, from: data),
              !saved.isEmpty else { return [] }
        return saved.sorted { $0.sortIndex < $1.sortIndex }
    }

    static func defaultContainerID() -> UUID? {
        loadContainers().first?.id
    }

    static func resolveContainerID(_ id: UUID?) -> UUID {
        if let id, loadContainers().contains(where: { $0.id == id }) { return id }
        if let fallback = defaultContainerID() { return fallback }
        // Should not happen after TabManager creates default accounts.
        return UUID()
    }
}
