import UIKit
import SnapKit

protocol PrivateNewTabViewControllerDelegate: AnyObject {
    func privateNewTabDidRequestClosePrivate()
}

/// Minimal private NTP — no Continue / Discover / history chrome.
/// Search uses the bottom address bar (same chrome as normal pages).
final class PrivateNewTabViewController: UIViewController {
    weak var delegate: PrivateNewTabViewControllerDelegate?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closePrivateButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        iconView.image = UIImage(systemName: "eye.slash.fill")
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = "Private Browsing"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.text = "History, cookies, and site data from this session won’t be kept after you close all private tabs. Bookmarks, reading list, and downloads stay blocked."
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        closePrivateButton.setTitle("Close Private Tabs", for: .normal)
        closePrivateButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closePrivateButton.addTarget(self, action: #selector(closePrivateTapped), for: .touchUpInside)

        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)

        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(closePrivateButton)

        iconView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(72)
            make.size.equalTo(48)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(iconView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(32)
        }
        closePrivateButton.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(28)
            make.centerX.equalToSuperview()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc func applyTheme() {
        view.backgroundColor = BrowserTheme.privateBackground
        iconView.tintColor = BrowserTheme.privateAccent
        titleLabel.textColor = BrowserTheme.textPrimary
        subtitleLabel.textColor = BrowserTheme.textSecondary
        closePrivateButton.setTitleColor(BrowserTheme.privateAccent, for: .normal)
    }

    @objc private func closePrivateTapped() {
        delegate?.privateNewTabDidRequestClosePrivate()
    }
}
