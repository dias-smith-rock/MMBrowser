import UIKit
import SnapKit
import SafariServices
import StoreKit

/// Dark dual-plan paywall for XBrowser Premium.
final class PremiumPaywallViewController: UIViewController {
    private let source: String

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let featureList = PremiumFeatureListView()
    private let yearlyCard = PlanCardView()
    private let monthlyCard = PlanCardView()
    private let ctaButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let legalLabel = UILabel()
    private let statusLabel = UILabel()
    private let manageButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var selectedYearly = true
    private var isBusy = false

    private enum Legal {
        static let privacy = URL(string: "https://xxxxxbrowser.cc/privacy.html")!
        static let terms = URL(string: "https://xxxxxbrowser.cc/terms.html")!
    }

    init(source: String) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)

        buildUI()
        applySelection()
        AppAnalytics.logPaywallShow(source: source)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(premiumChanged),
            name: .premiumStatusDidChange,
            object: nil
        )

        Task { @MainActor in
            await PremiumStore.shared.refresh()
            reloadFromStore()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            if source == "cold_start", !PremiumStore.shared.isPremiumActive {
                PremiumPaywallGate.markColdStartDismissedToday()
            }
        }
    }

    @objc private func premiumChanged() {
        reloadFromStore()
    }

    private func buildUI() {
        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
            for: .normal
        )
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        titleLabel.text = "XBrowser Premium"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        featureList.configure(items: Self.premiumFeatureItems(subscribed: false))

        yearlyCard.onTap = { [weak self] in
            self?.selectedYearly = true
            self?.applySelection()
        }
        monthlyCard.onTap = { [weak self] in
            self?.selectedYearly = false
            self?.applySelection()
        }

        ctaButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        ctaButton.setTitleColor(.black, for: .normal)
        ctaButton.backgroundColor = UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1)
        ctaButton.layer.cornerRadius = 14
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)

        restoreButton.setTitle("Restore Purchases", for: .normal)
        restoreButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        restoreButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)

        manageButton.setTitle("Manage Subscription", for: .normal)
        manageButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        manageButton.setTitleColor(UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1), for: .normal)
        manageButton.addTarget(self, action: #selector(manageTapped), for: .touchUpInside)
        manageButton.isHidden = true

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        legalLabel.textAlignment = .center
        legalLabel.numberOfLines = 0
        legalLabel.isUserInteractionEnabled = true
        legalLabel.attributedText = legalAttributedText()
        let tap = UITapGestureRecognizer(target: self, action: #selector(legalTapped(_:)))
        legalLabel.addGestureRecognizer(tap)

        spinner.color = .white
        spinner.hidesWhenStopped = true

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alignment = .fill
        contentStack.addArrangedSubview(titleLabel)
        contentStack.setCustomSpacing(20, after: titleLabel)
        contentStack.addArrangedSubview(featureList)
        contentStack.setCustomSpacing(24, after: featureList)
        contentStack.addArrangedSubview(yearlyCard)
        contentStack.addArrangedSubview(monthlyCard)
        contentStack.setCustomSpacing(24, after: monthlyCard)
        contentStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(ctaButton)
        contentStack.addArrangedSubview(manageButton)
        contentStack.addArrangedSubview(restoreButton)
        contentStack.addArrangedSubview(legalLabel)

        ctaButton.snp.makeConstraints { $0.height.equalTo(52) }

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(closeButton)
        view.addSubview(spinner)

        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(56)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(24)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-40)
        }
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.size.equalTo(32)
        }
        spinner.snp.makeConstraints { $0.center.equalToSuperview() }
    }

    private func reloadFromStore() {
        let store = PremiumStore.shared
        let yearly = store.yearlyProduct
        let monthly = store.monthlyProduct

        let yearlyTrial = store.trialDays(for: yearly)
        let monthlyTrial = store.trialDays(for: monthly)

        yearlyCard.configure(
            title: "Yearly",
            price: store.displayPrice(for: yearly),
            detail: {
                var parts: [String] = []
                if let perMonth = store.yearlyPerMonthPriceText(for: yearly) {
                    parts.append("\(perMonth)/mo")
                }
                if let days = yearlyTrial {
                    parts.append("\(days)-day free trial")
                } else {
                    parts.append("Billed annually")
                }
                return parts.joined(separator: " · ")
            }(),
            badge: "Best Value"
        )

        monthlyCard.configure(
            title: "Monthly",
            price: store.displayPrice(for: monthly),
            detail: {
                if let days = monthlyTrial {
                    return "\(days)-day free trial · then \(store.displayPrice(for: monthly))/mo"
                }
                return "Billed monthly"
            }(),
            badge: nil
        )

        let subscribed = store.isPremiumActive
        yearlyCard.isHidden = subscribed
        monthlyCard.isHidden = subscribed
        ctaButton.isHidden = subscribed
        restoreButton.isHidden = subscribed
        manageButton.isHidden = !subscribed
        statusLabel.isHidden = !subscribed

        if subscribed {
            let plan: String = {
                switch store.activeProductID {
                case PremiumStore.yearlyProductID: return "Yearly"
                case PremiumStore.monthlyProductID: return "Monthly"
                default: return "Premium"
                }
            }()
            if let expiry = store.expirationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                statusLabel.text = "You’re on \(plan).\nRenews or expires \(formatter.string(from: expiry))."
            } else {
                statusLabel.text = "You’re on \(plan)."
            }
            featureList.configure(items: Self.premiumFeatureItems(subscribed: true))
        } else {
            featureList.configure(items: Self.premiumFeatureItems(subscribed: false))
            updateCTATitle()
        }
    }

    private static func premiumFeatureItems(subscribed: Bool) -> [PremiumFeatureListView.Item] {
        [
            .init(
                symbol: "square.stack.3d.up.fill",
                title: subscribed ? "Unlimited Spaces Unlocked" : "Unlimited Spaces",
                detail: subscribed
                    ? "Every identity stays separate — cookies, logins, and browsing data."
                    : "Keep every identity separate. Free includes \(PremiumStore.freeSpaceLimit) Spaces."
            ),
            .init(
                symbol: "lock.fill",
                title: subscribed ? "Space Lock Unlocked" : "Space Lock",
                detail: "Protect any Space with a PIN or pattern. Locked Spaces stay hidden in Second Lock sessions."
            )
        ]
    }

    private func applySelection() {
        yearlyCard.setSelected(selectedYearly)
        monthlyCard.setSelected(!selectedYearly)
        updateCTATitle()
    }

    private func updateCTATitle() {
        let store = PremiumStore.shared
        let product = selectedYearly ? store.yearlyProduct : store.monthlyProduct
        if let days = store.trialDays(for: product) {
            ctaButton.setTitle("Start \(days)-Day Free Trial", for: .normal)
        } else {
            ctaButton.setTitle("Subscribe", for: .normal)
        }
    }

    private func selectedProduct() -> Product? {
        selectedYearly ? PremiumStore.shared.yearlyProduct : PremiumStore.shared.monthlyProduct
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        ctaButton.isEnabled = !busy
        restoreButton.isEnabled = !busy
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func ctaTapped() {
        guard !isBusy else { return }
        guard let product = selectedProduct() else {
            Toast.show("Products unavailable. Try again later.", from: self)
            return
        }
        setBusy(true)
        AppAnalytics.logPurchaseStart(productID: product.id, source: source)
        Task { @MainActor in
            let outcome = await PremiumStore.shared.purchase(product)
            setBusy(false)
            switch outcome {
            case .success:
                AppAnalytics.logPurchaseSuccess(productID: product.id, source: source)
                Toast.show("Welcome to Premium", from: self)
                reloadFromStore()
            case .cancelled:
                AppAnalytics.logPurchaseFail(productID: product.id, source: source, reason: "cancelled")
            case .pending:
                AppAnalytics.logPurchaseFail(productID: product.id, source: source, reason: "pending")
                Toast.show("Purchase pending approval", from: self)
            case .failed(let message):
                AppAnalytics.logPurchaseFail(productID: product.id, source: source, reason: "failed")
                Toast.show(message, from: self)
            }
        }
    }

    @objc private func restoreTapped() {
        guard !isBusy else { return }
        setBusy(true)
        Task { @MainActor in
            let ok = await PremiumStore.shared.restore()
            setBusy(false)
            AppAnalytics.logRestore(success: ok, source: source)
            if ok {
                Toast.show("Premium restored", from: self)
                reloadFromStore()
            } else {
                Toast.show("No active subscription found", from: self)
            }
        }
    }

    @objc private func manageTapped() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    private func legalAttributedText() -> NSAttributedString {
        let text = "Cancel anytime. Auto-renews until canceled.\nTerms of Use  ·  Privacy Policy"
        let attr = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.45)
            ]
        )
        let termsRange = (text as NSString).range(of: "Terms of Use")
        let privacyRange = (text as NSString).range(of: "Privacy Policy")
        attr.addAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.75)], range: termsRange)
        attr.addAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.75)], range: privacyRange)
        return attr
    }

    @objc private func legalTapped(_ gesture: UITapGestureRecognizer) {
        guard let label = gesture.view as? UILabel, let text = label.attributedText?.string else { return }
        let termsRange = (text as NSString).range(of: "Terms of Use")
        let privacyRange = (text as NSString).range(of: "Privacy Policy")
        if gesture.didTap(label: label, in: termsRange) {
            present(SFSafariViewController(url: Legal.terms), animated: true)
        } else if gesture.didTap(label: label, in: privacyRange) {
            present(SFSafariViewController(url: Legal.privacy), animated: true)
        }
    }
}

