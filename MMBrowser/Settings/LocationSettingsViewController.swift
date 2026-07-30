import MapKit
import UIKit

/// Location privacy: Deny / Spoof / Ask. Spoof does not change network IP.
final class LocationSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case mode, spoofPreset, spoofCustom, note }

    var onChanged: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Location"
        view.backgroundColor = BrowserTheme.background
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyDarkNavigationBar(to: navigationBar)
        }
        tableView.overrideUserInterfaceStyle = .dark
        tableView.backgroundColor = BrowserTheme.background
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
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
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .mode: return LocationPrivacyMode.allCases.count
        case .spoofPreset: return AppSettings.locationPrivacyMode == .spoof ? SpoofLocationPreset.all.count : 0
        case .spoofCustom: return AppSettings.locationPrivacyMode == .spoof ? 1 : 0
        case .note: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .mode: return "When Sites Ask for Location"
        case .spoofPreset: return AppSettings.locationPrivacyMode == .spoof ? "Virtual City" : nil
        case .spoofCustom: return AppSettings.locationPrivacyMode == .spoof ? "Custom" : nil
        case .note: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .mode:
            return "Deny and Spoof only affect the browser Geolocation API. Sites that detect your network IP cannot be changed without a VPN or proxy."
        case .spoofPreset:
            return AppSettings.locationPrivacyMode == .spoof
                ? "Spoof also adjusts JavaScript timezone to match the selected city when possible."
                : nil
        case .spoofCustom:
            return nil
        case .note:
            return "Changing virtual location only affects sites that ask the browser for GPS-like coordinates."
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.accessoryType = .none
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .mode:
            let mode = LocationPrivacyMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.displayName
            cell.detailTextLabel?.text = mode.detail
            cell.accessoryType = mode == AppSettings.locationPrivacyMode ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .spoofPreset:
            let preset = SpoofLocationPreset.all[indexPath.row]
            cell.textLabel?.text = preset.name
            cell.detailTextLabel?.text = String(format: "%.2f, %.2f · %@", preset.latitude, preset.longitude, preset.timeZoneIdentifier)
            let selected = !isCustomSpoofSelected
                && abs(AppSettings.spoofLatitude - preset.latitude) < 0.0001
                && abs(AppSettings.spoofLongitude - preset.longitude) < 0.0001
            cell.accessoryType = selected ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        case .spoofCustom:
            cell.textLabel?.text = "Choose on Map…"
            cell.detailTextLabel?.text = String(format: "%.5f, %.5f", AppSettings.spoofLatitude, AppSettings.spoofLongitude)
            if isCustomSpoofSelected {
                cell.accessoryType = .checkmark
                cell.tintColor = BrowserTheme.chromeBlue
            } else {
                cell.accessoryType = .disclosureIndicator
            }
        case .note:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .mode:
            let mode = LocationPrivacyMode.allCases[indexPath.row]
            AppSettings.locationPrivacyMode = mode
            if mode == .spoof, AppSettings.spoofPresetID.isEmpty {
                applyPreset(SpoofLocationPreset.all[0])
            }
            notify()
            tableView.reloadData()
        case .spoofPreset:
            applyPreset(SpoofLocationPreset.all[indexPath.row])
            notify()
            tableView.reloadData()
        case .spoofCustom:
            presentMapPicker()
        case .note:
            break
        }
    }

    private var isCustomSpoofSelected: Bool {
        if AppSettings.spoofPresetID == "custom" { return true }
        return !SpoofLocationPreset.all.contains {
            abs(AppSettings.spoofLatitude - $0.latitude) < 0.0001
                && abs(AppSettings.spoofLongitude - $0.longitude) < 0.0001
        }
    }

    private func applyPreset(_ preset: SpoofLocationPreset) {
        AppSettings.spoofPresetID = preset.id
        AppSettings.spoofLatitude = preset.latitude
        AppSettings.spoofLongitude = preset.longitude
        AppSettings.spoofTimeZoneIdentifier = preset.timeZoneIdentifier
    }

    private func presentMapPicker() {
        let picker = LocationMapPickerViewController()
        picker.initialCoordinate = CLLocationCoordinate2D(
            latitude: AppSettings.spoofLatitude,
            longitude: AppSettings.spoofLongitude
        )
        picker.onPick = { [weak self] coordinate in
            guard let self = self else { return }
            AppSettings.spoofPresetID = "custom"
            AppSettings.spoofLatitude = coordinate.latitude
            AppSettings.spoofLongitude = coordinate.longitude
            self.notify()
            self.tableView.reloadData()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func notify() {
        NotificationCenter.default.post(name: .locationPrivacyChanged, object: nil)
        onChanged?()
    }
}
