import UIKit
import SnapKit

final class OnboardingViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let pageControl = UIPageControl()
    private let scrollView = UIScrollView()
    private var autoTimer: Timer?
    private var isUserInteracting = false
    private let autoInterval: TimeInterval = 3.6

    private let pageCopy: [(title: String, body: String, image: String)] = [
        (
            "Dual Accounts",
            "Separate logins, cookies, and location for work and personal—so sites only see the identity you choose.",
            "onboarding_privacy"
        ),
        (
            "Fewer Ads & Shorts",
            "Block ads and trackers as you browse. Shorts Focus hides YouTube Shorts so you stay on the videos you want.",
            "onboarding_cleaner"
        ),
        (
            "Lock & Clear",
            "Protect MMBrowser with Face ID, PIN, or pattern. Auto-clear browsing data when you leave.",
            "onboarding_focus"
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        scrollView.bounces = true
        view.addSubview(scrollView)

        pageControl.numberOfPages = pageCopy.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = BrowserTheme.chromeBlue
        pageControl.pageIndicatorTintColor = BrowserTheme.textSecondary.withAlphaComponent(0.45)
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        view.addSubview(pageControl)

        let start = UIButton(type: .system)
        start.setTitle("Get Started", for: .normal)
        start.setTitleColor(Self.contrastingLabel(on: BrowserTheme.chromeBlue), for: .normal)
        start.backgroundColor = BrowserTheme.chromeBlue
        start.layer.cornerRadius = 14
        start.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        start.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        view.addSubview(start)

        pageControl.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(start.snp.top).offset(-14)
        }
        start.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(28)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-20)
            make.height.equalTo(52)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pageControl.snp.top).offset(-8)
        }

        view.layoutIfNeeded()
        var previousPage: UIView?
        for (index, page) in pageCopy.enumerated() {
            let pageView = addPage(
                title: page.title,
                body: page.body,
                imageName: page.image,
                previous: previousPage,
                isLast: index == pageCopy.count - 1
            )
            previousPage = pageView
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startAutoCycle()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopAutoCycle()
    }

    deinit {
        stopAutoCycle()
    }

    @discardableResult
    private func addPage(
        title: String,
        body: String,
        imageName: String,
        previous: UIView?,
        isLast: Bool
    ) -> UIView {
        let page = UIView()
        scrollView.addSubview(page)
        page.snp.makeConstraints { make in
            make.top.bottom.equalTo(scrollView.frameLayoutGuide)
            make.height.equalTo(scrollView.frameLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
            if let previous {
                make.leading.equalTo(previous.snp.trailing)
            } else {
                make.leading.equalTo(scrollView.contentLayoutGuide)
            }
            if isLast {
                make.trailing.equalTo(scrollView.contentLayoutGuide)
            }
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let imageCard = UIView()
        imageCard.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        imageCard.layer.cornerRadius = 22
        imageCard.clipsToBounds = true

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageCard.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))
        }

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 10
        textStack.setContentHuggingPriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)

        let stack = UIStackView(arrangedSubviews: [textStack, imageCard])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        page.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().offset(-4)
        }
        return page
    }

    private func startAutoCycle() {
        stopAutoCycle()
        guard !isUserInteracting else { return }
        let timer = Timer(timeInterval: autoInterval, repeats: true) { [weak self] _ in
            self?.advanceAutomatically()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
    }

    private func stopAutoCycle() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    private func advanceAutomatically() {
        guard !isUserInteracting, scrollView.bounds.width > 1 else { return }
        let next = (pageControl.currentPage + 1) % pageCopy.count
        scrollToPage(next, animated: true)
    }

    private func scrollToPage(_ page: Int, animated: Bool) {
        let width = scrollView.bounds.width
        guard width > 1 else { return }
        let offset = CGPoint(x: width * CGFloat(page), y: 0)
        scrollView.setContentOffset(offset, animated: animated)
        pageControl.currentPage = page
    }

    @objc private func pageControlChanged() {
        isUserInteracting = true
        stopAutoCycle()
        scrollToPage(pageControl.currentPage, animated: true)
        resumeAutoCycleSoon()
    }

    private func resumeAutoCycleSoon() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(resumeAutoCycle), object: nil)
        perform(#selector(resumeAutoCycle), with: nil, afterDelay: 4.0)
    }

    @objc private func resumeAutoCycle() {
        isUserInteracting = false
        startAutoCycle()
    }

    @objc private func startTapped() {
        AppSettings.didShowOnboarding = true
        stopAutoCycle()
        onFinished?()
    }

    private static func contrastingLabel(on background: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard background.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.62 ? BrowserTheme.textPrimary : .white
    }
}

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserInteracting = true
        stopAutoCycle()
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(resumeAutoCycle), object: nil)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            resumeAutoCycleSoon()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        resumeAutoCycleSoon()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updatePageControlFromScroll()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updatePageControlFromScroll()
    }

    private func updatePageControlFromScroll() {
        let width = max(scrollView.bounds.width, 1)
        let page = Int(round(scrollView.contentOffset.x / width))
        pageControl.currentPage = min(max(page, 0), pageCopy.count - 1)
    }
}
