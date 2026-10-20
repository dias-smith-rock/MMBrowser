import AVKit
import UIKit
import WebKit

/// Watch Later list for one space: add, edit, delete, and clear.
final class WatchLaterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    var containerID: UUID = ContainerScope.resolveContainerID(nil)
    var currentPageTitle: String?
    var currentPageURL: URL?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var sections: [(day: Date, items: [WatchLaterItem])] = []

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var changeObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Watch Later"
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addTapped)),
            UIBarButtonItem(title: "Clear All", style: .plain, target: self, action: #selector(clearAll))
        ]
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        reloadSections()
        tableView.backgroundColor = BrowserTheme.background
        tableView.separatorColor = BrowserTheme.textSecondary.withAlphaComponent(0.25)
        tableView.tintColor = BrowserTheme.chromeBlue
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        changeObserver = NotificationCenter.default.addObserver(
            forName: WatchLaterStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadAfterMutation()
        }
        updateClearButton()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSections()
        tableView.reloadData()
        updateClearButton()
    }

    private func reloadSections() {
        sections = WatchLaterStore.shared.sectionsByDay(containerID: containerID)
    }

    private func updateClearButton() {
        navigationItem.rightBarButtonItems?.last?.isEnabled = !sections.isEmpty
    }

    private func title(for day: Date) -> String {
        dayFormatter.string(from: day)
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        makeDayHeader(
            title: title(for: sections[section].day),
            count: sections[section].items.count,
            section: section
        )
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 44 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let item = sections[indexPath.section].items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = statusLine(for: item)
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.card
        cell.selectionStyle = .default
        applyStatusIcon(for: item, to: cell)
        return cell
    }

    private func statusLine(for item: WatchLaterItem) -> String {
        let video = item.hasVideoFile ? "Video saved" : (item.hasVideo ? "Video" : "No video")
        let cache: String
        if item.isCaching {
            cache = "Caching…"
        } else if item.isCacheComplete {
            cache = "Cached"
        } else if item.cacheState == "failed" {
            cache = "Cache failed"
        } else {
            cache = "Not cached"
        }
        return "\(item.urlString)\n\(video) · \(cache)"
    }

    private func applyStatusIcon(for item: WatchLaterItem, to cell: UITableViewCell) {
        let image = statusIcon(for: item)?.withRenderingMode(.alwaysTemplate)
        cell.imageView?.image = image
        if #available(iOS 17.0, *) {
            cell.imageView?.removeAllSymbolEffects()
        }
        let tint: UIColor
        if item.isCaching {
            tint = BrowserTheme.chromeBlue
            if #available(iOS 17.0, *) {
                cell.imageView?.addSymbolEffect(.pulse, options: .repeating, animated: true)
            }
        } else if item.cacheState == "failed" {
            tint = .systemOrange
        } else if item.isCacheComplete {
            tint = BrowserTheme.chromeBlue
        } else {
            tint = BrowserTheme.textSecondary
        }
        // Keep cell.tintColor in sync — UITableViewCell often resets imageView tint from it.
        cell.tintColor = tint
        cell.imageView?.tintColor = tint
    }

    private func statusIcon(for item: WatchLaterItem) -> UIImage? {
        let name: String
        if item.isCaching {
            name = "arrow.down.circle"
        } else if item.hasVideoFile && item.isCacheComplete {
            name = "play.rectangle.fill"
        } else if item.hasVideo {
            name = "play.rectangle"
        } else if item.isCacheComplete {
            name = "checkmark.circle.fill"
        } else if item.cacheState == "failed" {
            name = "exclamationmark.circle"
        } else {
            name = "arrow.down.circle"
        }
        return UIImage(systemName: name)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section].items[indexPath.row]
        if item.hasOfflinePage || item.hasVideoFile {
            let reader = WatchLaterOfflineViewController(item: item)
            navigationController?.pushViewController(reader, animated: true)
            return
        }
        if let url = item.url {
            onSelectURL?(url)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let item = self.sections[indexPath.section].items[indexPath.row]
            WatchLaterStore.shared.remove(id: item.id)
            self.reloadAfterMutation()
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let item = self.sections[indexPath.section].items[indexPath.row]
            self.presentEditor(item: item)
            done(true)
        }
        edit.backgroundColor = BrowserTheme.chromeBlue
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    private func makeDayHeader(title: String, count: Int, section: Int) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let titleLabel = UILabel()
        titleLabel.text = "\(title)  ·  \(count)"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        clearButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        clearButton.tag = section
        clearButton.addTarget(self, action: #selector(clearDayButtonTapped(_:)), for: .touchUpInside)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, clearButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        container.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    @objc private func clearDayButtonTapped(_ sender: UIButton) {
        confirmClearDay(at: sender.tag)
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func addTapped() {
        presentEditor(item: nil)
    }

    @objc private func clearAll() {
        let alert = UIAlertController(
            title: "Clear Watch Later?",
            message: "Every Watch Later entry in this space will be removed.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Clear All", style: .destructive) { [weak self] _ in
            guard let self else { return }
            WatchLaterStore.shared.clear(containerID: self.containerID)
            self.reloadAfterMutation()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.last
        }
        present(alert, animated: true)
    }

    private func confirmClearDay(at section: Int) {
        guard sections.indices.contains(section) else { return }
        let day = sections[section].day
        let label = title(for: day)
        let count = sections[section].items.count
        let alert = UIAlertController(
            title: "Clear \(label)?",
            message: count == 1 ? "1 entry will be deleted." : "\(count) entries will be deleted.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Clear Day", style: .destructive) { [weak self] _ in
            guard let self else { return }
            WatchLaterStore.shared.remove(onDayOf: day, containerID: self.containerID)
            self.reloadAfterMutation()
            Toast.show("Cleared \(label)", from: self)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.rectForHeader(inSection: section)
        }
        present(alert, animated: true)
    }

    private func presentEditor(item: WatchLaterItem?) {
        let isNew = item == nil
        let alert = UIAlertController(
            title: isNew ? "Add to Watch Later" : "Edit Watch Later",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Title"
            field.text = item?.title ?? self.currentPageTitle
            field.clearButtonMode = .whileEditing
        }
        alert.addTextField { field in
            field.placeholder = "https://"
            field.text = item?.urlString ?? self.currentPageURL?.absoluteString
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: isNew ? "Add" : "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?.first?.text ?? ""
            let rawURL = alert.textFields?.dropFirst().first?.text ?? ""
            guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                Toast.show("Enter a valid http or https URL", from: self)
                return
            }
            if let item {
                if WatchLaterStore.shared.update(id: item.id, title: title, url: url) {
                    Toast.show("Saved", from: self)
                } else {
                    Toast.show("Couldn’t save. Use a unique URL.", from: self)
                }
            } else if let _ = WatchLaterStore.shared.add(title: title, url: url, containerID: self.containerID) {
                if OfflineMediaCopyrightPolicy.restrictsAudioVideo(on: url) {
                    Toast.show(
                        "Added to Watch Later. \(OfflineMediaCopyrightPolicy.watchLaterNotice)",
                        from: self
                    )
                } else {
                    Toast.show("Added to Watch Later", from: self)
                }
            } else {
                Toast.show("Already in Watch Later", from: self)
            }
            self.reloadAfterMutation()
        })
        present(alert, animated: true)
    }

    private func reloadAfterMutation() {
        reloadSections()
        tableView.reloadData()
        updateClearButton()
    }
}

