import UIKit
import SnapKit

protocol ContainerManageViewControllerDelegate: AnyObject {
    func containerManageDidChange()
}

final class ContainerManageViewController: UIViewController {
    weak var delegate: ContainerManageViewControllerDelegate?

    private let tabManager: TabManager
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var items: [BrowserContainer] = []

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Containers"
        BrowserTheme.applyScreenChrome(to: self)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        items = tabManager.sortedContainers
        tableView.reloadData()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func addTapped() {
        let edit = ContainerEditViewController(
            container: nil,
            suggestedPresetIndex: tabManager.containers.count
        )
        edit.delegate = self
        navigationController?.pushViewController(edit, animated: true)
    }

    private func openEditor(for container: BrowserContainer) {
        let edit = ContainerEditViewController(container: container)
        edit.delegate = self
        navigationController?.pushViewController(edit, animated: true)
    }

    private func confirmDelete(_ container: BrowserContainer) {
        guard tabManager.containers.count > 1 else {
            presentError("Keep at least one container.")
            return
        }
        let alert = UIAlertController(
            title: "Delete Container?",
            message: "Tabs in “\(container.name)” will move to another container. Their login session for this container will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            _ = self.tabManager.deleteContainer(id: container.id)
            self.reload()
            self.delegate?.containerManageDidChange()
        }))
        present(alert, animated: true)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: "Containers", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension ContainerManageViewController: ContainerEditViewControllerDelegate {
    func containerEditDidSave(_ container: BrowserContainer, isNew: Bool) {
        let ok: Bool
        if isNew {
            ok = tabManager.addContainer(container) != nil
        } else {
            ok = tabManager.updateContainer(container)
        }
        guard ok else {
            presentError("Could not save. Choose a unique non-empty name.")
            return
        }
        reload()
        delegate?.containerManageDidChange()
    }
}

extension ContainerManageViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        BrowserTheme.styleListCell(cell)
        let item = items[indexPath.row]
        let count = tabManager.normalTabs.filter { $0.containerID == item.id }.count
        cell.textLabel?.text = item.name
        cell.detailTextLabel?.text = "\(count == 1 ? "1 tab" : "\(count) tabs") · \(item.locationSummary)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openEditor(for: items[indexPath.row])
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.confirmDelete(self.items[indexPath.row])
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        var ids = items.map(\.id)
        let id = ids.remove(at: sourceIndexPath.row)
        ids.insert(id, at: destinationIndexPath.row)
        tabManager.reorderContainers(ids: ids)
        reload()
        delegate?.containerManageDidChange()
    }
}

extension ContainerManageViewController: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let item = UIDragItem(itemProvider: NSItemProvider(object: items[indexPath.row].id.uuidString as NSString))
        item.localObject = items[indexPath.row].id
        return [item]
    }

    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let dest = coordinator.destinationIndexPath,
              let item = coordinator.items.first,
              let source = item.sourceIndexPath else { return }
        tableView.performBatchUpdates {
            var ids = items.map(\.id)
            let id = ids.remove(at: source.row)
            ids.insert(id, at: dest.row)
            tabManager.reorderContainers(ids: ids)
            items = tabManager.sortedContainers
            tableView.moveRow(at: source, to: dest)
        } completion: { [weak self] _ in
            self?.delegate?.containerManageDidChange()
        }
        coordinator.drop(item.dragItem, toRowAt: dest)
    }
}
