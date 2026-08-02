import UIKit
import CoreLocation

protocol ContainerEditViewControllerDelegate: AnyObject {
    func containerEditDidSave(_ container: BrowserContainer, isNew: Bool)
}

/// Add / edit a container name and its Geolocation spoof settings.
final class ContainerEditViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    weak var delegate: ContainerEditViewControllerDelegate?

    private let isNew: Bool
    private var draft: BrowserContainer
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let nameField = UITextField()

    private enum Section: Int, CaseIterable {
        case name, mode, spoofPreset, spoofCustom
    }

    init(container: BrowserContainer?, suggestedPresetIndex: Int = 0) {
        if let container {
            self.isNew = false
            self.draft = container
        } else {
            self.isNew = true
            let preset = SpoofLocationPreset.all[suggestedPresetIndex % SpoofLocationPreset.all.count]
            self.draft = BrowserContainer(
                id: UUID(),
                name: "",
                sessionID: UUID(),
                sortIndex: 0,
                location: preset
            )
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew ? "Add Container" : "Edit Container"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )

        nameField.placeholder = "Name"
        nameField.text = draft.name
        nameField.autocapitalizationType = .words
        nameField.clearButtonMode = .whileEditing
        nameField.textColor = BrowserTheme.textPrimary
        nameField.returnKeyType = .done
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        navigationController?.popViewController(animated: true)
        if isNew, navigationController == nil {
            dismiss(animated: true)
        }
    }

    @objc private func nameChanged() {
        draft.name = nameField.text ?? ""
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        draft.name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !draft.name.isEmpty else {
            presentAlert("Enter a container name.")
            return
        }
        delegate?.containerEditDidSave(draft, isNew: isNew)
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func presentAlert(_ message: String) {
        let alert = UIAlertController(title: "Container", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private var isCustomSpoofSelected: Bool {
        !SpoofLocationPreset.all.contains {
            abs($0.latitude - draft.latitude) < 0.0001 && abs($0.longitude - draft.longitude) < 0.0001
        }
    }

    private func apply(preset: SpoofLocationPreset) {
        draft.locationMode = .spoof
        draft.latitude = preset.latitude
        draft.longitude = preset.longitude
        draft.timeZoneIdentifier = preset.timeZoneIdentifier
        draft.locationPresetID = preset.id
        tableView.reloadData()
    }

    // MARK: - Table

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .name: return 1
        case .mode: return LocationPrivacyMode.allCases.count
        case .spoofPreset: return draft.locationMode == .spoof ? SpoofLocationPreset.all.count : 0
        case .spoofCustom: return draft.locationMode == .spoof ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .name: return "Name"
        case .mode: return "Location for Sites in This Container"
        case .spoofPreset: return draft.locationMode == .spoof ? "Virtual City" : nil
        case .spoofCustom: return draft.locationMode == .spoof ? "Custom" : nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .mode:
            return "Deny and Spoof only affect the browser Geolocation API. Network IP is unchanged."
        case .spoofPreset:
            return draft.locationMode == .spoof
                ? "Timezone is adjusted to match the selected city when possible."
                : nil
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        BrowserTheme.styleListCell(cell)
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.contentView.subviews.filter { $0 is UITextField }.forEach { $0.removeFromSuperview() }

        switch Section(rawValue: indexPath.section)! {
        case .name:
            cell.selectionStyle = .none
            cell.textLabel?.text = nil
            cell.detailTextLabel?.text = nil
            if nameField.superview != cell.contentView {
                nameField.removeFromSuperview()
                cell.contentView.addSubview(nameField)
                nameField.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    nameField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    nameField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                    nameField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
                    nameField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
                ])
            }
        case .mode:
            let mode = LocationPrivacyMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.displayName
            cell.detailTextLabel?.text = mode.detail
            cell.accessoryType = mode == draft.locationMode ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .spoofPreset:
            let preset = SpoofLocationPreset.all[indexPath.row]
            cell.textLabel?.text = preset.name
            cell.detailTextLabel?.text = String(
                format: "%.2f, %.2f · %@",
                preset.latitude,
                preset.longitude,
                preset.timeZoneIdentifier
            )
            let selected = !isCustomSpoofSelected
                && abs(draft.latitude - preset.latitude) < 0.0001
                && abs(draft.longitude - preset.longitude) < 0.0001
            cell.accessoryType = selected ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .spoofCustom:
            cell.textLabel?.text = "Choose on Map…"
            cell.detailTextLabel?.text = String(format: "%.5f, %.5f", draft.latitude, draft.longitude)
            cell.accessoryType = isCustomSpoofSelected ? .checkmark : .disclosureIndicator
            cell.tintColor = BrowserTheme.chromeBlue
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .name:
            nameField.becomeFirstResponder()
        case .mode:
            draft.locationMode = LocationPrivacyMode.allCases[indexPath.row]
            tableView.reloadData()
        case .spoofPreset:
            apply(preset: SpoofLocationPreset.all[indexPath.row])
        case .spoofCustom:
            let picker = LocationMapPickerViewController()
            picker.initialCoordinate = CLLocationCoordinate2D(latitude: draft.latitude, longitude: draft.longitude)
            picker.onPick = { [weak self] coordinate in
                guard let self else { return }
                self.draft.locationMode = .spoof
                self.draft.latitude = coordinate.latitude
                self.draft.longitude = coordinate.longitude
                self.draft.locationPresetID = nil
                // Keep previous TZ unless empty; custom pin does not infer timezone.
                if self.draft.timeZoneIdentifier.isEmpty {
                    self.draft.timeZoneIdentifier = SpoofLocationPreset.all[0].timeZoneIdentifier
                }
                self.tableView.reloadData()
            }
            navigationController?.pushViewController(picker, animated: true)
        }
    }
}
