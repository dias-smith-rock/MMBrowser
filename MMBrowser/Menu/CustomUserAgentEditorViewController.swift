import UIKit

protocol CustomUserAgentEditorDelegate: AnyObject {
    func customUserAgentEditor(_ editor: CustomUserAgentEditorViewController, didSave profile: CustomUserAgentProfile)
}

/// Client Hints picker used when a tab's user agent is Custom.
final class CustomUserAgentEditorViewController: UITableViewController {
    weak var delegate: CustomUserAgentEditorDelegate?

    private var profile: CustomUserAgentProfile
    private let isIncognito: Bool

    private enum Section: Int, CaseIterable {
        case brand
        case mobile
        case platform
        case fullVersion
        case model
        case architecture
    }

    init(profile: CustomUserAgentProfile, isIncognito: Bool) {
        self.profile = profile
        self.isIncognito = isIncognito
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Custom User Agent"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
        tableView.register(SubtitleTableCell.self, forCellReuseIdentifier: "cell")
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        view.backgroundColor = isIncognito ? BrowserTheme.privateBackground : BrowserTheme.background
    }

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .brand: return ClientHintBrand.allCases.count
        case .mobile: return 2
        case .platform: return ClientHintPlatform.allCases.count
        case .fullVersion: return 2
        case .model: return ClientHintModel.options(for: profile.platform).count
        case .architecture: return ClientHintArchitecture.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .brand: return "Browser"
        case .mobile: return "Device type"
        case .platform: return "Operating system"
        case .fullVersion: return "Exact browser version"
        case .model: return "Device model"
        case .architecture: return "Processor"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .brand:
            return "Choose which browser this tab should look like."
        case .mobile:
            return "Phone sites show the mobile layout. Computer sites show the desktop layout."
        case .platform:
            return "The operating system websites think you are using."
        case .fullVersion:
            return "Optional. Some sites check the full version number, not just 124 or 131."
        case .model:
            switch profile.platform {
            case .windows, .macOS, .linux:
                return "Optional. Computers usually don’t send a model — Don’t send is what Chrome does on Windows."
            case .android, .iOS:
                return "Optional. Only needed if you want to look like a specific phone."
            }
        case .architecture:
            return "Optional. Most people can leave this unsent."
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        BrowserTheme.styleListCell(cell)
        cell.detailTextLabel?.text = nil
        let selected: Bool
        switch Section(rawValue: indexPath.section)! {
        case .brand:
            let brand = ClientHintBrand.allCases[indexPath.row]
            cell.textLabel?.text = brand.displayName
            selected = profile.brand == brand
        case .mobile:
            let isMobile = indexPath.row == 0
            cell.textLabel?.text = isMobile ? "Phone" : "Computer"
            selected = profile.isMobile == isMobile
        case .platform:
            let platform = ClientHintPlatform.allCases[indexPath.row]
            cell.textLabel?.text = platform.displayName
            selected = profile.platform == platform
        case .fullVersion:
            let include = indexPath.row == 1
            cell.textLabel?.text = include ? "Send full version" : "Don’t send"
            if include {
                cell.detailTextLabel?.text = profile.brand.fullVersion
            }
            selected = profile.includeFullVersionList == include
        case .model:
            let model = ClientHintModel.options(for: profile.platform)[indexPath.row]
            cell.textLabel?.text = model.displayName
            selected = profile.model == model
        case .architecture:
            let arch = ClientHintArchitecture.allCases[indexPath.row]
            cell.textLabel?.text = arch.displayName
            selected = profile.architecture == arch
        }
        cell.accessoryType = selected ? .checkmark : .none
        cell.tintColor = isIncognito ? BrowserTheme.privateAccent : BrowserTheme.chromeBlue
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .brand:
            profile.brand = ClientHintBrand.allCases[indexPath.row]
        case .mobile:
            profile.isMobile = indexPath.row == 0
        case .platform:
            profile.platform = ClientHintPlatform.allCases[indexPath.row]
            let allowed = ClientHintModel.options(for: profile.platform)
            if !allowed.contains(profile.model) {
                profile.model = .none
            }
        case .fullVersion:
            profile.includeFullVersionList = indexPath.row == 1
        case .model:
            profile.model = ClientHintModel.options(for: profile.platform)[indexPath.row]
        case .architecture:
            profile.architecture = ClientHintArchitecture.allCases[indexPath.row]
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    @objc private func saveTapped() {
        delegate?.customUserAgentEditor(self, didSave: profile)
    }
}

final class SubtitleTableCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        textLabel?.numberOfLines = 1
        detailTextLabel?.numberOfLines = 2
        detailTextLabel?.font = .systemFont(ofSize: 11)
    }

    required init?(coder: NSCoder) { fatalError() }
}
