import AVKit
import SnapKit
import UIKit
import WebKit

/// Watch Later list for one space: two-column preview cards (like the tab switcher).
final class WatchLaterViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelectURL: ((URL) -> Void)?
    var containerID: UUID = ContainerScope.resolveContainerID(nil)
    var currentPageTitle: String?
    var currentPageURL: URL?

    private var collectionView: UICollectionView!
    private var sections: [(day: Date, items: [WatchLaterItem])] = []
    private let clearAllButton = UIBarButtonItem(title: "Clear All", style: .plain, target: nil, action: nil)

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
        view.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle

        let titleLabel = UILabel()
        titleLabel.text = "Watch Later"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.textAlignment = .center
        navigationItem.titleView = titleLabel

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close",
            style: .plain,
            target: self,
            action: #selector(close)
        )
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAll)
        navigationItem.rightBarButtonItem = clearAllButton
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = TabGridMetrics.spacing
        layout.minimumInteritemSpacing = TabGridMetrics.spacing
        layout.sectionInset = UIEdgeInsets(top: 4, left: 12, bottom: 16, right: 12)
        layout.headerReferenceSize = CGSize(width: 0, height: 44)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = BrowserTheme.background
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(WatchLaterGridCell.self, forCellWithReuseIdentifier: WatchLaterGridCell.reuseID)
        collectionView.register(
            WatchLaterDayHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: WatchLaterDayHeaderView.reuseID
        )
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        changeObserver = NotificationCenter.default.addObserver(
            forName: WatchLaterStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadAfterMutation()
        }
        reloadAfterMutation()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadAfterMutation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func reloadSections() {
        sections = WatchLaterStore.shared.sectionsByDay(containerID: containerID)
    }

    private func updateClearButton() {
        clearAllButton.isEnabled = !sections.isEmpty
    }

    private func title(for day: Date) -> String {
        dayFormatter.string(from: day)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WatchLaterGridCell.reuseID,
            for: indexPath
        ) as! WatchLaterGridCell
        let item = sections[indexPath.section].items[indexPath.row]
        cell.configure(item: item)
        cell.onClose = { [weak self] in
            WatchLaterStore.shared.remove(id: item.id)
            self?.reloadAfterMutation()
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: WatchLaterDayHeaderView.reuseID,
            for: indexPath
        ) as! WatchLaterDayHeaderView
        let section = indexPath.section
        header.configure(
            title: title(for: sections[section].day),
            count: sections[section].items.count
        )
        header.onClear = { [weak self] in
            self?.confirmClearDay(at: section)
        }
        return header
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        TabGridMetrics.layout(forContainerWidth: collectionView.bounds.width).itemSize
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: 44)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
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

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let item = sections[indexPath.section].items[indexPath.row]
        return UIContextMenuConfiguration(identifier: item.id.uuidString as NSString, previewProvider: nil) { [weak self] _ in
            let edit = UIAction(title: "Edit", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentEditor(item: item)
            }
            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                WatchLaterStore.shared.remove(id: item.id)
                self?.reloadAfterMutation()
            }
            return UIMenu(children: [edit, delete])
        }
    }

    @objc private func close() { dismiss(animated: true) }

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
            pop.barButtonItem = clearAllButton
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
            pop.sourceView = collectionView
            let attrs = collectionView.layoutAttributesForSupplementaryElement(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: section)
            )
            pop.sourceRect = attrs?.frame ?? CGRect(x: 0, y: 0, width: 44, height: 44)
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
        collectionView?.reloadData()
        updateClearButton()
    }
}

// MARK: - Day header

private final class WatchLaterDayHeaderView: UICollectionReusableView {
    static let reuseID = "WatchLaterDayHeader"
    var onClear: (() -> Void)?

    private let titleLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        clearButton.setTitle("Clear", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        clearButton.setTitleColor(BrowserTheme.chromeBlue, for: .normal)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, clearButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int) {
        titleLabel.text = "\(title)  ·  \(count)"
    }

    @objc private func clearTapped() { onClear?() }
}

// MARK: - Grid cell

