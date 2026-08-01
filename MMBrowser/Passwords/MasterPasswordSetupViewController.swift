import UIKit
import SnapKit
import CryptoKit

final class MasterPasswordSetupViewController: UIViewController {
    enum Mode {
        case create
        case change
        case remove
    }

    var onFinished: (() -> Void)?

    private let mode: Mode
    private let currentField = UITextField()
    private let passwordField = UITextField()
    private let confirmField = UITextField()
    private let warningLabel = UILabel()

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        switch mode {
        case .create: title = "Create master password"
        case .change: title = "Change master password"
        case .remove: title = "Remove master password"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(done))

        warningLabel.numberOfLines = 0
        warningLabel.font = .systemFont(ofSize: 13)
        warningLabel.textColor = BrowserTheme.textSecondary
        warningLabel.text = "If you forget your master password, saved passwords and cards cannot be recovered. You can only delete the vault and start over."

        configure(currentField, placeholder: "Current master password")
        configure(passwordField, placeholder: mode == .remove ? "Master password" : "New master password")
        configure(confirmField, placeholder: "Confirm master password")

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            make.leading.trailing.equalToSuperview().inset(16)
        }

        switch mode {
        case .create:
            stack.addArrangedSubview(passwordField)
            stack.addArrangedSubview(confirmField)
            stack.addArrangedSubview(warningLabel)
        case .change:
            stack.addArrangedSubview(currentField)
            stack.addArrangedSubview(passwordField)
            stack.addArrangedSubview(confirmField)
            stack.addArrangedSubview(warningLabel)
        case .remove:
            stack.addArrangedSubview(passwordField)
            stack.addArrangedSubview(warningLabel)
        }

        [currentField, passwordField, confirmField].forEach {
            $0.snp.makeConstraints { $0.height.equalTo(48) }
        }
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.backgroundColor = BrowserTheme.card
        field.textColor = BrowserTheme.textPrimary
        field.layer.cornerRadius = 12
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func done() {
        switch mode {
        case .create:
            let p = passwordField.text ?? ""
            let c = confirmField.text ?? ""
            guard p.count >= 6 else {
                Toast.show("Use at least 6 characters", from: self)
                return
            }
            guard p == c else {
                Toast.show("Passwords do not match", from: self)
                return
            }
            let oldKey = VaultCrypto.deviceKey()
            guard let newKey = VaultCrypto.setMasterPassword(p) else {
                Toast.show("Could not set master password", from: self)
                return
            }
            reencryptAll(from: oldKey, to: newKey)
            VaultCrypto.setSessionMasterKey(newKey)
            Toast.show("Master password created", from: self)
        case .change:
            let current = currentField.text ?? ""
            let p = passwordField.text ?? ""
            let c = confirmField.text ?? ""
            guard let oldKey = VaultCrypto.unlockMasterPassword(current) else {
                Toast.show("Incorrect current password", from: self)
                return
            }
            guard p.count >= 6, p == c else {
                Toast.show("Check the new password fields", from: self)
                return
            }
            VaultCrypto.clearMasterPassword()
            guard let newKey = VaultCrypto.setMasterPassword(p) else {
                Toast.show("Could not change master password", from: self)
                return
            }
            reencryptAll(from: oldKey, to: newKey)
            VaultCrypto.setSessionMasterKey(newKey)
            Toast.show("Master password changed", from: self)
        case .remove:
            let p = passwordField.text ?? ""
            guard let oldKey = VaultCrypto.unlockMasterPassword(p) else {
                Toast.show("Incorrect master password", from: self)
                return
            }
            let deviceKey = VaultCrypto.deviceKey()
            reencryptAll(from: oldKey, to: deviceKey)
            VaultCrypto.clearMasterPassword()
            VaultCrypto.setSessionMasterKey(nil)
            Toast.show("Master password removed", from: self)
        }
        onFinished?()
        dismiss(animated: true)
    }

    private func reencryptAll(from oldKey: SymmetricKey, to newKey: SymmetricKey) {
        VaultCrypto.reencrypt(service: VaultKeychain.passwordsService, from: oldKey, to: newKey)
        VaultCrypto.reencrypt(service: VaultKeychain.bankCardsService, from: oldKey, to: newKey)
        VaultCrypto.reencrypt(service: VaultKeychain.formProfileService, from: oldKey, to: newKey)
        PasswordStore.shared.reload()
        BankCardStore.shared.reload()
        FormProfileStore.shared.reload()
    }
}
