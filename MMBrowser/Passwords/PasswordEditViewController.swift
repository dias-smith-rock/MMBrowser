import UIKit
import SnapKit

final class PasswordEditViewController: UIViewController, UITextFieldDelegate, UITextViewDelegate {
    enum Mode {
        case create
        case edit(PasswordItem)
    }

    var onSaved: (() -> Void)?

    private let mode: Mode
    /// When creating, bind the entry to this browsing account.
    private let defaultContainerID: UUID?
    private let siteField = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let commentsView = UITextView()
    private var saveItem: UIBarButtonItem!

    init(mode: Mode, defaultContainerID: UUID? = nil) {
        self.mode = mode
        self.defaultContainerID = defaultContainerID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch mode {
        case .create: title = "New password"
        case .edit: title = "Edit password"
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        saveItem = UIBarButtonItem(
            title: {
                if case .create = mode { return "Add" }
                return "Save"
            }(),
            style: .done,
            target: self,
            action: #selector(save)
        )
        navigationItem.rightBarButtonItem = saveItem

        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        configureField(siteField, placeholder: "Site", keyboard: .URL)
        configureField(usernameField, placeholder: "Username", keyboard: .emailAddress)
        configureField(passwordField, placeholder: "Password", keyboard: .default)
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .newPassword

        commentsView.font = .systemFont(ofSize: 16)
        commentsView.textColor = BrowserTheme.textPrimary
        commentsView.backgroundColor = BrowserTheme.card
        commentsView.layer.cornerRadius = 12
        commentsView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        commentsView.delegate = self
        commentsView.text = "Comments..."
        commentsView.textColor = BrowserTheme.textSecondary

        let stack = UIStackView(arrangedSubviews: [siteField, usernameField, passwordField, commentsView])
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        [siteField, usernameField, passwordField].forEach {
            $0.snp.makeConstraints { $0.height.equalTo(48) }
        }
        commentsView.snp.makeConstraints { $0.height.equalTo(120) }

        if case let .edit(item) = mode {
            siteField.text = item.url
            usernameField.text = item.username
            passwordField.text = item.password
            if !item.comments.isEmpty {
                commentsView.text = item.comments
                commentsView.textColor = BrowserTheme.textPrimary
            }
        }

        [siteField, usernameField, passwordField].forEach {
            $0.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        }
        fieldsChanged()
    }

    private func configureField(_ field: UITextField, placeholder: String, keyboard: UIKeyboardType) {
        field.placeholder = placeholder
        field.borderStyle = .none
        field.backgroundColor = BrowserTheme.card
        field.textColor = BrowserTheme.textPrimary
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.layer.cornerRadius = 12
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.delegate = self
        field.clearButtonMode = .whileEditing
    }

    @objc private func fieldsChanged() {
        let site = siteField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let user = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pass = passwordField.text ?? ""
        saveItem.isEnabled = !site.isEmpty && (!user.isEmpty || !pass.isEmpty)
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        let site = siteField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let user = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pass = passwordField.text ?? ""
        var comments = commentsView.text ?? ""
        if commentsView.textColor == BrowserTheme.textSecondary || comments == "Comments..." {
            comments = ""
        }
        switch mode {
        case .create:
            guard PasswordStore.shared.add(
                site: site,
                username: user,
                password: pass,
                comments: comments,
                containerID: defaultContainerID
            ) != nil else {
                Toast.show("Could not save password", from: self)
                return
            }
            Toast.show("Password saved", from: self)
        case .edit(var item):
            item.url = site
            item.username = user
            item.password = pass
            item.comments = comments
            if item.containerID == nil, let defaultContainerID {
                item.containerID = defaultContainerID
            }
            guard PasswordStore.shared.update(item) else {
                Toast.show("Could not update password", from: self)
                return
            }
            Toast.show("Password updated", from: self)
        }
        onSaved?()
        dismiss(animated: true)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == BrowserTheme.textSecondary {
            textView.text = ""
            textView.textColor = BrowserTheme.textPrimary
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = "Comments..."
            textView.textColor = BrowserTheme.textSecondary
        }
    }
}
