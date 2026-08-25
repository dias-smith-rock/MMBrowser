import UIKit
import CoreLocation

protocol ContainerEditViewControllerDelegate: AnyObject {
    func containerEditDidSave(_ container: BrowserContainer, isNew: Bool)
}

/// Add / edit a container name and its Geolocation spoof settings.
final class ContainerEditViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIColorPickerViewControllerDelegate {
    weak var delegate: ContainerEditViewControllerDelegate?

    private let isNew: Bool
    private var draft: BrowserContainer
    private weak var tabManager: TabManager?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let nameField = UITextField()
    private let colorSwatches = AccountColorSwatchView()

    private enum Section: Int, CaseIterable {
        case template, name, color, identity, mode, spoofPreset, spoofCustom, management
    }

    init(container: BrowserContainer?, tabManager: TabManager? = nil, suggestedPresetIndex: Int = 0, template: ContainerTemplate = .custom) {
        self.tabManager = tabManager
        if let container {
            self.isNew = false
            self.draft = container
        } else {
            self.isNew = true
            self.draft = template.makeContainer(
                name: "",
                sortIndex: 0,
                colorIndex: suggestedPresetIndex % AccountColor.palette.count
            )
        }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew ? "Add Account" : "Edit Account"
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

        colorSwatches.onSelectPreset = { [weak self] index in
            guard let self else { return }
            self.draft.colorIndex = index
            self.draft.customColorHex = nil
            self.refreshColorSwatches()
        }
        colorSwatches.onSelectCustom = { [weak self] in
            self?.presentColorPicker()
        }

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
        refreshColorSwatches()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
        refreshColorSwatches()
    }

