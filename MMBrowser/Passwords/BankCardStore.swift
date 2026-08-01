import Foundation
import CryptoKit

struct BankCardItem: Codable, Equatable {
    var id: String
    var holderName: String
    var number: String
    var expiryMonth: Int
    var expiryYear: Int
    var cvv: String
    var updatedAt: Date

    var maskedNumber: String {
        let digits = number.filter(\.isNumber)
        guard digits.count >= 4 else { return "••••" }
        return "•••• " + String(digits.suffix(4))
    }

    var dto: BankCardItemDTO {
        BankCardItemDTO(
            id: id, holderName: holderName, number: number,
            expiryMonth: expiryMonth, expiryYear: expiryYear, cvv: cvv, updatedAt: updatedAt
        )
    }

    static func from(_ dto: BankCardItemDTO) -> BankCardItem {
        BankCardItem(
            id: dto.id, holderName: dto.holderName, number: dto.number,
            expiryMonth: dto.expiryMonth, expiryYear: dto.expiryYear, cvv: dto.cvv, updatedAt: dto.updatedAt
        )
    }
}

final class BankCardStore {
    static let shared = BankCardStore()
    private init() {}
    private var cache: [BankCardItem]?

    var all: [BankCardItem] { load() }

    @discardableResult
    func add(_ item: BankCardItem) -> Bool {
        var items = load()
        items.append(item)
        return persist(items)
    }

    @discardableResult
    func update(_ item: BankCardItem) -> Bool {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return false }
        var next = item
        next.updatedAt = Date()
        items[idx] = next
        return persist(items)
    }

    @discardableResult
    func remove(id: String) -> Bool {
        var items = load()
        items.removeAll { $0.id == id }
        return persist(items)
    }

    @discardableResult
    func removeAll() -> Bool { persist([]) }

    func reload() { cache = nil; _ = load() }

    private func load() -> [BankCardItem] {
        if let cache { return cache }
        guard let key = VaultCrypto.activeKey() else { return [] }
        guard let data = VaultKeychain.load(service: VaultKeychain.bankCardsService, account: VaultKeychain.blobAccount) else {
            cache = []
            return []
        }
        if let items = try? VaultCrypto.decrypt(data, as: [BankCardItemDTO].self, with: key).map(BankCardItem.from) {
            cache = items
            return items
        }
        if VaultCrypto.hasMasterPassword {
            let device = VaultCrypto.deviceKey()
            if let items = try? VaultCrypto.decrypt(data, as: [BankCardItemDTO].self, with: device).map(BankCardItem.from) {
                _ = persist(items)
                return items
            }
        }
        return []
    }

    private func persist(_ items: [BankCardItem]) -> Bool {
        guard let key = VaultCrypto.activeKey() else { return false }
        do {
            let sealed = try VaultCrypto.encrypt(items.map(\.dto), with: key)
            let ok = VaultKeychain.set(service: VaultKeychain.bankCardsService, account: VaultKeychain.blobAccount, data: sealed)
            if ok { cache = items }
            return ok
        } catch {
            return false
        }
    }
}
