import UIKit
import SnapKit

final class AutofillSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable {
        case forms
        case protection
        case passwords
        case cards
        case manage
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AutoFill settings"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        applyChrome()
        NotificationCenter.default.addObserver(self, selector: #selector(applyChrome), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .forms: return 1
        case .protection: return VaultCrypto.hasMasterPassword ? 2 : 1
        case .passwords: return 3
        case .cards: return 1
        case .manage: return 2
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .forms: return "FORM AUTOFILL"
        case .protection: return "DATA PROTECTION"
        case .passwords: return "PASSWORDS"
        case .cards: return "BANK CARDS"
        case .manage: return "MANAGE"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .forms:
            return "The browser can fill name, email, phone, and address fields from your saved profile."
        case .protection:
            return "Protect saved passwords and cards with a single master password."
        case .passwords:
            return "Turn on AutoFill Passwords for XBrowser in iOS Settings to use saved logins in other apps."
        case .cards:
            return "The browser will suggest saved card details in payment forms when enabled."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.textLabel?.numberOfLines = 2
        cell.imageView?.image = nil

        switch Section(rawValue: indexPath.section)! {
        case .forms:
            cell.selectionStyle = .none
            cell.textLabel?.text = "AutoFill forms"
            cell.accessoryView = makeSwitch(isOn: PasswordSettings.autofillForms, action: #selector(toggleForms(_:)))
        case .protection:
            if indexPath.row == 0 {
                cell.textLabel?.textColor = BrowserTheme.chromeBlue
                cell.textLabel?.text = VaultCrypto.hasMasterPassword
                    ? "Change master password"
                    : "Create a master password"
            } else {
                cell.textLabel?.textColor = .systemRed
                cell.textLabel?.text = "Remove master password"
            }
        case .passwords:
            switch indexPath.row {
            case 0:
                cell.selectionStyle = .none
                cell.textLabel?.text = "AutoFill passwords"
                cell.accessoryView = makeSwitch(isOn: PasswordSettings.autofillPasswords, action: #selector(togglePasswords(_:)))
            case 1:
                cell.selectionStyle = .none
                cell.textLabel?.text = "Automatically save new passwords"
                cell.accessoryView = makeSwitch(isOn: PasswordSettings.autoSavePasswords, action: #selector(toggleAutoSave(_:)))
            default:
                cell.textLabel?.textColor = BrowserTheme.chromeBlue
                cell.textLabel?.text = "AutoFill passwords from XBrowser in other applications"
            }
        case .cards:
            cell.selectionStyle = .none
            cell.textLabel?.text = "AutoFill card details"
            cell.accessoryView = makeSwitch(isOn: PasswordSettings.autofillBankCards, action: #selector(toggleCards(_:)))
        case .manage:
            cell.accessoryType = .disclosureIndicator
            cell.textLabel?.text = indexPath.row == 0 ? "Form profile" : "Bank cards"
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .protection:
            if indexPath.row == 0 {
                presentMaster(mode: VaultCrypto.hasMasterPassword ? .change : .create)
            } else {
                presentMaster(mode: .remove)
            }
        case .passwords where indexPath.row == 2:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .manage:
            if indexPath.row == 0 {
                navigationController?.pushViewController(FormProfileViewController(), animated: true)
            } else {
                navigationController?.pushViewController(BankCardsViewController(), animated: true)
            }
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    private func makeSwitch(isOn: Bool, action: Selector) -> UISwitch {
        let sw = UISwitch()
        sw.isOn = isOn
        sw.addTarget(self, action: action, for: .valueChanged)
        return sw
    }

    @objc private func toggleForms(_ sw: UISwitch) { PasswordSettings.autofillForms = sw.isOn }
    @objc private func togglePasswords(_ sw: UISwitch) { PasswordSettings.autofillPasswords = sw.isOn }
    @objc private func toggleAutoSave(_ sw: UISwitch) { PasswordSettings.autoSavePasswords = sw.isOn }
    @objc private func toggleCards(_ sw: UISwitch) { PasswordSettings.autofillBankCards = sw.isOn }

    private func presentMaster(mode: MasterPasswordSetupViewController.Mode) {
        let vc = MasterPasswordSetupViewController(mode: mode)
        vc.onFinished = { [weak self] in self?.tableView.reloadData() }
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        BrowserTheme.applyNavigationBar(to: nav.navigationBar)
        present(nav, animated: true)
    }
}
