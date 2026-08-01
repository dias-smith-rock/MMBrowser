import Foundation
import CryptoKit

struct FormProfile: Codable, Equatable {
    var fullName: String
    var email: String
    var phone: String
    var addressLine1: String
    var addressLine2: String
    var city: String
    var state: String
    var postalCode: String
    var country: String

    static var empty: FormProfile {
        FormProfile(
            fullName: "", email: "", phone: "",
            addressLine1: "", addressLine2: "", city: "",
            state: "", postalCode: "", country: ""
        )
    }

    var dto: FormProfileDTO {
        FormProfileDTO(
            fullName: fullName, email: email, phone: phone,
            addressLine1: addressLine1, addressLine2: addressLine2,
            city: city, state: state, postalCode: postalCode, country: country
        )
    }

    static func from(_ dto: FormProfileDTO) -> FormProfile {
        FormProfile(
            fullName: dto.fullName, email: dto.email, phone: dto.phone,
            addressLine1: dto.addressLine1, addressLine2: dto.addressLine2,
            city: dto.city, state: dto.state, postalCode: dto.postalCode, country: dto.country
        )
    }

    var hasAnyValue: Bool {
        [fullName, email, phone, addressLine1, addressLine2, city, state, postalCode, country]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

final class FormProfileStore {
    static let shared = FormProfileStore()
    private init() {}
    private var cache: FormProfile?

    var profile: FormProfile {
        load()
    }

    @discardableResult
    func save(_ profile: FormProfile) -> Bool {
        guard let key = VaultCrypto.activeKey() else { return false }
        do {
            let sealed = try VaultCrypto.encrypt(profile.dto, with: key)
            let ok = VaultKeychain.set(service: VaultKeychain.formProfileService, account: VaultKeychain.blobAccount, data: sealed)
            if ok { cache = profile }
            return ok
        } catch {
            return false
        }
    }

    func reload() { cache = nil; _ = load() }

    private func load() -> FormProfile {
        if let cache { return cache }
        guard let key = VaultCrypto.activeKey() else {
            cache = .empty
            return .empty
        }
        guard let data = VaultKeychain.load(service: VaultKeychain.formProfileService, account: VaultKeychain.blobAccount) else {
            cache = .empty
            return .empty
        }
        do {
            let profile = FormProfile.from(try VaultCrypto.decrypt(data, as: FormProfileDTO.self, with: key))
            cache = profile
            return profile
        } catch {
            cache = .empty
            return .empty
        }
    }
}
