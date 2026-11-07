import UIKit
import PhotosUI
import SnapKit

final class AppearanceSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, PHPickerViewControllerDelegate {
    enum FocusSection {
        case theme
        case wallpaper
    }

    private enum Section: Int, CaseIterable {
        case theme
        case wallpaper
        case fitMode
        case overlay
    }

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let packs = BuiltinThemePacks.all
    private let focus: FocusSection

    init(focus: FocusSection = .theme) {
        self.focus = focus
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Appearance"
        applyChrome()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(OverlayOpacityCell.self, forCellReuseIdentifier: OverlayOpacityCell.reuseID)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }

        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: .themeDidChange, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let section = focus == .theme ? Section.theme.rawValue : Section.wallpaper.rawValue
        let indexPath = IndexPath(row: 0, section: section)
        tableView.scrollToRow(at: indexPath, at: .top, animated: true)
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

    private var showsLayoutSections: Bool {
        HomeWallpaper.selected != .default
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .theme: return packs.count
        case .wallpaper:
            // presets + (Change / Remove when a custom photo exists)
            return HomeWallpaper.Option.allCases.count + (HomeWallpaper.hasCustomImage ? 2 : 0)
        case .fitMode: return showsLayoutSections ? HomeWallpaper.FitMode.allCases.count : 0
        case .overlay: return showsLayoutSections ? 1 : 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .theme: return "Theme"
        case .wallpaper: return "Wallpaper"
        case .fitMode: return showsLayoutSections ? "Display Mode" : nil
        case .overlay: return showsLayoutSections ? "Overlay" : nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .theme:
            return "Applies a full theme pack (colors and icons). Private browsing accent follows the selected theme."
        case .wallpaper:
            return "Affects Space home / New Tab. Forest and Midnight use photos; Custom lets you pick your own."
        case .fitMode:
            return showsLayoutSections ? "Fit keeps the full image. Tile repeats it. Stretch and Fill cover the screen." : nil
        case .overlay:
            return showsLayoutSections ? "Dark mask over the wallpaper so titles and icons stay readable. Wallpaper itself is slightly translucent." : nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        BrowserTheme.styleSectionHeaderFooter(view)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .theme:
            let cell = dequeueBasic(tableView)
            let pack = packs[indexPath.row]
            cell.textLabel?.text = pack.name
            cell.detailTextLabel?.text = pack.isLight ? "Light" : "Dark"
            cell.accessoryType = pack.id == ThemeManager.shared.current.id ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
            cell.imageView?.image = makeSwatch(for: pack)
            return cell
        case .wallpaper:
            let cell = dequeueBasic(tableView)
            let options = HomeWallpaper.Option.allCases
            if indexPath.row < options.count {
                let option = options[indexPath.row]
                cell.textLabel?.text = option.title
                if option == .custom {
                    cell.detailTextLabel?.text = HomeWallpaper.hasCustomImage ? "Your photo" : "Choose a photo"
                } else {
                    cell.detailTextLabel?.text = nil
                }
                cell.accessoryType = option == HomeWallpaper.selected ? .checkmark : .none
                cell.tintColor = BrowserTheme.chromeBlue
                cell.imageView?.image = HomeWallpaper.preview(at: option)
                cell.imageView?.layer.cornerRadius = 8
                cell.imageView?.clipsToBounds = true
            } else if indexPath.row == options.count {
                cell.textLabel?.text = "Change Custom Photo"
                cell.detailTextLabel?.text = nil
                cell.accessoryType = .disclosureIndicator
                cell.imageView?.image = nil
            } else {
                cell.textLabel?.text = "Remove Custom Photo"
                cell.textLabel?.textColor = .systemRed
                cell.detailTextLabel?.text = nil
                cell.accessoryType = .none
                cell.imageView?.image = nil
            }
            return cell
        case .fitMode:
            let cell = dequeueBasic(tableView)
            let mode = HomeWallpaper.FitMode.allCases[indexPath.row]
            cell.textLabel?.text = mode.title
            cell.detailTextLabel?.text = mode.detail
            cell.accessoryType = mode == HomeWallpaper.fitMode ? .checkmark : .none
            cell.tintColor = BrowserTheme.chromeBlue
            return cell
        case .overlay:
            let cell = tableView.dequeueReusableCell(withIdentifier: OverlayOpacityCell.reuseID, for: indexPath) as! OverlayOpacityCell
            cell.configure(
                opacity: AppSettings.homeWallpaperOverlayOpacity,
                onChange: { value in
                    AppSettings.setHomeWallpaperOverlayOpacity(value, notify: false)
                },
                onCommit: { value in
                    AppSettings.setHomeWallpaperOverlayOpacity(value, notify: true)
                }
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .theme:
            let pack = packs[indexPath.row]
            ThemeManager.shared.select(packID: pack.id)
            Toast.show("Theme: \(pack.name)", from: self)
        case .wallpaper:
            let options = HomeWallpaper.Option.allCases
            if indexPath.row < options.count {
                let option = options[indexPath.row]
                if option == .custom {
                    if HomeWallpaper.hasCustomImage {
                        AppSettings.homeWallpaperIndex = option.rawValue
                        Toast.show("Wallpaper: Custom", from: self)
                    } else {
                        presentPhotoPicker()
                    }
                } else {
                    AppSettings.homeWallpaperIndex = option.rawValue
                    Toast.show("Wallpaper: \(option.title)", from: self)
                }
            } else if indexPath.row == options.count {
                presentPhotoPicker()
            } else {
                HomeWallpaper.removeCustomImage()
                Toast.show("Custom photo removed", from: self)
            }
            tableView.reloadData()
        case .fitMode:
            let mode = HomeWallpaper.FitMode.allCases[indexPath.row]
            AppSettings.homeWallpaperFitMode = mode.rawValue
            Toast.show("Display: \(mode.title)", from: self)
            tableView.reloadSections(IndexSet(integer: Section.fitMode.rawValue), with: .none)
        case .overlay:
            break
        }
    }

