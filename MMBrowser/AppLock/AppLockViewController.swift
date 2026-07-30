import UIKit
import SnapKit

protocol AppLockViewControllerDelegate: AnyObject {
    func appLockDidUnlock(_ controller: AppLockViewController)
    func appLockDidDisableLock(_ controller: AppLockViewController)
}

/// Full-screen unlock UI styled like iOS passcode / pattern lock.
final class AppLockViewController: UIViewController {
    weak var delegate: AppLockViewControllerDelegate?

    private let titleLabel = UILabel()
    private let dotsView = PasscodeDotsView(count: 4)
    private let keypad = PasscodeKeypadView()
    private let patternView = PatternLockView()
    private let bioButton = UIButton(type: .system)
    private let disableButton = UIButton(type: .system)
    private var pinValue = ""
    private var idleTitle = "Enter Passcode"

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        titleLabel.font = .systemFont(ofSize: 22, weight: .regular)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        keypad.delegate = self
        patternView.delegate = self

        configureBioButtonChrome()
        bioButton.addTarget(self, action: #selector(bioTapped), for: .touchUpInside)

        disableButton.setTitle("Turn Off App Lock", for: .normal)
        disableButton.setTitleColor(UIColor.white.withAlphaComponent(0.55), for: .normal)
        disableButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
        disableButton.addTarget(self, action: #selector(disableTapped), for: .touchUpInside)
        disableButton.isHidden = true

        view.addSubview(titleLabel)
        view.addSubview(dotsView)
        view.addSubview(keypad)
        view.addSubview(patternView)
        view.addSubview(bioButton)
        view.addSubview(disableButton)

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(88)
            make.leading.trailing.equalToSuperview().inset(32)
        }
        dotsView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(28)
            make.centerX.equalToSuperview()
            make.height.equalTo(16)
        }
        keypad.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-28)
        }
        patternView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(titleLabel.snp.bottom).offset(48)
            make.width.height.equalTo(min(UIScreen.main.bounds.width - 48, 320))
        }
        disableButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-12)
        }

        configureForCurrentMethods()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if AppLockSettings.biometricsEnabled {
            attemptBiometrics(auto: true)
        }
    }

    private func configureBioButtonChrome() {
        bioButton.tintColor = .white
        bioButton.setImage(UIImage(systemName: AppLockBiometrics.systemImageName), for: .normal)
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        bioButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
        bioButton.accessibilityLabel = "Unlock with \(AppLockBiometrics.biometryDisplayName)"
    }

    private func configureForCurrentMethods() {
        let method = AppLockSettings.primaryMethod
        let bio = AppLockSettings.biometricsEnabled

        dotsView.isHidden = method != .pin
        keypad.isHidden = method != .pin
        patternView.isHidden = method != .pattern
        keypad.setBottomLeftAccessory(nil)
        bioButton.removeFromSuperview()
        view.addSubview(bioButton)

        switch method {
        case .pin:
            idleTitle = "Enter Passcode"
            titleLabel.text = idleTitle
        case .pattern:
            idleTitle = "Draw Pattern"
            titleLabel.text = idleTitle
        case .none:
            idleTitle = bio
                ? "Unlock with \(AppLockBiometrics.biometryDisplayName)"
                : "MMBrowser Locked"
            titleLabel.text = idleTitle
        }

        if bio && method == .pin {
            // System lock screen layout: Face ID / Touch ID sits bottom-left of the keypad.
            bioButton.setTitle(nil, for: .normal)
            bioButton.isHidden = false
            keypad.setBottomLeftAccessory(bioButton)
        } else if bio && method == .pattern {
            bioButton.setTitle(nil, for: .normal)
            bioButton.isHidden = false
            bioButton.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalTo(patternView.snp.bottom).offset(36)
                make.size.equalTo(44)
            }
        } else if bio && method == .none {
            bioButton.setTitle(nil, for: .normal)
            bioButton.isHidden = false
            bioButton.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalTo(titleLabel.snp.bottom).offset(40)
                make.size.equalTo(56)
            }
        } else {
            bioButton.isHidden = true
        }

        disableButton.isHidden = !(bio && method == .none)
    }

    @objc private func bioTapped() {
        attemptBiometrics(auto: false)
    }

    private func attemptBiometrics(auto: Bool) {
        guard AppLockSettings.biometricsEnabled else { return }
        AppLockBiometrics.authenticate(reason: "Unlock MMBrowser") { [weak self] success, message in
            guard let self = self else { return }
            if success {
                self.unlock()
            } else if !auto, let message = message {
                self.showError(message)
            }
        }
    }

    @objc private func disableTapped() {
        let alert = UIAlertController(
            title: "Turn Off App Lock?",
            message: "Without a PIN or pattern, failed biometrics can lock you out. Turning off App Lock will let you back in.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Turn Off", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            AppLockSecretStore.clearSecrets()
            AppLockSettings.clearAllFlags()
            self.delegate?.appLockDidDisableLock(self)
        })
        present(alert, animated: true)
    }

    private func showError(_ text: String) {
        // iOS passcode: primary title becomes the error / retry cue.
        titleLabel.text = text
        dotsView.shake()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func restoreIdleTitle() {
        titleLabel.text = idleTitle
    }

    private func unlock() {
        restoreIdleTitle()
        delegate?.appLockDidUnlock(self)
    }
}

extension AppLockViewController: PasscodeKeypadViewDelegate {
    func passcodeKeypad(_ view: PasscodeKeypadView, didTapDigit digit: String) {
        guard pinValue.count < 4 else { return }
        if titleLabel.text != idleTitle {
            restoreIdleTitle()
        }
        pinValue += digit
        dotsView.setFilledCount(pinValue.count)
        guard pinValue.count == 4 else { return }
        let pin = pinValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if AppLockSecretStore.verifyPIN(pin) {
                self.unlock()
            } else {
                self.showError("Incorrect Passcode")
                self.pinValue = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    self.dotsView.setFilledCount(0)
                    self.titleLabel.text = "Try Again"
                }
            }
        }
    }

    func passcodeKeypadDidTapDelete(_ view: PasscodeKeypadView) {
        guard !pinValue.isEmpty else { return }
        pinValue.removeLast()
        dotsView.setFilledCount(pinValue.count)
        if titleLabel.text != idleTitle {
            restoreIdleTitle()
        }
    }
}

extension AppLockViewController: PatternLockViewDelegate {
    func patternLockView(_ view: PatternLockView, didFinishPattern indices: [Int]) {
        if AppLockSecretStore.verifyPattern(indices) {
            unlock()
        } else {
            showError("Incorrect Pattern")
            view.flashError()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                self?.titleLabel.text = "Try Again"
            }
        }
    }
}
