import UIKit
import WebKit
import SnapKit

/// Modal popup WebView for `window.open` / OAuth (Google GSI, Apple, etc.).
/// Must be created with the `WKWebViewConfiguration` from `createWebViewWith`
/// so `window.opener` and postMessage keep working.
final class AuthPopupViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {
    let popupWebView: WKWebView
    var onDismissed: (() -> Void)?
    private let closeBar = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let header = UIView()
    private var didLayOutWebView = false

    /// - Important: `webView` must already be created with WebKit's `createWebViewWith`
    ///   configuration and must already be in a UIWindow hierarchy before that delegate
    ///   returns — otherwise `window.opener` stays null and Google GSI hangs on
    ///   `/gsi/transform`.
    init(webView: WKWebView) {
        self.popupWebView = webView
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrowserTheme.background

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.text = "Sign in"

        closeBar.setTitle("Done", for: .normal)
        closeBar.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        closeBar.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        closeBar.accessibilityLabel = "Done"

        view.addSubview(header)
        header.addSubview(titleLabel)
        header.addSubview(closeBar)

        header.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }
        closeBar.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(72)
            make.trailing.lessThanOrEqualTo(closeBar.snp.leading).offset(-8)
        }
    }

    /// Move the already-created WebView into this sheet (do not recreate / reload it).
    func attachPopupWebViewIfNeeded() {
        guard !didLayOutWebView else { return }
        didLayOutWebView = true
        popupWebView.isHidden = false
        popupWebView.alpha = 1
        popupWebView.removeFromSuperview()
        view.addSubview(popupWebView)
        popupWebView.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        attachPopupWebViewIfNeeded()
    }

    func present(from host: UIViewController) {
        XSiteProbe.log("popup.present", [
            "url": popupWebView.url?.absoluteString ?? "pending",
            "pool": ObjectIdentifier(popupWebView.configuration.processPool).debugDescription,
            "hasSuperview": popupWebView.superview != nil
        ])
        host.present(self, animated: true)
    }

    @objc private func doneTapped() {
        XSiteProbe.log("popup.done", ["url": popupWebView.url?.absoluteString ?? "nil"])
        dismissPopup()
    }

    func dismissPopup() {
        let finish = { [weak self] in
            guard let self else { return }
            self.popupWebView.stopLoading()
            self.popupWebView.uiDelegate = nil
            self.popupWebView.navigationDelegate = nil
            self.popupWebView.removeFromSuperview()
            self.onDismissed?()
            self.onDismissed = nil
        }
        if presentingViewController != nil {
            dismiss(animated: true, completion: finish)
        } else {
            finish()
        }
    }

    // MARK: - WKUIDelegate

    func webViewDidClose(_ webView: WKWebView) {
        XSiteProbe.log("popup.webViewDidClose", ["url": webView.url?.absoluteString ?? "nil"])
        dismissPopup()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Nested window.open: return this same view so opener chain stays intact.
        // Do NOT call load() — WebKit navigates the returned web view itself.
        XSiteProbe.log("popup.nestedOpen", [
            "url": navigationAction.request.url?.absoluteString ?? "nil",
            "action": "reuseSelf"
        ])
        return webView
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme.hasPrefix("x-safari-") {
            XSiteProbe.log("popup.ignoreXSafari", ["url": url.absoluteString])
            decisionHandler(.cancel)
            return
        }
        let allowed = ["http", "https", "about", "blob", "data"]
        if !scheme.isEmpty && !allowed.contains(scheme) {
            XSiteProbe.log("popup.cancelScheme", ["url": url.absoluteString, "scheme": scheme])
            decisionHandler(.cancel)
            return
        }
        if XSiteProbe.isRelevant(url) {
            XSiteProbe.log("popup.nav", [
                "url": url.absoluteString,
                "main": navigationAction.targetFrame?.isMainFrame ?? true
            ])
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            titleLabel.text = title
        }
        let href = webView.url?.absoluteString ?? "nil"
        XSiteProbe.log("popup.finish", [
            "url": href,
            "title": titleLabel.text ?? ""
        ])
        webView.evaluateJavaScript(
            "(function(){return {opener:!!window.opener,href:location.href,bodyLen:(document.body&&document.body.innerText||'').length};})()"
        ) { result, _ in
            if let dict = result as? [String: Any] {
                XSiteProbe.log("popup.state", dict)
            }
        }

        // If GSI transform still has no opener, the page stays blank — close so the
        // user is not stuck (credential cannot be delivered without opener).
        if href.contains("/gsi/transform") {
            webView.evaluateJavaScript("(function(){return !!window.opener;})()") { [weak self] result, _ in
                let hasOpener = (result as? Bool) ?? false
                XSiteProbe.log("popup.transform", ["hasOpener": hasOpener])
                if !hasOpener {
                    // Give GSI a brief moment in case opener is assigned late.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.popupWebView.evaluateJavaScript("(function(){return !!window.opener;})()") { result, _ in
                            let ok = (result as? Bool) ?? false
                            XSiteProbe.log("popup.transform.retry", ["hasOpener": ok])
                        }
                    }
                }
            }
        }
    }
}