    private func dequeueBasic(_ tableView: UITableView) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
        cell.detailTextLabel?.text = nil
        cell.accessoryType = .none
        cell.imageView?.image = nil
        cell.imageView?.layer.cornerRadius = 0
        cell.imageView?.clipsToBounds = false
        cell.selectionStyle = .default
        cell.textLabel?.textColor = BrowserTheme.textPrimary
        return cell
    }

    private func presentPhotoPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image = object as? UIImage else {
                    Toast.show("Could not load photo", from: self)
                    return
                }
                if HomeWallpaper.saveCustomImage(image) {
                    Toast.show("Wallpaper: Custom", from: self)
                    self.tableView.reloadData()
                } else {
                    Toast.show("Could not save photo", from: self)
                }
            }
        }
    }

    private func makeSwatch(for pack: ThemePack) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            pack.colors.background.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
            let accent = CGRect(x: 16, y: 16, width: 10, height: 10)
            pack.colors.accent.setFill()
            UIBezierPath(ovalIn: accent).fill()
        }
    }
}

// MARK: - Overlay slider cell

private final class OverlayOpacityCell: UITableViewCell {
    static let reuseID = "OverlayOpacityCell"

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let slider = UISlider()
    private var onChange: ((Double) -> Void)?
    private var onCommit: ((Double) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = BrowserTheme.card

        titleLabel.text = "Mask Strength"
        titleLabel.font = .systemFont(ofSize: 16)
        titleLabel.textColor = BrowserTheme.textPrimary

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        valueLabel.textColor = BrowserTheme.textSecondary
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        slider.minimumValue = 0.1
        slider.maximumValue = 0.8
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderCommitted), for: .touchUpInside)
        slider.addTarget(self, action: #selector(sliderCommitted), for: .touchUpOutside)
        slider.addTarget(self, action: #selector(sliderCommitted), for: .touchCancel)

        let header = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        header.axis = .horizontal
        header.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical
        stack.spacing = 8
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(
        opacity: Double,
        onChange: @escaping (Double) -> Void,
        onCommit: @escaping (Double) -> Void
    ) {
        backgroundColor = BrowserTheme.card
        titleLabel.textColor = BrowserTheme.textPrimary
        valueLabel.textColor = BrowserTheme.textSecondary
        self.onChange = onChange
        self.onCommit = onCommit
        slider.value = Float(opacity)
        valueLabel.text = "\(Int((opacity * 100).rounded()))%"
    }

    @objc private func sliderChanged() {
        let value = Double(slider.value)
        valueLabel.text = "\(Int((value * 100).rounded()))%"
        onChange?(value)
    }

    @objc private func sliderCommitted() {
        onCommit?(Double(slider.value))
    }
}