/// Opens a saved page without the network, and plays a saved video when one exists.
final class WatchLaterOfflineViewController: UIViewController, WKNavigationDelegate {
    private let item: WatchLaterItem
    private let webView: WKWebView
    private let playerController = AVPlayerViewController()
    private let emptyLabel = UILabel()
    private var showsPlayer = false
    private var didFallbackToLiveURL = false

    init(item: WatchLaterItem) {
        self.item = item
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Allow media in archived pages without a user gesture when a video is also saved separately.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Watch Later is deliberately offline — stop page scripts from toasting "You're offline".
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.offlineReaderSupportScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.offlineReaderSupportScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.title
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Open Live",
            style: .plain,
            target: self,
            action: #selector(openLivePage)
        )

        showsPlayer = item.hasVideoFile
        if showsPlayer, let url = item.videoFileURL {
            playerController.player = AVPlayer(url: url)
            addChild(playerController)
            view.addSubview(playerController.view)
            playerController.didMove(toParent: self)
        }

        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = BrowserTheme.background
        webView.scrollView.backgroundColor = BrowserTheme.background
        view.addSubview(webView)

        emptyLabel.text = "Loading offline page…"
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = BrowserTheme.textSecondary
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.backgroundColor = BrowserTheme.background
        view.addSubview(emptyLabel)

