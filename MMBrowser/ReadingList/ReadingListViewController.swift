import UIKit
import WebKit

final class ReadingListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onOpenURL: ((URL) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [ReadingListItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reading List"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        items = ReadingListStore.shared.items
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
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = (item.offlineFileName != nil ? "Offline · " : "") + (item.url?.host ?? "")
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.background
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        if let offline = item.offlineURL, FileManager.default.fileExists(atPath: offline.path) {
            let web = WKWebView(frame: view.bounds)
            let vc = UIViewController()
            vc.view = web
            vc.title = item.title
            web.loadFileURL(offline, allowingReadAccessTo: offline.deletingLastPathComponent())
            navigationController?.pushViewController(vc, animated: true)
        } else if let url = item.url {
            dismiss(animated: true) { self.onOpenURL?(url) }
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        ReadingListStore.shared.remove(id: items[indexPath.row].id)
        items = ReadingListStore.shared.items
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    @objc private func close() { dismiss(animated: true) }
}
