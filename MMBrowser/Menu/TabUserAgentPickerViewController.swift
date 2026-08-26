import UIKit

protocol TabUserAgentPickerDelegate: AnyObject {
    func tabUserAgentPicker(_ picker: TabUserAgentPickerViewController, didSelect settings: TabUserAgentSettings)
}

/// Per-tab user agent mode picker (Automatic / Mobile / Desktop / Custom).
final class TabUserAgentPickerViewController: UITableViewController {
    weak var delegate: TabUserAgentPickerDelegate?

    private var settings: TabUserAgentSettings
    private let isIncognito: Bool

    init(settings: TabUserAgentSettings, isIncognito: Bool) {
        self.settings = settings
        self.isIncognito = isIncognito
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "How this tab looks"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        tableView.register(SubtitleTableCell.self, forCellReuseIdentifier: "cell")
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        view.backgroundColor = isIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        UserAgentMode.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Applies to this tab only. New tabs use your account default unless opened from a link."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        BrowserTheme.styleListCell(cell)
        let mode = UserAgentMode.allCases[indexPath.row]
        cell.textLabel?.text = mode.displayName
        if mode == .custom, settings.userAgentMode == .custom {
            if let profile = settings.customProfile {
                cell.detailTextLabel?.text = profile.summary
            } else if let custom = settings.customUserAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !custom.isEmpty {
                cell.detailTextLabel?.text = String(custom.prefix(48)) + (custom.count > 48 ? "…" : "")
            } else {
                cell.detailTextLabel?.text = nil
            }
        } else {
            cell.detailTextLabel?.text = nil
        }
        cell.accessoryType = settings.userAgentMode == mode ? .checkmark : .none
        cell.tintColor = isIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let mode = UserAgentMode.allCases[indexPath.row]
        if mode == .custom {
            presentCustomEditor()
            return
        }
        settings.userAgentMode = mode
        settings.customUserAgent = nil
        settings.customProfile = nil
        tableView.reloadData()
        delegate?.tabUserAgentPicker(self, didSelect: settings)
    }

    private func presentCustomEditor() {
        if let sheet = navigationController?.sheetPresentationController {
            sheet.selectedDetentIdentifier = .large
        }
        let editor = CustomUserAgentEditorViewController(
            profile: settings.customProfile ?? .default,
            isIncognito: isIncognito
        )
        editor.delegate = self
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}

extension TabUserAgentPickerViewController: CustomUserAgentEditorDelegate {
    func customUserAgentEditor(_ editor: CustomUserAgentEditorViewController, didSave profile: CustomUserAgentProfile) {
        settings = TabUserAgentSettings(
            userAgentMode: .custom,
            customUserAgent: profile.userAgentString,
            customProfile: profile
        )
        tableView.reloadData()
        delegate?.tabUserAgentPicker(self, didSelect: settings)
    }
}
