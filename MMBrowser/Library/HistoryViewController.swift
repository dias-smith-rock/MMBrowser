import UIKit

final class HistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [HistoryItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        view.backgroundColor = BrowserTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clear))
        navigationController?.navigationBar.barTintColor = BrowserTheme.background
        navigationController?.navigationBar.isTranslucent = false

        items = HistoryStore.shared.items
        tableView.backgroundColor = BrowserTheme.background
        tableView.separatorColor = UIColor(white: 0.25, alpha: 1)
        tableView.dataSource = self
        tableView.delegate = self
        // subtitle cells created manually
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.urlString
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.backgroundColor = BrowserTheme.background
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let url = items[indexPath.row].url {
            onSelectURL?(url)
        }
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        HistoryStore.shared.remove(id: items[indexPath.row].id)
        items = HistoryStore.shared.items
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func clear() {
        HistoryStore.shared.clear()
        items = []
        tableView.reloadData()
    }
}