// MARK: - Feature list

private final class PremiumFeatureListView: UIView {
    struct Item {
        let symbol: String
        let title: String
        let detail: String
    }

    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 0.45).cgColor
        backgroundColor = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 0.10)

        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(items: [Item]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for item in items {
            stack.addArrangedSubview(makeRow(item))
        }
    }

    private func makeRow(_ item: Item) -> UIView {
        let row = UIView()
        let iconBackground = UIView()
        iconBackground.backgroundColor = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 0.22)
        iconBackground.layer.cornerRadius = 18

        let iconView = UIImageView(
            image: UIImage(
                systemName: item.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            )
        )
        iconView.tintColor = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1)
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .white

        let detailLabel = UILabel()
        detailLabel.text = item.detail
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        detailLabel.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading

        row.addSubview(iconBackground)
        iconBackground.addSubview(iconView)
        row.addSubview(textStack)

        iconBackground.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalToSuperview().offset(2)
            make.size.equalTo(36)
        }
        iconView.snp.makeConstraints { $0.center.equalToSuperview() }
        textStack.snp.makeConstraints { make in
            make.leading.equalTo(iconBackground.snp.trailing).offset(12)
            make.trailing.top.bottom.equalToSuperview()
        }
        return row
    }
}

// MARK: - Plan card

