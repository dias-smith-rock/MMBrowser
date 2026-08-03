import UIKit
import QuickLook

final class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, QLPreviewControllerDataSource {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [DownloadItem] = []
    private var changeObserver: NSObjectProtocol?
    private var previewURL: URL?
    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No downloads yet"
        label.textColor = BrowserTheme.textSecondary
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloads"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.allowsSelectionDuringEditing = true
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        changeObserver = NotificationCenter.default.addObserver(
            forName: DownloadManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadItems()
        }
        reloadItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadItems()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    private func reloadItems() {
        items = DownloadManager.shared.items
        tableView.reloadData()
        emptyLabel.isHidden = !items.isEmpty
        tableView.isHidden = items.isEmpty
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "c")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.fileName
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.text = statusText(for: item)
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.background
        cell.accessoryType = item.status == .completed ? .disclosureIndicator : .none

        if item.status == .downloading {
            let wrap: UIView
            let progress: UIProgressView
            if let existing = cell.accessoryView, let bar = existing.subviews.first as? UIProgressView {
                wrap = existing
                progress = bar
            } else {
                wrap = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 12))
                progress = UIProgressView(progressViewStyle: .default)
                progress.frame = wrap.bounds
                progress.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                wrap.addSubview(progress)
                cell.accessoryView = wrap
            }
            progress.progress = Float(item.progress)
        } else {
            cell.accessoryView = nil
        }
        return cell
    }

    private func statusText(for item: DownloadItem) -> String {
        switch item.status {
        case .downloading:
            let pct = item.totalBytes > 0 ? " · \(Int(item.progress * 100))%" : ""
            return "Downloading\(pct)\n\(item.displayDetail)"
        case .completed:
            return item.sourceURL
        case .failed:
            return "Failed · \(item.errorMessage ?? "Unknown error")"
        case .cancelled:
            return "Cancelled"
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        switch item.status {
        case .completed:
            previewOrShare(item)
        case .failed, .cancelled:
            presentActions(for: item)
        case .downloading:
            presentActions(for: item)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        var actions: [UIContextualAction] = []

        if item.status == .downloading {
            let cancel = UIContextualAction(style: .destructive, title: "Cancel") { _, _, done in
                DownloadManager.shared.cancel(id: item.id)
                done(true)
            }
            actions.append(cancel)
        } else if item.status == .failed || item.status == .cancelled {
            let retry = UIContextualAction(style: .normal, title: "Retry") { _, _, done in
                DownloadManager.shared.retry(id: item.id)
                done(true)
            }
            retry.backgroundColor = BrowserTheme.chromeBlue
            actions.append(retry)
        }

        let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, done in
            DownloadManager.shared.remove(id: item.id)
            done(true)
        }
        actions.append(delete)
        return UISwipeActionsConfiguration(actions: actions)
    }

    private func presentActions(for item: DownloadItem) {
        let sheet = UIAlertController(title: item.fileName, message: nil, preferredStyle: .actionSheet)
        if item.status == .downloading {
            sheet.addAction(UIAlertAction(title: "Cancel Download", style: .destructive) { _ in
                DownloadManager.shared.cancel(id: item.id)
            })
        }
        if item.status == .failed || item.status == .cancelled {
            sheet.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                DownloadManager.shared.retry(id: item.id)
            })
        }
        if item.status == .completed {
            sheet.addAction(UIAlertAction(title: "Preview", style: .default) { [weak self] _ in
                self?.preview(item)
            })
            sheet.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
                self?.share(item)
            })
        }
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            DownloadManager.shared.remove(id: item.id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    private func previewOrShare(_ item: DownloadItem) {
        if QLPreviewController.canPreview(item.fileURL as QLPreviewItem) {
            preview(item)
        } else {
            share(item)
        }
    }

    private func preview(_ item: DownloadItem) {
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            Toast.show("File missing", from: self)
            return
        }
        previewURL = item.fileURL
        let ql = QLPreviewController()
        ql.dataSource = self
        present(ql, animated: true)
    }

    private func share(_ item: DownloadItem) {
        guard FileManager.default.fileExists(atPath: item.fileURL.path) else {
            Toast.show("File missing", from: self)
            return
        }
        let activity = UIActivityViewController(activityItems: [item.fileURL], applicationActivities: nil)
        present(activity, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        (previewURL ?? URL(fileURLWithPath: "/")) as QLPreviewItem
    }

    @objc private func close() { dismiss(animated: true) }
}
