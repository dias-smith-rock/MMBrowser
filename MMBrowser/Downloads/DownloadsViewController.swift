import UIKit

final class DownloadsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [DownloadItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Downloads"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        items = DownloadManager.shared.items
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "c") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "c")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.fileName
        cell.detailTextLabel?.text = item.sourceURL
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.background
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        let activity = UIActivityViewController(activityItems: [item.fileURL], applicationActivities: nil)
        present(activity, animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        DownloadManager.shared.remove(id: items[indexPath.row].id)
        items = DownloadManager.shared.items
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    @objc private func close() { dismiss(animated: true) }
}