private final class PlanCardView: UIView {
    var onTap: (() -> Void)?

    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let detailLabel = UILabel()
    private let badgeLabel = UILabel()
    private let checkView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 16
        layer.borderWidth = 1.5
        backgroundColor = UIColor.white.withAlphaComponent(0.06)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        priceLabel.font = .systemFont(ofSize: 22, weight: .bold)
        priceLabel.textColor = .white
        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        detailLabel.numberOfLines = 2

        badgeLabel.font = .systemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = .black
        badgeLabel.backgroundColor = UIColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 8
        badgeLabel.clipsToBounds = true
        badgeLabel.isHidden = true

        checkView.contentMode = .scaleAspectFit
        checkView.tintColor = UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1)

        addSubview(titleLabel)
        addSubview(priceLabel)
        addSubview(detailLabel)
        addSubview(badgeLabel)
        addSubview(checkView)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(checkView.snp.leading).offset(-8)
        }
        badgeLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.leading.equalTo(titleLabel.snp.trailing).offset(8)
            make.height.equalTo(20)
            make.width.greaterThanOrEqualTo(72)
        }
        priceLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(10)
            make.leading.equalToSuperview().inset(16)
        }
        detailLabel.snp.makeConstraints { make in
            make.top.equalTo(priceLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }
        checkView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }

        snp.makeConstraints { $0.height.greaterThanOrEqualTo(108) }

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, price: String, detail: String, badge: String?) {
        titleLabel.text = title
        priceLabel.text = price
        detailLabel.text = detail
        if let badge {
            badgeLabel.isHidden = false
            badgeLabel.text = "  \(badge)  "
        } else {
            badgeLabel.isHidden = true
        }
    }

    func setSelected(_ selected: Bool) {
        layer.borderColor = selected
            ? UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1).cgColor
            : UIColor.white.withAlphaComponent(0.12).cgColor
        backgroundColor = selected
            ? UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 0.12)
            : UIColor.white.withAlphaComponent(0.06)
        checkView.image = UIImage(
            systemName: selected ? "checkmark.circle.fill" : "circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        )
    }

    @objc private func tapped() { onTap?() }
}

private extension UITapGestureRecognizer {
    func didTap(label: UILabel, in targetRange: NSRange) -> Bool {
        guard let attributed = label.attributedText else { return false }
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: label.bounds.size)
        let storage = NSTextStorage(attributedString: attributed)
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = label.numberOfLines
        container.lineBreakMode = label.lineBreakMode
        let location = self.location(in: label)
        let index = layout.characterIndex(for: location, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        return NSLocationInRange(index, targetRange)
    }
}
