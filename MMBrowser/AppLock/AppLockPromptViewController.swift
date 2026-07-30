import UIKit
import SnapKit

/// First-webpage prompt to optionally enable App Lock.
final class AppLockPromptViewController: UIViewController {
    var onFinished: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.elevated

        let title = UILabel()
        title.text = "Protect MMBrowser?"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let body = UILabel()
        body.text = "Lock the app with a PIN, pattern, or \(AppLockBiometrics.biometryDisplayName). You can change this anytime in Settings."
        body.font = .systemFont(ofSize: 15)
        body.textColor = BrowserTheme.textSecondary
        body.numberOfLines = 0
        body.textAlignment = .center

        let pinButton = makeButton(title: "Set 4-Digit PIN", action: #selector(setPIN))
        let patternButton = makeButton(title: "Set Pattern", action: #selector(setPattern))
        let bioButton = makeButton(title: "Use \(AppLockBiometrics.biometryDisplayName) Only", action: #selector(setBioOnly))
        let laterButton = UIButton(type: .system)
        laterButton.setTitle("Not Now", for: .normal)
        laterButton.setTitleColor(BrowserTheme.textSecondary, for: .normal)
        laterButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        laterButton.addTarget(self, action: #selector(later), for: .touchUpInside)

        if case .unavailable = AppLockBiometrics.availability() {
            bioButton.isEnabled = false
            bioButton.alpha = 0.45
        }

        let stack = UIStackView(arrangedSubviews: [title, body, pinButton, patternButton, bioButton, laterButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(20, after: body)
        view.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = BrowserTheme.chromeBlue
        button.layer.cornerRadius = 12
        button.snp.makeConstraints { $0.height.equalTo(48) }
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func setPIN() {
        let setup = AppLockSetupViewController(mode: .createPIN)
        setup.delegate = self
        let nav = UINavigationController(rootViewController: setup)
        nav.modalPresentationStyle = .fullScreen
        nav.setNavigationBarHidden(true, animated: false)
        present(nav, animated: true)
    }

    @objc private func setPattern() {
        let setup = AppLockSetupViewController(mode: .createPattern)
        setup.delegate = self
        let nav = UINavigationController(rootViewController: setup)
        nav.modalPresentationStyle = .fullScreen
        nav.setNavigationBarHidden(true, animated: false)
        present(nav, animated: true)
    }

    @objc private func setBioOnly() {
        let alert = UIAlertController(
            title: "Biometrics Only",
            message: "If \(AppLockBiometrics.biometryDisplayName) fails and you have no PIN or pattern, you can turn off App Lock from the lock screen. Continue?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            AppLockBiometrics.authenticate(reason: "Enable App Lock") { success, message in
                guard success else {
                    if let self = self, let message = message {
                        Toast.show(message, from: self)
                    }
                    return
                }
                AppLockSettings.biometricsEnabled = true
                AppLockSettings.primaryMethod = .none
                AppLockSettings.isEnabled = true
                AppLockSettings.setupPromptCompleted = true
                self?.dismissPrompt()
            }
        })
        present(alert, animated: true)
    }

    @objc private func later() {
        AppLockSettings.setupPromptDismissed = true
        dismissPrompt()
    }

    private func dismissPrompt() {
        dismiss(animated: true) { [weak self] in
            self?.onFinished?()
        }
    }
}

extension AppLockPromptViewController: AppLockSetupViewControllerDelegate {
    func appLockSetupDidFinish(_ controller: AppLockSetupViewController, success: Bool) {
        if success {
            dismissPrompt()
        }
    }
}
