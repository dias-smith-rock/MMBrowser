import UIKit

final class AppLockSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case status, methods, biometrics }
    private enum StatusRow: Int { case master = 0, lockAfter = 1 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App Lock"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .status: return 2
        case .methods: return 2
        case .biometrics: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .status: return "Status"
        case .methods: return "Unlock Method"
        case .biometrics: return AppLockBiometrics.biometryDisplayName
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .status:
            return "When enabled, MMBrowser locks on launch and after being in the background longer than Lock After."
        case .methods:
            return "Choose a 4-digit PIN or a pattern. Setting one replaces the other."
        case .biometrics:
            switch AppLockBiometrics.availability() {
            case .available:
                return "You can enable \(AppLockBiometrics.biometryDisplayName) alone, or together with a PIN/pattern. Without a PIN/pattern, the lock screen includes a way to turn App Lock off if biometrics fail."
            case .unavailable(let reason):
                return reason
            }
        }
    }

    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let rowCell = UITableViewCell(style: .value1, reuseIdentifier: "value1")
        rowCell.backgroundColor = BrowserTheme.card
        rowCell.textLabel?.textColor = BrowserTheme.textPrimary
        rowCell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        rowCell.detailTextLabel?.text = nil
        rowCell.accessoryView = nil
        rowCell.accessoryType = .none
        rowCell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .status:
            if indexPath.row == StatusRow.master.rawValue {
                rowCell.textLabel?.text = "App Lock"
                rowCell.selectionStyle = .none
                let sw = UISwitch()
                sw.isOn = AppLockSettings.isEnabled
                sw.addTarget(self, action: #selector(masterToggled(_:)), for: .valueChanged)
                rowCell.accessoryView = sw
            } else {
                rowCell.textLabel?.text = "Lock After"
                rowCell.detailTextLabel?.text = AppLockSettings.gracePeriod.shortDisplayName
                rowCell.accessoryType = .disclosureIndicator
            }
        case .methods:
            if indexPath.row == 0 {
                rowCell.textLabel?.text = "4-Digit PIN"
                rowCell.detailTextLabel?.text = AppLockSettings.primaryMethod == .pin ? "On" : "Off"
                rowCell.accessoryType = .disclosureIndicator
            } else {
                rowCell.textLabel?.text = "Pattern"
                rowCell.detailTextLabel?.text = AppLockSettings.primaryMethod == .pattern ? "On" : "Off"
                rowCell.accessoryType = .disclosureIndicator
            }
        case .biometrics:
            rowCell.textLabel?.text = AppLockBiometrics.biometryDisplayName
            rowCell.selectionStyle = .none
            let sw = UISwitch()
            sw.isOn = AppLockSettings.biometricsEnabled
            if case .unavailable = AppLockBiometrics.availability() {
                sw.isEnabled = false
            }
            sw.addTarget(self, action: #selector(bioToggled(_:)), for: .valueChanged)
            rowCell.accessoryView = sw
        }
        return rowCell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .status:
            guard indexPath.row == StatusRow.lockAfter.rawValue else { return }
            let picker = AppLockGracePeriodViewController()
            navigationController?.pushViewController(picker, animated: true)
        case .methods:
            if indexPath.row == 0 {
                beginChange(to: .pin)
            } else {
                beginChange(to: .pattern)
            }
        case .biometrics:
            break
        }
    }

    private func beginChange(to method: AppLockPrimaryMethod) {
        if AppLockSettings.isEnabled {
            authenticateThen {
                let mode: AppLockSetupMode = method == .pin
                    ? .verifyThen(action: .changeToPIN)
                    : .verifyThen(action: .changeToPattern)
                // If verifying with biometrics-only, skip verify and go create.
                if AppLockSettings.primaryMethod == .none {
                    let create: AppLockSetupMode = method == .pin ? .createPIN : .createPattern
                    self.pushSetup(create)
                } else {
                    self.pushSetup(mode)
                }
            }
        } else {
            let create: AppLockSetupMode = method == .pin ? .createPIN : .createPattern
            pushSetup(create)
        }
    }

    @objc private func masterToggled(_ sw: UISwitch) {
        if sw.isOn {
            sw.isOn = AppLockSettings.isEnabled
            let sheet = UIAlertController(title: "Enable App Lock", message: "Choose an unlock method", preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "4-Digit PIN", style: .default) { [weak self] _ in
                self?.pushSetup(.createPIN)
            })
            sheet.addAction(UIAlertAction(title: "Pattern", style: .default) { [weak self] _ in
                self?.pushSetup(.createPattern)
            })
            if case .available = AppLockBiometrics.availability() {
                sheet.addAction(UIAlertAction(title: "\(AppLockBiometrics.biometryDisplayName) Only", style: .default) { [weak self] _ in
                    self?.enableBioOnly()
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.tableView.reloadData()
            })
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = sw
                pop.sourceRect = sw.bounds
            }
            present(sheet, animated: true)
        } else {
            sw.isOn = true
            requestDisableLock()
        }
    }

    private func requestDisableLock() {
        if AppLockSettings.biometricsEnabled {
            AppLockBiometrics.authenticate(reason: "Turn off App Lock") { [weak self] success, _ in
                guard let self = self else { return }
                if success {
                    AppLockSecretStore.clearSecrets()
                    AppLockSettings.clearAllFlags()
                    self.tableView.reloadData()
                    return
                }
                if AppLockSettings.primaryMethod != .none {
                    self.pushSetup(.verifyThen(action: .disableLock))
                } else {
                    Toast.show("Authentication failed", from: self)
                    self.tableView.reloadData()
                }
            }
            return
        }
        if AppLockSettings.primaryMethod != .none {
            pushSetup(.verifyThen(action: .disableLock))
        } else {
            AppLockSettings.clearAllFlags()
            tableView.reloadData()
        }
    }

    @objc private func bioToggled(_ sw: UISwitch) {
        if sw.isOn {
            sw.isOn = false
            authenticateThen { [weak self] in
                guard let self = self else { return }
                AppLockBiometrics.authenticate(reason: "Enable \(AppLockBiometrics.biometryDisplayName)") { success, message in
                    if success {
                        AppLockSettings.biometricsEnabled = true
                        AppLockSettings.isEnabled = true
                        AppLockSettings.setupPromptCompleted = true
                    } else if let message = message {
                        Toast.show(message, from: self)
                    }
                    self.tableView.reloadData()
                }
            }
        } else {
            sw.isOn = true
            authenticateThen { [weak self] in
                AppLockSettings.biometricsEnabled = false
                if AppLockSettings.primaryMethod == .none {
                    AppLockSettings.isEnabled = false
                }
                self?.tableView.reloadData()
            }
        }
    }

    private func enableBioOnly() {
        let alert = UIAlertController(
            title: "Biometrics Only",
            message: "If biometrics fail, you can turn off App Lock from the lock screen.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            AppLockBiometrics.authenticate(reason: "Enable App Lock") { success, message in
                if success {
                    AppLockSecretStore.clearSecrets()
                    AppLockSettings.primaryMethod = .none
                    AppLockSettings.biometricsEnabled = true
                    AppLockSettings.isEnabled = true
                    AppLockSettings.setupPromptCompleted = true
                } else if let self = self, let message = message {
                    Toast.show(message, from: self)
                }
                self?.tableView.reloadData()
            }
        })
        present(alert, animated: true)
    }

    /// Authenticate with current methods before sensitive changes.
    private func authenticateThen(_ work: @escaping () -> Void) {
        if !AppLockSettings.isEnabled {
            work()
            return
        }
        if AppLockSettings.biometricsEnabled {
            AppLockBiometrics.authenticate(reason: "Confirm to change App Lock") { success, _ in
                if success {
                    work()
                } else if AppLockSettings.primaryMethod != .none {
                    // Fall through to PIN/pattern verify UI.
                    work()
                } else {
                    Toast.show("Authentication failed", from: self)
                    self.tableView.reloadData()
                }
            }
            return
        }
        if AppLockSettings.primaryMethod != .none {
            work()
            return
        }
        work()
    }

    private func pushSetup(_ mode: AppLockSetupMode) {
        let setup = AppLockSetupViewController(mode: mode)
        setup.delegate = self
        // Prefer full-screen system passcode chrome even from Settings.
        let nav = UINavigationController(rootViewController: setup)
        nav.modalPresentationStyle = .fullScreen
        nav.setNavigationBarHidden(true, animated: false)
        present(nav, animated: true)
    }
}

extension AppLockSettingsViewController: AppLockSetupViewControllerDelegate {
    func appLockSetupDidFinish(_ controller: AppLockSetupViewController, success: Bool) {
        tableView.reloadData()
    }
}

/// System-style single-select list for background lock grace period.
final class AppLockGracePeriodViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let options = AppLockGracePeriod.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lock After"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Require unlock after MMBrowser has been in the background for this long."
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let option = options[indexPath.row]
        BrowserTheme.styleListCell(cell)
        cell.textLabel?.text = option.displayName
        cell.accessoryType = option == AppLockSettings.gracePeriod ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        AppLockSettings.gracePeriod = options[indexPath.row]
        tableView.reloadData()
        // Pop after a short beat so the checkmark is visible, like Settings.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
    }
}

