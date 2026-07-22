import UIKit
import WebKit
import SnapKit

protocol WebViewControllerDelegate: AnyObject {
    func webViewController(_ controller: WebViewController, didUpdateTitle title: String?)
    func webViewController(_ controller: WebViewController, didUpdateURL url: URL?)
    func webViewController(_ controller: WebViewController, didUpdateProgress progress: Double, isLoading: Bool)
    func webViewController(_ controller: WebViewController, didUpdateNavigationState canGoBack: Bool, canGoForward: Bool)
    func webViewController(_ controller: WebViewController, requestNewTabFor url: URL)
    func webViewControllerDidFail(_ controller: WebViewController, error: Error)
}

final class WebViewController: UIViewController {
    weak var delegate: WebViewControllerDelegate?

    private(set) var webView: WKWebView?
    private let isIncognito: Bool
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private var lastFailedURL: URL?

    init(isIncognito: Bool) {
        self.isIncognito = isIncognito
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        setupWebView()
        setupErrorView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        if isIncognito {
            config.websiteDataStore = .nonPersistent()
        }
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        view.addSubview(wv)
        wv.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        webView = wv

        progressObservation = wv.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateProgress: webView.estimatedProgress, isLoading: webView.isLoading)
        }
        titleObservation = wv.observe(\.title, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateTitle: webView.title)
        }
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateURL: webView.url)
        }
        canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateNavigationState: webView.canGoBack, canGoForward: webView.canGoForward)
        }
        canGoForwardObservation = wv.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.delegate?.webViewController(self, didUpdateNavigationState: webView.canGoBack, canGoForward: webView.canGoForward)
        }
    }

    private func setupErrorView() {
        errorContainer.isHidden = true
        errorContainer.backgroundColor = BrowserTheme.background
        view.addSubview(errorContainer)

        errorLabel.textColor = BrowserTheme.textPrimary
        errorLabel.font = .systemFont(ofSize: 16)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center

        retryButton.setTitle("Retry", for: .normal)
        retryButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        errorContainer.addSubview(errorLabel)
        errorContainer.addSubview(retryButton)
        errorContainer.snp.makeConstraints { make in make.edges.equalToSuperview() }
        errorLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(-20)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        retryButton.snp.makeConstraints { make in
            make.top.equalTo(errorLabel.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }
    }

    func load(url: URL) {
        errorContainer.isHidden = true
        lastFailedURL = nil
        webView?.load(URLRequest(url: url))
    }

    func goBack() { if webView?.canGoBack == true { webView?.goBack() } }
    func goForward() { if webView?.canGoForward == true { webView?.goForward() } }
    func reload() { webView?.reload() }

    func captureSnapshot(completion: @escaping (UIImage?) -> Void) {
        webView?.takeSnapshot(with: nil) { image, _ in
            completion(image)
        }
    }

    func cleanup() {
        progressObservation = nil
        titleObservation = nil
        urlObservation = nil
        canGoBackObservation = nil
        canGoForwardObservation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
    }

    @objc private func retryTapped() {
        if let url = lastFailedURL {
            load(url: url)
        } else {
            webView?.reload()
        }
    }

    deinit {
        cleanup()
    }
}

extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorContainer.isHidden = true
        delegate?.webViewController(self, didUpdateProgress: 1, isLoading: false)
        delegate?.webViewController(self, didUpdateTitle: webView.title)
        delegate?.webViewController(self, didUpdateURL: webView.url)
        if !isIncognito, let url = webView.url {
            HistoryStore.shared.add(title: webView.title ?? "", url: url)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        lastFailedURL = webView?.url
        errorLabel.text = "Couldn't load page.\n\(error.localizedDescription)"
        errorContainer.isHidden = false
        delegate?.webViewControllerDidFail(self, error: error)
        delegate?.webViewController(self, didUpdateProgress: 0, isLoading: false)
    }
}

extension WebViewController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            delegate?.webViewController(self, requestNewTabFor: url)
        }
        return nil
    }
}
