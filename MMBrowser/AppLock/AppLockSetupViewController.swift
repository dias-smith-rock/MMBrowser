import UIKit
import SnapKit

enum AppLockSetupMode {
    case createPIN
    case createPattern
    case confirmPIN(first: String)
    case confirmPattern(first: [Int])
    case verifyThen(action: AppLockVerifyAction)
}

enum AppLockVerifyAction {
    case disableLock
    case changeToPIN
    case changeToPattern
    case enableBiometrics
    case disableBiometrics
}

protocol AppLockSetupViewControllerDelegate: AnyObject {
    func appLockSetupDidFinish(_ controller: AppLockSetupViewController, success: Bool)
}

final class AppLockSetupViewController: UIViewController {
    weak var delegate: AppLockSetupViewControllerDelegate?

    private var mode: AppLockSetupMode
    private let titleLabel = UILabel()
    private let dotsView = PasscodeDotsView(count: 4)
    private let keypad = PasscodeKeypadView()
    private let patternView = PatternLockView()
    private var pinValue = ""
    private let cancelButton = UIButton(type: .system)

    init(mode: AppLockSetupMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.setNavigationBarHidden(true, animated: false)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        titleLabel.font = .systemFont(ofSize: 22, weight: .regular)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        keypad.delegate = self
        patternView.delegate = self

        view.addSubview(cancelButton)
        view.addSubview(titleLabel)
        view.addSubview(dotsView)
        view.addSubview(keypad)
        view.addSubview(patternView)

        cancelButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.equalToSuperview().offset(20)
        }
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

