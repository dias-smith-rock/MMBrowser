import UIKit
import SnapKit

/// First-run guided demo: compare two accounts on the same site.
final class AccountOnboardingWowViewController: UIViewController {
    var onFinished: (() -> Void)?
    /// Called after the user starts Split View (sheet can dismiss underneath).
    var onStartedSplitDemo: (() -> Void)?

    private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        modalPresentationStyle = .formSheet

        let titleLabel = UILabel()
        titleLabel.text = "Two WhatsApp sessions, zero mixing"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        let bodyLabel = UILabel()
        bodyLabel.text = "We’ll open WhatsApp Web in two accounts, one above the other. Scan or sign in on one side only — the other stays separate."
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        let imageCard = UIView()
        imageCard.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        imageCard.layer.cornerRadius = 22
        imageCard.clipsToBounds = true

        let imageView = UIImageView(image: UIImage(named: "onboarding_split"))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.accessibilityLabel = "Split View with two WhatsApp Web sessions"
        imageCard.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }

        let tryButton = UIButton(type: .system)
        tryButton.setTitle("Try WhatsApp Split View", for: .normal)
        tryButton.backgroundColor = BrowserTheme.chromeBlue
        tryButton.setTitleColor(.white, for: .normal)
        tryButton.layer.cornerRadius = 12
        tryButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        tryButton.addTarget(self, action: #selector(tryTapped), for: .touchUpInside)

        let later = UIButton(type: .system)
        later.setTitle("Maybe Later", for: .normal)
        later.addTarget(self, action: #selector(laterTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 10

        let content = UIStackView(arrangedSubviews: [textStack, imageCard])
        content.axis = .vertical
        content.spacing = 16
        content.alignment = .fill

        view.addSubview(content)
        view.addSubview(tryButton)
        view.addSubview(later)

        later.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-16)
        }
        tryButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(later.snp.top).offset(-12)
            make.height.equalTo(48)
        }
        content.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.lessThanOrEqualTo(tryButton.snp.top).offset(-16)
        }
        imageCard.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(180)
            make.height.equalTo(imageCard.snp.width).multipliedBy(0.92).priority(.high)
        }
    }

    @objc private func tryTapped() {
        UserDefaults.standard.set(true, forKey: ContainerScope.didShowAccountWowKey)
        UserDefaults.standard.set(false, forKey: ContainerScope.needsAccountChipTipKey)
        let containers = tabManager.sortedContainers
        guard containers.count >= 2,
              let url = URL(string: "https://web.whatsapp.com") else {
            dismiss(animated: true) { self.onFinished?() }
            return
        }
        onStartedSplitDemo?()
        let compare = DualAccountCompareViewController(
            tabManager: tabManager,
            leftContainer: containers[0],
            rightContainer: containers[1],
            url: url
        )
        compare.modalPresentationStyle = .fullScreen
        present(compare, animated: true)
    }

    @objc private func laterTapped() {
        UserDefaults.standard.set(true, forKey: ContainerScope.didShowAccountWowKey)
        UserDefaults.standard.set(true, forKey: ContainerScope.needsAccountChipTipKey)
        dismiss(animated: true) { self.onFinished?() }
    }
}
