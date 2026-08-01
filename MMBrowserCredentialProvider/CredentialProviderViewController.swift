import AuthenticationServices
import LocalAuthentication
import UIKit

/// System Password AutoFill provider backed by the shared encrypted vault.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var items: [PasswordItemDTO] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchField = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        searchField.placeholder = "Search"
        searchField.borderStyle = .roundedRect
        searchField.addTarget(self, action: #selector(reload), for: .editingChanged)

        tableView.dataSource = self
        tableView.delegate = self

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [cancel, searchField, tableView])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        authenticateThenLoad(preferredHosts: serviceIdentifiers.compactMap { URL(string: $0.identifier)?.host ?? $0.identifier })
    }

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // Require interactive unlock for encrypted vault.
        self.extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userInteractionRequired.rawValue
        ))
    }

    private func authenticateThenLoad(preferredHosts: [String]) {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock MM Browser Passwords") { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard ok else {
                    self.extensionContext.cancelRequest(withError: NSError(
                        domain: ASExtensionErrorDomain,
                        code: ASExtensionError.userCanceled.rawValue
                    ))
                    return
                }
                if VaultCrypto.hasMasterPassword {
                    self.promptMasterPassword { unlocked in
                        if unlocked { self.loadItems(preferredHosts: preferredHosts) }
                        else {
                            self.extensionContext.cancelRequest(withError: NSError(
                                domain: ASExtensionErrorDomain,
                                code: ASExtensionError.userCanceled.rawValue
                            ))
                        }
                    }
                } else {
                    self.loadItems(preferredHosts: preferredHosts)
                }
            }
        }
    }

    private func promptMasterPassword(completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "Master Password", message: nil, preferredStyle: .alert)
        alert.addTextField {
            $0.isSecureTextEntry = true
            $0.placeholder = "Master password"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "Unlock", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            if let key = VaultCrypto.unlockMasterPassword(text) {
                VaultCrypto.setSessionMasterKey(key)
                completion(true)
            } else {
                completion(false)
            }
        })
        present(alert, animated: true)
    }

    private func loadItems(preferredHosts: [String]) {
        guard let key = VaultCrypto.activeKey(),
              let data = VaultKeychain.load(service: VaultKeychain.passwordsService, account: VaultKeychain.blobAccount),
              let decoded = try? VaultCrypto.decrypt(data, as: [PasswordItemDTO].self, with: key)
        else {
            items = []
            tableView.reloadData()
            return
        }
        let preferred = Set(preferredHosts.map { $0.lowercased() })
        items = decoded.sorted { a, b in
            let aHit = preferred.contains(a.host.lowercased())
            let bHit = preferred.contains(b.host.lowercased())
            if aHit != bHit { return aHit && !bHit }
            return a.host.localizedCaseInsensitiveCompare(b.host) == .orderedAscending
        }
        reload()
    }

    @objc private func reload() {
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        extensionContext.cancelRequest(withError: NSError(
            domain: ASExtensionErrorDomain,
            code: ASExtensionError.userCanceled.rawValue
        ))
    }

    private var filtered: [PasswordItemDTO] {
        let q = (searchField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.host.lowercased().contains(q) || $0.username.lowercased().contains(q) || $0.url.lowercased().contains(q)
        }
    }
}

extension CredentialProviderViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(filtered.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        if filtered.isEmpty {
            cell.textLabel?.text = "No passwords"
            cell.detailTextLabel?.text = nil
            cell.selectionStyle = .none
        } else {
            let item = filtered[indexPath.row]
            cell.textLabel?.text = item.host
            cell.detailTextLabel?.text = item.username
            cell.selectionStyle = .default
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !filtered.isEmpty else { return }
        let item = filtered[indexPath.row]
        let credential = ASPasswordCredential(user: item.username, password: item.password)
        extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
    }
}
