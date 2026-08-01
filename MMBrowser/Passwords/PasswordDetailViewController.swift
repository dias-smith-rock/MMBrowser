import UIKit
import SnapKit

final class PasswordDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onChanged: (() -> Void)?

    private var item: PasswordItem
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var passwordVisible = false

    init(item: PasswordItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.host
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "pencil"),
            style: .plain,
            target: self,
            action: #selector(editTapped)
        )

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        tableView.reloadData()
    }

    @objc private func editTapped() {
        let edit = PasswordEditViewController(mode: .edit(item))
        edit.onSaved = { [weak self] in
            guard let self else { return }
            if let updated = PasswordStore.shared.all.first(where: { $0.id == self.item.id }) {
                self.item = updated
                self.title = updated.host
            }
            self.tableView.reloadData()
            self.onChanged?()
        }
        let nav = UINavigationController(rootViewController: edit)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 3 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3
        case 1: return 3
        default: return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.selectionStyle = .default
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textAlignment = .natural
        cell.textLabel?.numberOfLines = 2
        cell.imageView?.image = nil

        switch indexPath.section {
        case 0:
            cell.selectionStyle = .none
            cell.textLabel?.textColor = BrowserTheme.textPrimary
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Username\n\(item.username.isEmpty ? "—" : item.username)"
            case 1:
                let shown = passwordVisible ? item.password : String(repeating: "•", count: max(item.password.count, 8))
                cell.textLabel?.text = "Password\n\(shown)"
                let eye = UIButton(type: .system)
                eye.setImage(UIImage(systemName: passwordVisible ? "eye.slash" : "eye"), for: .normal)
                eye.tintColor = BrowserTheme.textSecondary
                eye.addTarget(self, action: #selector(togglePassword), for: .touchUpInside)
                eye.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
                cell.accessoryView = eye
            default:
                cell.textLabel?.text = "URL\n\(item.url)"
            }
        case 1:
            cell.textLabel?.textColor = BrowserTheme.chromeBlue
            let titles = ["Copy login", "Copy password", "Show password"]
            cell.textLabel?.text = passwordVisible && indexPath.row == 2 ? "Hide password" : titles[indexPath.row]
        default:
            cell.textLabel?.text = "Delete"
            cell.textLabel?.textColor = .systemRed
            cell.textLabel?.textAlignment = .center
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 1:
            switch indexPath.row {
            case 0:
                UIPasteboard.general.string = item.username
                Toast.show("Login copied", from: self)
            case 1:
                UIPasteboard.general.string = item.password
                Toast.show("Password copied", from: self)
            default:
                togglePassword()
            }
        case 2:
            confirmDelete()
        default:
            break
        }
    }

    @objc private func togglePassword() {
        passwordVisible.toggle()
        tableView.reloadSections(IndexSet(integer: 0), with: .none)
        tableView.reloadRows(at: [IndexPath(row: 2, section: 1)], with: .none)
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Delete Password?", message: item.host, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            _ = PasswordStore.shared.remove(id: self.item.id)
            self.onChanged?()
            self.navigationController?.popViewController(animated: true)
            Toast.show("Password deleted", from: self)
        })
        present(alert, animated: true)
    }
}