    @objc private func cancelTapped() {
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
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
            presentAlert("Enter an account name.")
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
        let alert = UIAlertController(title: "Account", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func refreshColorSwatches() {
        colorSwatches.configure(
            selectedPresetIndex: draft.colorIndex,
            customHex: draft.customColorHex
        )
    }

    private func presentColorPicker() {
        let picker = UIColorPickerViewController()
        picker.delegate = self
        picker.supportsAlpha = false
        if let hex = draft.customColorHex, let color = AccountColor.uiColor(fromHex: hex) {
            picker.selectedColor = color
        } else {
            picker.selectedColor = AccountColor.color(at: draft.colorIndex)
        }
        present(picker, animated: true)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        applyPickedColor(viewController.selectedColor)
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        // Live preview while dragging; commit on finish as well.
        applyPickedColor(viewController.selectedColor)
    }

    private func applyPickedColor(_ color: UIColor) {
        let hex = AccountColor.hexString(from: color)
        // If user lands exactly on a palette color, treat as preset.
        for i in 0..<AccountColor.palette.count {
            if AccountColor.matchesPalette(color, at: i) {
                draft.colorIndex = i
                draft.customColorHex = nil
                refreshColorSwatches()
                return
            }
        }
        draft.customColorHex = hex
        refreshColorSwatches()
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

    private func sectionKind(_ section: Int) -> Section? {
        Section(rawValue: section)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let kind = sectionKind(section) else { return 0 }
        switch kind {
        case .template: return isNew ? ContainerTemplate.allCases.count : 0
        case .name: return 1
        case .color: return 1
        case .identity: return UserAgentMode.allCases.count + 1
        case .mode: return LocationPrivacyMode.allCases.count
        case .spoofPreset: return draft.locationMode == .spoof ? SpoofLocationPreset.all.count : 0
        case .spoofCustom: return draft.locationMode == .spoof ? 1 : 0
        case .management: return (!isNew && tabManager != nil) ? 3 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let kind = sectionKind(section) else { return nil }
        switch kind {
        case .template: return isNew ? "Template" : nil
        case .name: return "Name"
        case .color: return "Color"
        case .identity: return "Identity Profile"
        case .mode: return "Location for Sites in This Account"
        case .spoofPreset: return draft.locationMode == .spoof ? "Virtual City" : nil
        case .spoofCustom: return draft.locationMode == .spoof ? "Custom" : nil
        case .management: return "Management"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let kind = sectionKind(section) else { return nil }
        switch kind {
        case .color:
            return "Tap a swatch, or + to pick a custom color."
        case .identity:
            return "Locale and user agent help sites see a consistent identity. Network IP is unchanged."
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

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        sectionKind(indexPath.section) == .color ? 98 : UITableView.automaticDimension
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
        cell.contentView.subviews.filter { $0 is UITextField || $0 is AccountColorSwatchView }.forEach { $0.removeFromSuperview() }
        cell.imageView?.image = nil
        cell.textLabel?.text = nil
        cell.detailTextLabel?.text = nil

        switch sectionKind(indexPath.section)! {
        case .template:
            let template = ContainerTemplate.allCases[indexPath.row]
            cell.textLabel?.text = template.displayName
            cell.detailTextLabel?.text = template.detail
            cell.accessoryType = draft.templateID == template.rawValue ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .name:
            cell.selectionStyle = .none
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
        case .color:
            cell.selectionStyle = .none
            if colorSwatches.superview != cell.contentView {
                colorSwatches.removeFromSuperview()
                cell.contentView.addSubview(colorSwatches)
                colorSwatches.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    colorSwatches.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
                    colorSwatches.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
                    colorSwatches.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    colorSwatches.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor)
                ])
            }
            refreshColorSwatches()
        case .identity:
            if indexPath.row < UserAgentMode.allCases.count {
                let mode = UserAgentMode.allCases[indexPath.row]
                cell.textLabel?.text = "User Agent: \(mode.displayName)"
                cell.detailTextLabel?.text = nil
                cell.accessoryType = draft.identity.userAgentMode == mode ? .checkmark : .none
            } else {
                cell.textLabel?.text = "Strip tracking URL parameters"
                cell.detailTextLabel?.text = draft.identity.stripTrackingParams ? "On" : "Off"
                cell.accessoryType = draft.identity.stripTrackingParams ? .checkmark : .none
            }
            cell.tintColor = BrowserTheme.chromeBlue
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
        case .management:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Site Data"
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Account Health"
                cell.accessoryType = .disclosureIndicator
            default:
                cell.textLabel?.text = "Split View"
                cell.accessoryType = .disclosureIndicator
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sectionKind(indexPath.section)! {
        case .template:
            let template = ContainerTemplate.allCases[indexPath.row]
            let preservedID = draft.id
            let preservedSession = draft.sessionID
            let built = template.makeContainer(name: draft.name, sortIndex: draft.sortIndex, colorIndex: draft.colorIndex)
            draft = BrowserContainer(
                id: preservedID,
                name: built.name,
                sessionID: preservedSession,
                sortIndex: built.sortIndex,
                colorIndex: built.colorIndex,
                customColorHex: built.customColorHex,
                locationMode: built.locationMode,
                latitude: built.latitude,
                longitude: built.longitude,
                timeZoneIdentifier: built.timeZoneIdentifier,
                locationPresetID: built.locationPresetID,
                pinnedSites: built.pinnedSites,
                persistence: .persistent,
                identity: built.identity,
                templateID: template.rawValue
            )
            nameField.text = draft.name
            tableView.reloadData()
        case .name:
            nameField.becomeFirstResponder()
        case .color:
            break
        case .identity:
            if indexPath.row < UserAgentMode.allCases.count {
                draft.identity.userAgentMode = UserAgentMode.allCases[indexPath.row]
            } else {
                draft.identity.stripTrackingParams.toggle()
            }
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
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
                if self.draft.timeZoneIdentifier.isEmpty {
                    self.draft.timeZoneIdentifier = SpoofLocationPreset.all[0].timeZoneIdentifier
                }
                self.tableView.reloadData()
            }
            navigationController?.pushViewController(picker, animated: true)
        case .management:
            guard let tabManager else { return }
            switch indexPath.row {
            case 0:
                navigationController?.pushViewController(ContainerSiteDataViewController(container: draft), animated: true)
            case 1:
                navigationController?.pushViewController(AccountHealthViewController(tabManager: tabManager, container: draft), animated: true)
            default:
                let containers = tabManager.sortedContainers.filter { $0.id != draft.id }
                guard let other = containers.first,
                      let url = URL(string: "https://www.google.com") else { return }
                let compare = DualAccountCompareViewController(
                    tabManager: tabManager,
                    leftContainer: draft,
                    rightContainer: other,
                    url: url
                )
                compare.modalPresentationStyle = .fullScreen
                present(compare, animated: true)
            }
        }
    }
}
