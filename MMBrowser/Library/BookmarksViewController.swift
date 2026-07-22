import UIKit

final class BookmarksViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onSelectURL: ((URL) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var items: [BookmarkItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bookmarks"
        view.backgroundColor = BrowserTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(close))
        navigationController?.navigationBar.barTintColor = BrowserTheme.background
        navigationController?.navigationBar.isTranslucent = false

        items = BookmarkStore.shared.items
        tableView.backgroundColor = BrowserTheme.background
        tableView.separatorColor = UIColor(white: 0.25, alpha: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.textLabel?.textColor = .white
        cell.backgroundColor = BrowserTheme.background
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
        BookmarkStore.shared.remove(id: items[indexPath.row].id)
        items = BookmarkStore.shared.items
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    @objc private func close() { dismiss(animated: true) }
}
