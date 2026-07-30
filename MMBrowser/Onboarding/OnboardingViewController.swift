import UIKit
import SnapKit

final class OnboardingViewController: UIViewController {
    var onFinished: (() -> Void)?
    private let pageControl = UIPageControl()
    private let scrollView = UIScrollView()
    private var engineStack: UIStackView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        pageControl.numberOfPages = 3
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = BrowserTheme.chromeBlue
        pageControl.pageIndicatorTintColor = BrowserTheme.textSecondary
        view.addSubview(pageControl)

        let start = UIButton(type: .system)
        start.setTitle("Get Started", for: .normal)
        start.setTitleColor(.black, for: .normal)
        start.backgroundColor = BrowserTheme.chromeBlue
        start.layer.cornerRadius = 14
        start.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        start.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        view.addSubview(start)

        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(start.snp.top).offset(-16)
        }
        start.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-24)
            make.height.equalTo(52)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pageControl.snp.top).offset(-12)
        }

        view.layoutIfNeeded()
        let width = UIScreen.main.bounds.width
        scrollView.contentSize = CGSize(width: width * 3, height: 1)
        addPage(
            at: 0,
            title: "Private by default",
            body: "Block ads and trackers on the open web. Your browsing data stays on this device. Location is denied by default—sites that use GPS-like APIs won’t get your coordinates. Network IP geo-detection still needs a VPN or proxy to change."
        )
        addPage(
            at: 1,
            title: "Cleaner pages",
            body: "Fewer banners and trackers mean faster loads and less clutter—especially when you watch video in the browser."
        )
        let third = addPage(
            at: 2,
            title: "Focus Mode",
            body: "Hide YouTube Shorts shelves and open Shorts as normal videos. Choose your default search engine below."
        )
        let engineLabel = UILabel()
        engineLabel.text = "Default search engine"
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
            btn.snp.makeConstraints { $0.height.equalTo(44) }
            stack.addArrangedSubview(btn)
        }
        engineStack = stack
        let wrap = UIStackView(arrangedSubviews: [engineLabel, stack])
        wrap.axis = .vertical
        wrap.spacing = 12
        third.addSubview(wrap)
        wrap.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.bottom.equalToSuperview().offset(-24)
        }
    }

    @discardableResult
    private func addPage(at index: Int, title: String, body: String) -> UIView {
        let width = UIScreen.main.bounds.width
        let page = UIView()
        scrollView.addSubview(page)
        page.frame = CGRect(x: width * CGFloat(index), y: 0, width: width, height: 420)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 16
        page.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(48)
            make.leading.trailing.equalToSuperview().inset(28)
        }
        return page
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

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        pageControl.currentPage = page
    }
}
