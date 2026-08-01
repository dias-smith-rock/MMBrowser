import UIKit
import SnapKit

final class FormProfileViewController: UIViewController {
    private var fields: [(String, UITextField)] = []
    private var profile = FormProfileStore.shared.profile

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Form profile"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        let scroll = UIScrollView()
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12
        view.addSubview(scroll)
        scroll.addSubview(content)
        scroll.snp.makeConstraints { $0.edges.equalToSuperview() }
        content.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
            make.width.equalTo(scroll).offset(-32)
        }

        let specs: [(String, String, KeyPath<FormProfile, String>)] = [
            ("Full name", profile.fullName, \.fullName),
            ("Email", profile.email, \.email),
            ("Phone", profile.phone, \.phone),
            ("Address line 1", profile.addressLine1, \.addressLine1),
            ("Address line 2", profile.addressLine2, \.addressLine2),
            ("City", profile.city, \.city),
            ("State", profile.state, \.state),
            ("Postal code", profile.postalCode, \.postalCode),
            ("Country", profile.country, \.country)
        ]

        for (placeholder, value, _) in specs {
            let field = makeField(placeholder: placeholder, text: value)
            fields.append((placeholder, field))
            content.addArrangedSubview(field)
            field.snp.makeConstraints { $0.height.equalTo(48) }
        }
    }

    private func makeField(placeholder: String, text: String) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = text
        field.backgroundColor = BrowserTheme.card
        field.textColor = BrowserTheme.textPrimary
        field.layer.cornerRadius = 12
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.autocapitalizationType = .words
        return field
    }

    @objc private func save() {
        func text(_ placeholder: String) -> String {
            fields.first(where: { $0.0 == placeholder })?.1.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let next = FormProfile(
            fullName: text("Full name"),
            email: text("Email"),
            phone: text("Phone"),
            addressLine1: text("Address line 1"),
            addressLine2: text("Address line 2"),
            city: text("City"),
            state: text("State"),
            postalCode: text("Postal code"),
            country: text("Country")
        )
        if FormProfileStore.shared.save(next) {
            Toast.show("Form profile saved", from: self)
            navigationController?.popViewController(animated: true)
        } else {
            Toast.show("Could not save profile", from: self)
        }
    }
}
