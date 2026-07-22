import UIKit
import SnapKit

final class OnboardingViewController: UIViewController {
    var onFinished: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background

        let title = UILabel()
        title.text = "Welcome to MMBrowser"
        title.textColor = .white
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = UILabel()
        body.text = "Private by default tracking protection, Reader Mode, Reading List, Downloads, custom search engines, and a home page you control."
        body.textColor = BrowserTheme.textSecondary
        body.font = .systemFont(ofSize: 16)
        body.textAlignment = .center
        body.numberOfLines = 0

        let engineLabel = UILabel()
        engineLabel.text = "Choose your default search engine"
        engineLabel.textColor = .white
        engineLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        engineLabel.textAlignment = .center

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        for engine in SearchEngine.all {
            let btn = UIButton(type: .system)
            btn.setTitle(engine.name, for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = BrowserTheme.card
            btn.layer.cornerRadius = 12
            btn.tag = SearchEngine.all.firstIndex(of: engine) ?? 0
            btn.addTarget(self, action: #selector(engineTapped(_:)), for: .touchUpInside)
            btn.snp.makeConstraints { $0.height.equalTo(48) }
            stack.addArrangedSubview(btn)
        }

        let start = UIButton(type: .system)
        start.setTitle("Get Started", for: .normal)
        start.setTitleColor(.black, for: .normal)
        start.backgroundColor = BrowserTheme.chromeBlue
        start.layer.cornerRadius = 14
        start.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        start.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        let wrap = UIStackView(arrangedSubviews: [title, body, engineLabel, stack, start])
        wrap.axis = .vertical
        wrap.spacing = 20
        view.addSubview(wrap)
        wrap.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(28)
        }
        start.snp.makeConstraints { $0.height.equalTo(52) }
    }

    @objc private func engineTapped(_ sender: UIButton) {
        let engine = SearchEngine.all[sender.tag]
        SearchEngineManager.setCurrent(engine)
        Toast.show("Search: \(engine.name)", from: self)
    }

    @objc private func startTapped() {
        AppSettings.didShowOnboarding = true
        onFinished?()
    }
}
