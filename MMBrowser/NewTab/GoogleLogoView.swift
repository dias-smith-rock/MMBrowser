import UIKit
import SnapKit

/// Compact brand chip for the NTP header — matches the Settings pill style.
final class GoogleLogoView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        layer.cornerRadius = 16
        layer.borderWidth = 1

        iconView.image = UIImage(named: "MMBrowserLogo")
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 6

        label.textAlignment = .left
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.text = "XBrowser"

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)

        iconView.snp.makeConstraints { make in
            make.size.equalTo(18)
        }
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.trailing.equalToSuperview().offset(-12)
            make.top.equalToSuperview().offset(6)
            make.bottom.equalToSuperview().offset(-6)
        }

        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func applyTheme() {
        label.textColor = BrowserTheme.chromeBlue
        layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.45).cgColor
    }
}