        loadOfflinePage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let width = safe.width
        let originY = safe.minY
        let playerHeight: CGFloat = showsPlayer ? min(280, safe.height * 0.42) : 0
        playerController.view.frame = CGRect(x: safe.minX, y: originY, width: width, height: playerHeight)
        let webY = originY + playerHeight
        let webH = max(0, safe.maxY - webY)
        let webFrame = CGRect(x: safe.minX, y: webY, width: width, height: webH)
        webView.frame = webFrame
        // Full web area — opaque label replaces the archive; no site chrome can peek through.
        emptyLabel.frame = webFrame
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if showsPlayer {
            playerController.player?.play()
        }
    }

    @objc private func openLivePage() {
        guard let url = item.url else { return }
        // Pop offline reader, then ask the presenting Watch Later list to open live.
        if let nav = navigationController,
           let list = nav.viewControllers.first as? WatchLaterViewController {
            nav.popViewController(animated: false)
            list.onSelectURL?(url)
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func loadOfflinePage() {
        showWebContent()
        if let archiveURL = item.pageArchiveURL,
           FileManager.default.fileExists(atPath: archiveURL.path),
           let data = try? Data(contentsOf: archiveURL),
           !data.isEmpty {
            // Official WebKit path. Using the *remote* page URL as baseURL often yields a blank
            // document; the archive file URL (or its directory) is the correct base.
            webView.load(
                data,
                mimeType: "application/x-webarchive",
                characterEncodingName: "",
                baseURL: archiveURL
            )
            return
        }
        // Stay offline — never auto-fetch the live page (that surfaces site “You’re offline” toasts).
        if item.hasVideoFile {
            showEmptyState("No offline page snapshot.\nYour saved video is available above.")
        } else {
            showEmptyState("No offline page was saved for this entry.\nUse Open Live when you have a connection.")
        }
    }

    private func showEmptyState(_ message: String) {
        emptyLabel.text = message
        emptyLabel.isHidden = false
        // Hide + stop the archive so site error / Refresh chrome can’t overlap our copy.
        webView.stopLoading()
        webView.isHidden = true
        webView.alpha = 0
        view.bringSubviewToFront(emptyLabel)
    }

    private func showWebContent() {
        emptyLabel.isHidden = true
        webView.isHidden = false
        webView.alpha = 1
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Probe before revealing — avoids a flash of site error UI under our empty copy.
        webView.alpha = 0
        webView.evaluateJavaScript("window.__mmWatchLaterHideOffline && window.__mmWatchLaterHideOffline();", completionHandler: nil)
        webView.evaluateJavaScript(Self.archiveContentProbeScript) { [weak self] result, _ in
            guard let self else { return }
            let info = result as? [String: Any]
            let richness = (info?["richness"] as? Int)
                ?? (info?["richness"] as? Double).map(Int.init)
                ?? 0
            let isErrorShell = (info?["errorShell"] as? Bool) == true
            if richness == 0 || isErrorShell {
                if self.item.hasVideoFile {
                    self.showEmptyState("This offline page couldn’t be displayed.\nYour saved video is available above.")
                } else {
                    self.showEmptyState("This offline page couldn’t be displayed.\nUse Open Live when you have a connection.")
                }
            } else {
                self.showWebContent()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    private func handleLoadFailure(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
        // Second attempt: loadFileURL (works for some archive layouts). Still no live network fetch.
        if !didFallbackToLiveURL,
           let archiveURL = item.pageArchiveURL,
           FileManager.default.fileExists(atPath: archiveURL.path) {
            didFallbackToLiveURL = true
            let accessRoot = archiveURL.deletingLastPathComponent()
            webView.loadFileURL(archiveURL, allowingReadAccessTo: accessRoot)
            return
        }
        if item.hasVideoFile {
            showEmptyState("This offline page couldn’t be displayed.\nYour saved video is available above.")
        } else {
            showEmptyState("This offline page couldn’t be displayed.\nUse Open Live when you have a connection.")
        }
    }

    /// Probe archived DOM: text/image richness + generic error-shell heuristics (site-agnostic).
    private static let archiveContentProbeScript = #"""
(function() {
  try {
    var body = document.body;
    var text = ((body && body.innerText) || '').replace(/\s+/g, ' ').trim();
    var richness = text.length
      + ((document.images && document.images.length) || 0)
      + ((document.querySelectorAll && document.querySelectorAll('video, article, main').length) || 0);
    var head = text.slice(0, 600);
    var errorShell = /something went wrong|don.?t fret|it.?s not your fault|unable to load|page isn.?t (working|available)|aw,? snap|err_internet|this site can.?t be reached|took too long to respond|try again later|出了点问题|无法显示|加载失败/i.test(head);
    // Error shells are usually short and dominated by a Retry/Refresh control.
    if (errorShell && text.length < 900) {
      var hasRetry = false;
      var buttons = document.querySelectorAll('button, [role="button"], a');
      for (var i = 0; i < buttons.length; i++) {
        var t = ((buttons[i].innerText || buttons[i].textContent || '') + ' ' + (buttons[i].getAttribute('aria-label') || '')).trim();
        if (/^refresh$|^retry$|^try again$|^reload$|重试|刷新/i.test(t)) { hasRetry = true; break; }
      }
      errorShell = hasRetry || text.length < 420;
    } else {
      errorShell = false;
    }
    return { richness: richness, errorShell: !!errorShell };
  } catch (e) {
    return { richness: 0, errorShell: false };
  }
})()
"""#

    /// Spoof connectivity and hide common offline / soft-error banners inside archived pages.
    private static let offlineReaderSupportScript = #"""
(function() {
  function spoofOnline() {
    try {
      Object.defineProperty(Navigator.prototype, 'onLine', {
        configurable: true,
        get: function() { return true; }
      });
    } catch (e) {
      try {
        Object.defineProperty(navigator, 'onLine', {
          configurable: true,
          get: function() { return true; }
        });
      } catch (e2) {}
    }
    try {
      window.addEventListener('offline', function(e) {
        e.stopImmediatePropagation();
        e.preventDefault();
      }, true);
    } catch (e) {}
    try {
      if (typeof window.dispatchEvent === 'function') {
        window.dispatchEvent(new Event('online'));
      }
    } catch (e) {}
  }

  var hidePattern = /you.?re offline|check your connection|no internet|network unavailable|appears offline|something went wrong|don.?t fret|it.?s not your fault|unable to load|page isn.?t (working|available)|try again later|无网络|检查网络|出了点问题|加载失败/i;

  function hideMatchingSubtree(el) {
    if (!el) return;
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.setAttribute('data-mm-offline-hidden', '1');
  }

  function hideOfflineToasts() {
    try {
      var style = document.getElementById('mm-watch-later-hide-offline');
      if (!style) {
        style = document.createElement('style');
        style.id = 'mm-watch-later-hide-offline';
        // Capability-based offline banners only — text heuristics below catch the rest.
        style.textContent = [
          '#offline-message',
          '.offline-message',
          '.offline-banner',
          '[data-offline]',
          '[data-testid*="offline"]'
        ].join(',') + '{ display:none !important; visibility:hidden !important; opacity:0 !important; height:0 !important; pointer-events:none !important; }';
        (document.head || document.documentElement || document.body).appendChild(style);
      }
    } catch (e) {}
    try {
      var nodes = document.querySelectorAll('body *');
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        if (!el || el.childElementCount > 12) continue;
        var text = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
        if (!text || text.length > 220) continue;
        if (!hidePattern.test(text)) continue;
        hideMatchingSubtree(el);
        var p = el.parentElement;
        for (var d = 0; p && d < 5; d++) {
          var tag = (p.tagName || '').toLowerCase();
          var cls = String(p.className || '').toLowerCase();
          if (tag.indexOf('toast') !== -1 || cls.indexOf('toast') !== -1
              || tag.indexOf('notification') !== -1 || cls.indexOf('notification') !== -1
              || cls.indexOf('error') !== -1 || cls.indexOf('empty') !== -1) {
            hideMatchingSubtree(p);
            break;
          }
          p = p.parentElement;
        }
      }
    } catch (e) {}
  }

  window.__mmWatchLaterHideOffline = hideOfflineToasts;
  spoofOnline();
  hideOfflineToasts();
  if (!window.__mmWatchLaterOfflineSupport) {
    window.__mmWatchLaterOfflineSupport = true;
    document.addEventListener('DOMContentLoaded', hideOfflineToasts, true);
    setTimeout(hideOfflineToasts, 200);
    setTimeout(hideOfflineToasts, 800);
    setTimeout(hideOfflineToasts, 2000);
    setTimeout(hideOfflineToasts, 4000);
    try {
      var mo = new MutationObserver(function() { hideOfflineToasts(); });
      mo.observe(document.documentElement || document, { childList: true, subtree: true });
    } catch (e) {}
  }
})();
"""#
}
