import UIKit
import SnapKit

final class OnboardingViewController: UIViewController {
    var onFinished: (() -> Void)?
    private let pageControl = UIPageControl()
    private let scrollView = UIScrollView()

    private let pageCopy: [(title: String, body: String, image: String)] = [
        (
            "Privacy & Security",
            "Spoof or deny location so sites don’t get your real GPS. Turn on App Lock with Face ID, PIN, or pattern to keep your browsing private.",
            "onboarding_privacy"
        ),
        (
            "Fast & Clean",
            "Block ads and trackers, hide images when you need speed, clean cluttered pages, and auto-clear history and junk when you leave the app.",
            "onboarding_cleaner"
        ),
        (
            "Easy to Use",
            "Capture long screenshots of full pages, and use two-finger gestures—like a checkmark to bookmark or a circle to reload—for quicker actions.",
            "onboarding_focus"
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        pageControl.numberOfPages = pageCopy.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = BrowserTheme.chromeBlue
        pageControl.pageIndicatorTintColor = BrowserTheme.textSecondary
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
        scrollView.contentSize = CGSize(width: width * CGFloat(pageCopy.count), height: 1)

        for (index, page) in pageCopy.enumerated() {
            addPage(at: index, title: page.title, body: page.body, imageName: page.image)
        }
    }

    @discardableResult
    private func addPage(at index: Int, title: String, body: String, imageName: String) -> UIView {
        let width = UIScreen.main.bounds.width
        let page = UIView()
        scrollView.addSubview(page)
        page.snp.makeConstraints { make in
            make.top.bottom.equalTo(scrollView.frameLayoutGuide)
            make.height.equalTo(scrollView.frameLayoutGuide)
            make.width.equalTo(width)
            make.leading.equalTo(scrollView.contentLayoutGuide).offset(width * CGFloat(index))
            if index == pageCopy.count - 1 {
                make.trailing.equalTo(scrollView.contentLayoutGuide)
            }
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.textColor = BrowserTheme.textSecondary
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [textStack, imageView])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        page.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(28)
            make.leading.trailing.equalToSuperview().inset(28)
            make.bottom.equalToSuperview().offset(-12)
        }
        imageView.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(180)
        }
        return page
    }

    @objc private func startTapped() {
        AppSettings.didShowOnboarding = true
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
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        pageControl.currentPage = page
    }
}
