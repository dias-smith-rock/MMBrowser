import UIKit
import SnapKit

final class BankCardsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var items: [BankCardItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bank cards"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        applyChrome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
    }

    private func reload() {
        items = BankCardStore.shared.all.sorted { $0.updatedAt > $1.updatedAt }
        tableView.reloadData()
    }

    @objc private func addTapped() {
        presentEditor(item: nil)
    }

    private func presentEditor(item: BankCardItem?) {
        let alert = UIAlertController(
            title: item == nil ? "Add Card" : "Edit Card",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "Name on card"; $0.text = item?.holderName }
        alert.addTextField {
            $0.placeholder = "Card number"
            $0.keyboardType = .numberPad
            $0.text = item?.number
        }
        alert.addTextField {
            $0.placeholder = "MM"
            $0.keyboardType = .numberPad
            $0.text = item.map { String(format: "%02d", $0.expiryMonth) }
        }
        alert.addTextField {
            $0.placeholder = "YYYY"
            $0.keyboardType = .numberPad
            $0.text = item.map { String($0.expiryYear) }
        }
        alert.addTextField {
            $0.placeholder = "CVV"
            $0.isSecureTextEntry = true
            $0.keyboardType = .numberPad
            $0.text = item?.cvv
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let number = alert.textFields?[1].text?.filter(\.isNumber) ?? ""
            let month = Int(alert.textFields?[2].text ?? "") ?? 0
            let year = Int(alert.textFields?[3].text ?? "") ?? 0
            let cvv = alert.textFields?[4].text ?? ""
            guard number.count >= 12, (1...12).contains(month), year >= 2024 else {
                if let self { Toast.show("Check card details", from: self) }
                return
            }
            if var existing = item {
                existing.holderName = name
                existing.number = number
                existing.expiryMonth = month
                existing.expiryYear = year
                existing.cvv = cvv
                _ = BankCardStore.shared.update(existing)
            } else {
                let card = BankCardItem(
                    id: UUID().uuidString,
                    holderName: name,
                    number: number,
                    expiryMonth: month,
                    expiryYear: year,
                    cvv: cvv,
                    updatedAt: Date()
                )
                _ = BankCardStore.shared.add(card)
            }
            self?.reload()
        })
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(items.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.backgroundColor = BrowserTheme.card
        if items.isEmpty {
            cell.textLabel?.text = "No saved cards"
            cell.textLabel?.textColor = BrowserTheme.textSecondary
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            let card = items[indexPath.row]
            cell.textLabel?.text = "\(card.maskedNumber)  \(card.holderName)"
            cell.textLabel?.textColor = BrowserTheme.textPrimary
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !items.isEmpty else { return }
        presentEditor(item: items[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !items.isEmpty else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            _ = BankCardStore.shared.remove(id: self.items[indexPath.row].id)
            self.reload()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
