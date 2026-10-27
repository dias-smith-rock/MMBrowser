import UIKit
import SnapKit

/// One-time post–Spaces intro sheet for **new users only**: four capability cards.
final class FeatureHighlightsViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private var cards: [UIView] = []
    private var didFinish = false

    private let items: [(image: String, title: String, body: String)] = [
        (
            "highlight_ads",
            "Private by default",
            "Ads and trackers are blocked, HTTPS is preferred, and Global Privacy Control is on. Protections are best-effort—not anonymity, and not a VPN."
        ),
        (
            "highlight_spaces",
            "Multi-account isolation",
            "Spaces keep separate cookies, history, and logins—so WhatsApp, Instagram, and shopping accounts never mix."
        ),
        (
            "highlight_locks",
            "App Lock & Space Lock",
            "Protect the whole app with App Lock. Each Space stays isolated, and Space Lock (Premium) can PIN-protect a single identity."
        ),
        (
            "highlight_playback",
            "Play with the screen locked",
            "Background Audio and Picture in Picture keep supported web video and audio playing after you leave the app or lock the screen."
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background
        // First-run uses `.fullScreen` (set by presenter); sheet is only a fallback.
        if modalPresentationStyle != .fullScreen {
            modalPresentationStyle = .pageSheet
            if let sheet = sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
            }
        }
        presentationController?.delegate = self

        let titleLabel = UILabel()
        titleLabel.text = "Private by default. Isolated by Space."
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = "Ads and trackers blocked, accounts never mix—plus playback when you leave the app."
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
        continueButton.setTitle("Get Started", for: .normal)
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
            make.top.equalTo(view.safeAreaLayoutGuide).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        subtitle.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(28)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(subtitle.snp.bottom).offset(12)
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
            let card = makeCard(imageName: item.image, title: item.title, body: item.body)
            scrollView.addSubview(card)
            cards.append(card)
        }
    }

    private func layoutCards() {
        let width = scrollView.bounds.width
        let height = scrollView.bounds.height
        guard width > 1, height > 1 else { return }
        for (index, card) in cards.enumerated() {
            card.frame = CGRect(x: CGFloat(index) * width + 20, y: 0, width: width - 40, height: height)
        }
        scrollView.contentSize = CGSize(width: width * CGFloat(cards.count), height: height)
    }

    private func makeCard(imageName: String, title: String, body: String) -> UIView {
        let card = UIView()
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 18
        card.clipsToBounds = true

        let imageCard = UIView()
        imageCard.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        imageCard.layer.cornerRadius = 16
        imageCard.clipsToBounds = true

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageCard.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(6)
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        bodyLabel.setContentHuggingPriority(.required, for: .vertical)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 8
        textStack.alignment = .fill
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [imageCard, textStack])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        card.addSubview(stack)

        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.leading.trailing.equalToSuperview().inset(14)
            make.bottom.equalToSuperview().offset(-14)
        }
        // Keep illustration dominant but leave room for copy on short sheets.
        imageCard.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(180)
            make.height.equalTo(stack.snp.height).multipliedBy(0.58).priority(.high)
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
