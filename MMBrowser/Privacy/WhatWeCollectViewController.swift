import UIKit
import SnapKit
import SafariServices
import FirebaseAnalytics
import FirebaseCrashlytics

/// Plain-language collection summary. Defaults match shipping Firebase (on until the user turns it off).
final class WhatWeCollectViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "What we collect"
        BrowserTheme.applyScreenChrome(to: self)

        let text = UITextView()
        text.backgroundColor = .clear
        text.textColor = BrowserTheme.textPrimary
        text.font = .systemFont(ofSize: 16)
        text.isEditable = false
        text.text = """
        XBrowser is built so most browsing data stays on your device. Here’s what leaves the device, if anything.

        On your device
        • History, cookies, and Space data stay local unless you erase them or back up via OS features you control.

        Optional / operational
        • Crash reports and usage analytics (if enabled) help us fix bugs and improve the app.
        • Remote configuration can update filter and product flags.
        • App Store handles Premium purchases; we don’t see your full payment card details.

        We don’t
        • We don’t sell your browsing history.
        • Spaces don’t send your passwords to XBrowser servers for sync.
        """
        let row = UIView()
        row.backgroundColor = BrowserTheme.card
        row.layer.cornerRadius = 12
        let label = UILabel()
        label.text = "Share crash & analytics data"
        label.textColor = BrowserTheme.textPrimary
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.numberOfLines = 0
        let footer = UILabel()
        footer.text = "Helps improve stability. Never required for core browsing."
        footer.textColor = BrowserTheme.textSecondary
        footer.font = .systemFont(ofSize: 13)
        footer.numberOfLines = 0
        let toggle = UISwitch()
        toggle.isOn = AppSettings.shareDiagnostics
        toggle.addTarget(self, action: #selector(diagnosticsChanged(_:)), for: .valueChanged)
        let policy = UIButton(type: .system)
        policy.setTitle("Full Privacy Policy", for: .normal)
        policy.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        policy.addTarget(self, action: #selector(openPolicy), for: .touchUpInside)

        view.addSubview(text)
        view.addSubview(row)
        row.addSubview(label)
        row.addSubview(toggle)
        view.addSubview(footer)
        view.addSubview(policy)

        text.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.height.equalTo(280)
        }
        row.snp.makeConstraints { make in
            make.top.equalTo(text.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.trailing.lessThanOrEqualTo(toggle.snp.leading).offset(-12)
            make.top.bottom.equalToSuperview().inset(14)
        }
        toggle.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-14)
            make.centerY.equalToSuperview()
        }
        footer.snp.makeConstraints { make in
            make.top.equalTo(row.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        policy.snp.makeConstraints { make in
            make.top.equalTo(footer.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
        }
    }

    @objc private func diagnosticsChanged(_ toggle: UISwitch) {
        AppSettings.shareDiagnostics = toggle.isOn
        guard FirebaseBootstrap.isConfigured else { return }
        Analytics.setAnalyticsCollectionEnabled(toggle.isOn)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(toggle.isOn)
    }

    @objc private func openPolicy() {
        let safari = SFSafariViewController(url: URL(string: "https://xxxxxbrowser.cc/privacy.html")!)
        safari.preferredControlTintColor = BrowserTheme.chromeBlue
        present(safari, animated: true)
    }
}