private final class WatchLaterGridCell: UICollectionViewCell {
    static let reuseID = "WatchLaterGridCell"
    var onClose: (() -> Void)?

    private let card = UIView()
    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let preview = UIImageView()
    private let placeholder = UILabel()
    private let statusBadge = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.backgroundColor = BrowserTheme.card
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        card.layer.borderWidth = 1.5
        card.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.35).cgColor
        contentView.addSubview(card)

        headerBar.backgroundColor = BrowserTheme.card
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = BrowserTheme.textPrimary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)),
            for: .normal
        )
        closeButton.tintColor = BrowserTheme.textSecondary
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.backgroundColor = BrowserTheme.secondaryCard

        placeholder.text = "Page"
        placeholder.textAlignment = .center
        placeholder.textColor = BrowserTheme.textSecondary
        placeholder.font = .systemFont(ofSize: 15)

        statusBadge.contentMode = .center
        statusBadge.tintColor = .white
        statusBadge.backgroundColor = BrowserTheme.chromeBlue.withAlphaComponent(0.9)
        statusBadge.layer.cornerRadius = 12
        statusBadge.clipsToBounds = true
        statusBadge.isHidden = true

        card.addSubview(preview)
        card.addSubview(placeholder)
        card.addSubview(headerBar)
        card.addSubview(statusBadge)
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(closeButton)

        card.snp.makeConstraints { $0.edges.equalToSuperview() }
        headerBar.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(40)
        }
        closeButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().offset(-8)
            make.size.equalTo(22)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(10)
            make.trailing.equalTo(closeButton.snp.leading).offset(-6)
            make.centerY.equalToSuperview()
        }
        preview.snp.makeConstraints { make in
            make.top.equalTo(headerBar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        placeholder.snp.makeConstraints { make in
            make.center.equalTo(preview)
        }
        statusBadge.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.bottom.equalToSuperview().offset(-8)
            make.size.equalTo(24)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(item: WatchLaterItem) {
        titleLabel.text = item.title
        if let image = item.previewImage {
            preview.image = image
            placeholder.isHidden = true
        } else {
            preview.image = nil
            placeholder.isHidden = false
            placeholder.text = item.url?.host ?? "Page"
        }

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        if item.isCaching {
            statusBadge.isHidden = false
            statusBadge.image = UIImage(systemName: "arrow.down.circle.fill", withConfiguration: iconConfig)
            statusBadge.backgroundColor = BrowserTheme.chromeBlue.withAlphaComponent(0.9)
        } else if item.cacheState == "failed" {
            statusBadge.isHidden = false
            statusBadge.image = UIImage(systemName: "exclamationmark.circle.fill", withConfiguration: iconConfig)
            statusBadge.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        } else if item.hasVideoFile {
            statusBadge.isHidden = false
            statusBadge.image = UIImage(systemName: "play.fill", withConfiguration: iconConfig)
            statusBadge.backgroundColor = BrowserTheme.chromeBlue.withAlphaComponent(0.9)
        } else if item.isCacheComplete {
            statusBadge.isHidden = false
            statusBadge.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: iconConfig)
            statusBadge.backgroundColor = BrowserTheme.chromeBlue.withAlphaComponent(0.9)
        } else {
            statusBadge.isHidden = true
            statusBadge.image = nil
        }
    }

    @objc private func closeTapped() { onClose?() }
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

        emptyLabel.text = "Loading page snapshot…"
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
            showEmptyState("No page snapshot was saved.\nYour saved media is available above.")
        } else {
            showEmptyState("No page snapshot was saved for this entry.\nUse Open Live when you have a connection.")
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
                    self.showEmptyState("This page snapshot couldn’t be displayed.\nYour saved media is available above.")
                } else {
                    self.showEmptyState("This page snapshot couldn’t be displayed.\nUse Open Live when you have a connection.")
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
            showEmptyState("This page snapshot couldn’t be displayed.\nYour saved media is available above.")
        } else {
            showEmptyState("This page snapshot couldn’t be displayed.\nUse Open Live when you have a connection.")
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
