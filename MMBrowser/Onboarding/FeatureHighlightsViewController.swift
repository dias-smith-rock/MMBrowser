import UIKit
import SnapKit

/// One-time post–Spaces intro sheet for **new users only**: four capability cards.
final class FeatureHighlightsViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private var cards: [UIView] = []
    private var didFinish = false

    private let items: [(symbol: String, title: String, body: String)] = [
        (
            "person.2.fill",
            "Multi-account isolation",
            "Spaces keep separate cookies, history, and logins—so WhatsApp, Instagram, and shopping accounts never mix."
        ),
        (
            "lock.shield.fill",
            "App Lock & Space Lock",
            "Protect the whole app with App Lock. Each Space stays isolated, and Space Lock (Premium) can PIN-protect a single identity."
        ),
        (
            "shield.checkered",
            "Fewer pop-ups & video ads",
            "Block Ads & Trackers cuts network ads, trackers, and common pop-up banners. Fewer YouTube video ads is best-effort and may change when the site updates."
        ),
        (
            "play.circle.fill",
            "Play with the screen locked",
            "Background Audio and Picture in Picture keep supported web video and audio playing after you leave the app or lock the screen."
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        modalPresentationStyle = .pageSheet
        presentationController?.delegate = self
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }

        let titleLabel = UILabel()
        titleLabel.text = "Built for how you browse"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = "A quick look at protections and playback—beyond multiple logins."
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = BrowserTheme.textSecondary
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.bounces = true

        pageControl.numberOfPages = items.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = BrowserTheme.chromeBlue
        pageControl.pageIndicatorTintColor = BrowserTheme.textSecondary.withAlphaComponent(0.45)
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)

        let continueButton = UIButton(type: .system)
        continueButton.setTitle("Continue", for: .normal)
        continueButton.setTitleColor(.white, for: .normal)
        continueButton.backgroundColor = BrowserTheme.chromeBlue
        continueButton.layer.cornerRadius = 14
        continueButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(subtitle)
        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(continueButton)

        continueButton.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-16)
            make.height.equalTo(52)
        }
        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(continueButton.snp.top).offset(-12)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        subtitle.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(28)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(subtitle.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pageControl.snp.top).offset(-8)
        }

        view.layoutIfNeeded()
        buildCards()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCards()
    }

    private func buildCards() {
        for item in items {
            let card = makeCard(symbol: item.symbol, title: item.title, body: item.body)
            scrollView.addSubview(card)
            cards.append(card)
        }
    }

    private func layoutCards() {
        let width = scrollView.bounds.width
        let height = scrollView.bounds.height
        guard width > 1, height > 1 else { return }
        for (index, card) in cards.enumerated() {
            card.frame = CGRect(x: CGFloat(index) * width + 24, y: 0, width: width - 48, height: height)
        }
        scrollView.contentSize = CGSize(width: width * CGFloat(cards.count), height: height)
    }

    private func makeCard(symbol: String, title: String, body: String) -> UIView {
        let card = UIView()
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 18
        card.clipsToBounds = true

        let iconWrap = UIView()
        iconWrap.backgroundColor = BrowserTheme.chromeBlue.withAlphaComponent(0.16)
        iconWrap.layer.cornerRadius = 28

        let icon = UIImageView(
            image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        )
        icon.tintColor = BrowserTheme.chromeBlue
        icon.contentMode = .scaleAspectFit
        iconWrap.addSubview(icon)
        icon.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(32)
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [iconWrap, titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .center
        card.addSubview(stack)

        iconWrap.snp.makeConstraints { $0.size.equalTo(56) }
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(20)
            make.centerY.equalToSuperview()
        }
        return card
    }

    @objc private func pageControlChanged() {
        let x = CGFloat(pageControl.currentPage) * scrollView.bounds.width
        scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: true)
    }

    @objc private func continueTapped() {
        finish(tipID: "feature_highlights_done")
    }

    private func finish(tipID: String) {
        guard !didFinish else { return }
        didFinish = true
        AppSettings.didShowFeatureHighlights = true
        AppAnalytics.logTipShown(tipID: tipID)
        onFinished?()
    }
}

extension FeatureHighlightsViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 1 else { return }
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        pageControl.currentPage = min(max(page, 0), items.count - 1)
    }
}

extension FeatureHighlightsViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(tipID: "feature_highlights_dismiss")
    }
}
