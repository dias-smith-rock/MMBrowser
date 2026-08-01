import Foundation

enum PasswordSettings {
    private static var d: UserDefaults { VaultKeychain.sharedDefaults }

    static var autofillForms: Bool {
        get { d.object(forKey: "pwd.autofill.forms") as? Bool ?? true }
        set { d.set(newValue, forKey: "pwd.autofill.forms") }
    }

    static var autofillPasswords: Bool {
        get { d.object(forKey: "pwd.autofill.passwords") as? Bool ?? true }
        set { d.set(newValue, forKey: "pwd.autofill.passwords") }
    }

    static var autoSavePasswords: Bool {
        get { d.object(forKey: "pwd.autosave") as? Bool ?? true }
        set { d.set(newValue, forKey: "pwd.autosave") }
    }

    static var autofillBankCards: Bool {
        get { d.object(forKey: "pwd.autofill.cards") as? Bool ?? false }
        set { d.set(newValue, forKey: "pwd.autofill.cards") }
    }
}
