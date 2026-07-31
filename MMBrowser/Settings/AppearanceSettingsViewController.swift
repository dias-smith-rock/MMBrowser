import UIKit
import SnapKit

final class AppearanceSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Section: Int, CaseIterable { case theme, wallpaper }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let packs = BuiltinThemePacks.all
    private let wallpaperNames = ["Default", "Deep Blue", "Forest", "Midnight"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Appearance"
        applyChrome()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
        tableView.reloadData()
    }

    @objc private func themeChanged() {
        applyChrome()
        tableView.reloadData()
    }

    private func applyChrome() {
        view.backgroundColor = BrowserTheme.background
        tableView.backgroundColor = BrowserTheme.background
        tableView.overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        overrideUserInterfaceStyle = BrowserTheme.preferredUserInterfaceStyle
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .theme: return packs.count
        case .wallpaper: return wallpaperNames.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .theme: return "Theme"
        case .wallpaper: return "Wallpaper"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .theme:
            return "Applies a full theme pack (colors and icons). Private browsing accent follows the selected theme."
        case .wallpaper:
            return "Affects the new tab page only. Deep Blue / Forest / Midnight adapt tint and depth to the current theme."
        }
    }

    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .none
        cell.imageView?.image = nil
        cell.selectionStyle = .default

        switch Section(rawValue: indexPath.section)! {
        case .theme:
            let pack = packs[indexPath.row]
            cell.textLabel?.text = pack.name
            cell.detailTextLabel?.text = pack.isLight ? "Light" : "Dark"
            cell.accessoryType = pack.id == ThemeManager.shared.current.id ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
            cell.imageView?.image = makeSwatch(for: pack)
        case .wallpaper:
            let name = wallpaperNames[indexPath.row]
            cell.textLabel?.text = name
            cell.accessoryType = indexPath.row == AppSettings.homeWallpaperIndex % wallpaperNames.count ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .theme:
            let pack = packs[indexPath.row]
            ThemeManager.shared.select(packID: pack.id)
            Toast.show("Theme: \(pack.name)", from: self)
        case .wallpaper:
            AppSettings.homeWallpaperIndex = indexPath.row
            tableView.reloadSections(IndexSet(integer: Section.wallpaper.rawValue), with: .none)
            Toast.show("Wallpaper: \(wallpaperNames[indexPath.row])", from: self)
        }
    }

    private func makeSwatch(for pack: ThemePack) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            pack.colors.background.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
            let accent = CGRect(x: 16, y: 16, width: 10, height: 10)
            pack.colors.accent.setFill()
            UIBezierPath(ovalIn: accent).fill()
        }
    }
}