        applyModeUI()
    }

    private func applyModeUI() {
        pinValue = ""
        dotsView.setFilledCount(0, animated: false)
        patternView.reset()
        titleLabel.textColor = .white

        switch mode {
        case .createPIN:
            // Matches Settings → Passcode: first entry then re-enter.
            titleLabel.text = "Enter a Passcode"
            showPIN(true)
        case .confirmPIN:
            titleLabel.text = "Re-enter your Passcode"
            showPIN(true)
        case .createPattern:
            titleLabel.text = "Draw a Pattern"
            showPIN(false)
        case .confirmPattern:
            titleLabel.text = "Re-draw your Pattern"
            showPIN(false)
        case .verifyThen:
            switch AppLockSettings.primaryMethod {
            case .pin:
                titleLabel.text = "Enter Passcode"
                showPIN(true)
            case .pattern:
                titleLabel.text = "Draw Pattern"
                showPIN(false)
            case .none:
                titleLabel.text = "Verify"
                showPIN(true)
                dotsView.isHidden = true
                keypad.isHidden = true
            }
        }
    }

    private func showPIN(_ show: Bool) {
        dotsView.isHidden = !show
        keypad.isHidden = !show
        patternView.isHidden = show
    }

    private func handlePINComplete(_ pin: String) {
        switch mode {
        case .createPIN:
            mode = .confirmPIN(first: pin)
            applyModeUI()
        case .confirmPIN(let first):
            if pin == first {
                guard AppLockSecretStore.setPIN(pin) else {
                    showError("Could Not Save Passcode")
                    return
                }
                AppLockSettings.isEnabled = true
                AppLockSettings.setupPromptCompleted = true
                finish(success: true, toast: "Passcode set")
            } else {
                showError("Passcodes Did Not Match")
                mode = .createPIN
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                    self?.applyModeUI()
                }
            }
        case .verifyThen(let action):
            if AppLockSecretStore.verifyPIN(pin) {
                perform(action)
            } else {
                showError("Incorrect Passcode")
                pinValue = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    self?.dotsView.setFilledCount(0)
                    self?.titleLabel.text = "Try Again"
                }
            }
        default:
            break
        }
    }

    private func handlePatternComplete(_ indices: [Int]) {
        switch mode {
        case .createPattern:
            mode = .confirmPattern(first: indices)
            applyModeUI()
        case .confirmPattern(let first):
            if indices == first {
                guard AppLockSecretStore.setPattern(indices) else {
                    showError("Could Not Save Pattern")
                    return
                }
                AppLockSettings.isEnabled = true
                AppLockSettings.setupPromptCompleted = true
                finish(success: true, toast: "Passcode set")
            } else {
                showError("Patterns Did Not Match")
                patternView.flashError()
                mode = .createPattern
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                    self?.applyModeUI()
                }
            }
        case .verifyThen(let action):
            if AppLockSecretStore.verifyPattern(indices) {
                perform(action)
            } else {
                showError("Incorrect Pattern")
                patternView.flashError()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                    self?.titleLabel.text = "Try Again"
                }
            }
        default:
            break
        }
    }

    private func perform(_ action: AppLockVerifyAction) {
        switch action {
        case .disableLock:
            AppLockSecretStore.clearSecrets()
            AppLockSettings.clearAllFlags()
            finish(success: true)
        case .changeToPIN:
            mode = .createPIN
            applyModeUI()
        case .changeToPattern:
            mode = .createPattern
            applyModeUI()
        case .enableBiometrics:
            AppLockSettings.biometricsEnabled = true
            AppLockSettings.isEnabled = true
            AppLockSettings.setupPromptCompleted = true
            finish(success: true)
        case .disableBiometrics:
            AppLockSettings.biometricsEnabled = false
            if AppLockSettings.primaryMethod == .none {
                AppLockSettings.isEnabled = false
            }
            finish(success: true)
        }
    }

    private func showError(_ text: String) {
        titleLabel.text = text
        dotsView.shake()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func finish(success: Bool, toast: String? = nil) {
        let toastHost: UIViewController? = {
            if let nav = navigationController {
                if nav.viewControllers.first === self {
                    return nav.presentingViewController
                }
                if let idx = nav.viewControllers.firstIndex(of: self), idx > 0 {
                    return nav.viewControllers[idx - 1]
                }
            }
            return presentingViewController
        }()

        let notifyAndToast = { [weak self] in
            guard let self = self else { return }
            self.delegate?.appLockSetupDidFinish(self, success: success)
            guard success, let toast = toast else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                let root = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: { $0.isKeyWindow })?
                    .rootViewController
                    ?? toastHost
                guard let root = root else { return }
                var top = root
                while let presented = top.presentedViewController { top = presented }
                Toast.show(toast, from: top)
            }
        }

        if let nav = navigationController, nav.viewControllers.first === self {
            dismiss(animated: true, completion: notifyAndToast)
        } else if navigationController != nil {
            navigationController?.popViewController(animated: true)
            notifyAndToast()
        } else {
            dismiss(animated: true, completion: notifyAndToast)
        }
    }

    @objc private func cancel() {
        finish(success: false)
    }
}

extension AppLockSetupViewController: PasscodeKeypadViewDelegate {
    func passcodeKeypad(_ view: PasscodeKeypadView, didTapDigit digit: String) {
        guard pinValue.count < 4 else { return }
        // Restore idle title if user starts typing after an error.
        switch mode {
        case .createPIN where titleLabel.text != "Enter a Passcode":
            titleLabel.text = "Enter a Passcode"
        case .confirmPIN where titleLabel.text != "Re-enter your Passcode":
            titleLabel.text = "Re-enter your Passcode"
        case .verifyThen where titleLabel.text == "Incorrect Passcode" || titleLabel.text == "Try Again":
            titleLabel.text = "Enter Passcode"
        default:
            break
        }

        pinValue += digit
        dotsView.setFilledCount(pinValue.count)
        guard pinValue.count == 4 else { return }
        let pin = pinValue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.handlePINComplete(pin)
        }
    }

    func passcodeKeypadDidTapDelete(_ view: PasscodeKeypadView) {
        guard !pinValue.isEmpty else { return }
        pinValue.removeLast()
        dotsView.setFilledCount(pinValue.count)
    }
}

extension AppLockSetupViewController: PatternLockViewDelegate {
    func patternLockView(_ view: PatternLockView, didFinishPattern indices: [Int]) {
        handlePatternComplete(indices)
    }
}
