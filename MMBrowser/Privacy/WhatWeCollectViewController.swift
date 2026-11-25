import UIKit
import SnapKit
import SafariServices
import FirebaseAnalytics
import FirebaseCrashlytics

/// Plain-language collection summary. Crash/analytics are **opt-in** (off by default).
final class WhatWeCollectViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "What we collect".l10n
        BrowserTheme.applyScreenChrome(to: self)

        let text = UITextView()
        text.backgroundColor = .clear
        text.textColor = BrowserTheme.textPrimary
        text.font = .systemFont(ofSize: 16)
        text.isEditable = false
        text.text = """
        X Browser is built so most browsing data stays on your device. Here’s what leaves the device, if anything.

        On your device
        • History, cookies, and Space data stay local unless you erase them or back up via OS features you control.

        Optional / operational
        • Crash reports and usage analytics stay off until you turn them on below.
        • App Store handles Premium purchases; we don’t see your full payment card details.
        • Ad/tracker filter lists may update over the network when blocking is on.

        We don’t
        • We don’t show in-app ads or monetize your sessions with advertising SDKs.
        • We don’t sell your browsing history or profile you for advertisers.
        • Spaces don’t send your passwords to X Browser servers for sync.
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
        footer.text = "Off by default. Optional—helps improve stability. Never required for core browsing."
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

        policy.snp.makeConstraints { make in
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-12)
            make.centerX.equalToSuperview()
        }
        footer.snp.makeConstraints { make in
            make.bottom.equalTo(policy.snp.top).offset(-16)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        row.snp.makeConstraints { make in
            make.bottom.equalTo(footer.snp.top).offset(-8)
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
        text.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.bottom.equalTo(row.snp.top).offset(-12)
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
