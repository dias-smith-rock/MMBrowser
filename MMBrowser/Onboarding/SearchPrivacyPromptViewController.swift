import UIKit
import SnapKit

/// One-time search picker. Does not change the current engine until the user taps Continue.
final class SearchPrivacyPromptViewController: UIViewController {
    var onFinished: (() -> Void)?

    private var selectedID: String

    init(currentEngineID: String) {
        selectedID = currentEngineID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }

        let titleLabel = UILabel()
        titleLabel.text = "Choose your search engine"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 0

        let body = UILabel()
        body.text = "Privacy-friendly options like DuckDuckGo help reduce search profiling. You can change this anytime in Settings."
        body.font = .systemFont(ofSize: 15)
        body.textColor = BrowserTheme.textSecondary
        body.numberOfLines = 0

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        for engine in SearchEngine.privacyFriendly + SearchEngine.general {
            stack.addArrangedSubview(engineRow(engine))
        }

        let continueButton = UIButton(type: .system)
        continueButton.setTitle("Continue", for: .normal)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = BrowserTheme.chromeBlue
        continueButton.layer.cornerRadius = 12
        continueButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        let later = UIButton(type: .system)
        later.setTitle("Not now", for: .normal)
        later.setTitleColor(BrowserTheme.textSecondary, for: .normal)
        later.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        later.addTarget(self, action: #selector(notNowTapped), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(body)
        view.addSubview(stack)
        view.addSubview(continueButton)
        view.addSubview(later)

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        body.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        stack.snp.makeConstraints { make in
            make.top.equalTo(body.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        continueButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(48)
            make.bottom.equalTo(later.snp.top).offset(-8)
        }
        later.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(44)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-12)
        }
    }

    private func engineRow(_ engine: SearchEngine) -> UIButton {
        let button = UIButton(type: .system)
        let recommended = engine.id == SearchEngine.duckDuckGo.id
        let title = recommended ? "\(engine.name)  ·  Recommended" : engine.name
        button.setTitle(title, for: .normal)
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        button.layer.cornerRadius = 12
        button.tag = SearchEngine.all.firstIndex(where: { $0.id == engine.id }) ?? 0
        button.addTarget(self, action: #selector(engineTapped(_:)), for: .touchUpInside)
        button.accessibilityIdentifier = engine.id
        style(button, engine: engine)
        button.snp.makeConstraints { $0.height.equalTo(48) }
        return button
    }

    private func style(_ button: UIButton, engine: SearchEngine) {
        let selected = engine.id == selectedID
        button.backgroundColor = selected ? BrowserTheme.chromeBlue : BrowserTheme.card
        button.setTitleColor(selected ? .white : BrowserTheme.textPrimary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: selected ? .semibold : .regular)
    }

    @objc private func engineTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier else { return }
        selectedID = id
        for case let button as UIButton in (sender.superview as? UIStackView)?.arrangedSubviews ?? [] {
            if let engine = SearchEngine.all.first(where: { $0.id == button.accessibilityIdentifier }) {
                style(button, engine: engine)
            }
        }
    }

    @objc private func continueTapped() {
        if let engine = SearchEngine.all.first(where: { $0.id == selectedID }) {
            SearchEngineManager.setCurrent(engine)
        }
        finish()
    }

    @objc private func notNowTapped() {
        finish()
    }

    private func finish() {
        AppSettings.didShowSearchPrivacyPrompt = true
        let done = onFinished
        dismiss(animated: true) { done?() }
    }
}
