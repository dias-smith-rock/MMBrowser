import Foundation
import StoreKit

extension Notification.Name {
    static let premiumStatusDidChange = Notification.Name("mmbrowser.premium.statusChanged")
}

/// StoreKit 2 facade for XBrowser Premium subscriptions.
@MainActor
final class PremiumStore {
    static let shared = PremiumStore()

    static let monthlyProductID = "xbrowser.monthly"
    static let yearlyProductID = "xbrowser.yearly"
    /// Free-tier Space cap; Premium is unlimited.
    static let freeSpaceLimit = 3

    private(set) var monthlyProduct: Product?
    private(set) var yearlyProduct: Product?
    private(set) var isPremiumActive = false
    private(set) var activeProductID: String?
    private(set) var expirationDate: Date?
    private(set) var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?
    fileprivate static let cacheActiveKey = "premium.cache.isActive"
    private let cacheProductKey = "premium.cache.productID"
    private let cacheExpiryKey = "premium.cache.expiry"

    var products: [Product] {
        [yearlyProduct, monthlyProduct].compactMap { $0 }
    }

    func canCreateSpace(currentCount: Int) -> Bool {
        isPremiumActive || currentCount < Self.freeSpaceLimit
    }

    /// Per-space PIN / pattern lock is a Premium feature.
    var canUseSpaceLock: Bool { isPremiumActive }

    /// Safe from any queue — reads the cached entitlement flag.
    nonisolated static func canCreateSpaceSync(currentCount: Int) -> Bool {
        UserDefaults.standard.bool(forKey: cacheActiveKey)
            || currentCount < freeSpaceLimit
    }

    nonisolated static var canUseSpaceLockSync: Bool {
        UserDefaults.standard.bool(forKey: cacheActiveKey)
    }

    private init() {
        let defaults = UserDefaults.standard
        isPremiumActive = defaults.bool(forKey: Self.cacheActiveKey)
        activeProductID = defaults.string(forKey: cacheProductKey)
        let expiry = defaults.double(forKey: cacheExpiryKey)
        expirationDate = expiry > 0 ? Date(timeIntervalSince1970: expiry) : nil
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlements()
            }
        }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: [
                Self.yearlyProductID,
                Self.monthlyProductID
            ])
            yearlyProduct = list.first(where: { $0.id == Self.yearlyProductID })
            monthlyProduct = list.first(where: { $0.id == Self.monthlyProductID })
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var bestProduct: String?
        var bestExpiry: Date?
        var active = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.monthlyProductID
                    || transaction.productID == Self.yearlyProductID else { continue }
            if transaction.revocationDate != nil { continue }
            active = true
            let expiry = transaction.expirationDate
            if bestExpiry == nil || (expiry ?? .distantFuture) > (bestExpiry ?? .distantPast) {
                bestExpiry = expiry
                bestProduct = transaction.productID
            }
        }

        let changed = active != isPremiumActive
            || bestProduct != activeProductID
            || bestExpiry != expirationDate
        isPremiumActive = active
        activeProductID = bestProduct
        expirationDate = bestExpiry
        persistCache()
        if changed {
            NotificationCenter.default.post(name: .premiumStatusDidChange, object: nil)
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("Could not verify the purchase.")
                }
                await transaction.finish()
                await refreshEntitlements()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Purchase could not be completed.")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func restore() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            return isPremiumActive
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func trialDays(for product: Product?) -> Int? {
        guard let offer = product?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return periodDays(offer.period)
    }

    func displayPrice(for product: Product?) -> String {
        product?.displayPrice ?? "—"
    }

    /// Yearly price ÷ 12 for “Best Value” monthly equivalent copy.
    func yearlyPerMonthPriceText(for product: Product?) -> String? {
        guard let product, product.id == Self.yearlyProductID else { return nil }
        let perMonth = product.price / 12
        let formatter = product.priceFormatStyle
        return formatter.format(perMonth)
    }

    private func periodDays(_ period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    private func persistCache() {
        let defaults = UserDefaults.standard
        defaults.set(isPremiumActive, forKey: Self.cacheActiveKey)
        defaults.set(activeProductID, forKey: cacheProductKey)
        defaults.set(expirationDate?.timeIntervalSince1970 ?? 0, forKey: cacheExpiryKey)
    }

    enum PurchaseOutcome {
        case success
        case cancelled
        case pending
        case failed(String)
    }
}

/// Once-per-calendar-day cold-start paywall gate.
enum PremiumPaywallGate {
    private static let dismissDayKey = "premium.paywall.dismissDay"

    static func shouldAutoPresentColdStart() -> Bool {
        guard !UserDefaults.standard.bool(forKey: PremiumStore.cacheActiveKey) else { return false }
        return UserDefaults.standard.string(forKey: dismissDayKey) != todayString()
    }

    static func markColdStartDismissedToday() {
        UserDefaults.standard.set(todayString(), forKey: dismissDayKey)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
