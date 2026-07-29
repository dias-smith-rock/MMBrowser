import UIKit
import SnapKit

protocol PrivateNewTabViewControllerDelegate: AnyObject {
    func privateNewTabDidSubmit(_ text: String)
    func privateNewTabDidRequestClosePrivate()
}

/// Minimal private NTP: search only — no Continue / Discover / history chrome.
final class PrivateNewTabViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: PrivateNewTabViewControllerDelegate?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let searchField = UITextField()
    private let closePrivateButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.privateBackground

        iconView.image = UIImage(systemName: "eye.slash.fill")
        iconView.tintColor = BrowserTheme.privateAccent
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = "Private Browsing"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.text = "History, cookies, and site data from this session won’t be kept after you close all private tabs. Bookmarks, reading list, and downloads stay blocked."
        subtitleLabel.textColor = BrowserTheme.textSecondary
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center

        let searchBox = UIView()
        searchBox.backgroundColor = BrowserTheme.privateElevated
        searchBox.layer.cornerRadius = 22
        searchField.textColor = .white
        searchField.tintColor = BrowserTheme.privateAccent
        searchField.font = .systemFont(ofSize: 16)
        searchField.returnKeyType = .go
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.keyboardType = .webSearch
        searchField.delegate = self
        searchField.attributedPlaceholder = NSAttributedString(
            string: "Search or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )
        searchBox.addSubview(searchField)

        closePrivateButton.setTitle("Close Private Tabs", for: .normal)
        closePrivateButton.setTitleColor(BrowserTheme.privateAccent, for: .normal)
        closePrivateButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closePrivateButton.addTarget(self, action: #selector(closePrivateTapped), for: .touchUpInside)

        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(searchBox)
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
        searchBox.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(28)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(44)
        }
        searchField.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
        closePrivateButton.snp.makeConstraints { make in
            make.top.equalTo(searchBox.snp.bottom).offset(24)
            make.centerX.equalToSuperview()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        textField.resignFirstResponder()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        delegate?.privateNewTabDidSubmit(text)
        return true
    }

    @objc private func closePrivateTapped() {
        delegate?.privateNewTabDidRequestClosePrivate()
    }
}
