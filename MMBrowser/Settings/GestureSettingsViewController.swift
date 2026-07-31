import UIKit
import SnapKit

final class GestureSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case toggles, bindings, practice }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Gestures"
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self, tableView: tableView)
        tableView.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .toggles: return 2
        case .bindings: return GestureShape.allCases.count
        case .practice: return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .toggles: return "Gestures"
        case .bindings: return "Shapes"
        case .practice: return "Practice"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .toggles:
            return "All shapes use one finger: Hook → back, Hook ← forward, Hook ○ bookmark. Plain swipes are ignored."
        case .bindings:
            return "Assign an action to each shape, or turn a shape off."
        case .practice:
            return "Use one finger on the practice pad to preview recognition."
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
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.selectionStyle = .default
        cell.imageView?.image = nil
        cell.imageView?.tintColor = BrowserTheme.chromeBlue

        switch Section(rawValue: indexPath.section)! {
        case .toggles:
            cell.selectionStyle = .none
            let sw = UISwitch()
            if indexPath.row == 0 {
                cell.textLabel?.text = "Navigation Hooks"
                cell.detailTextLabel?.text = "One-finger Hook → / Hook ←"
                sw.isOn = AppSettings.navigationSwipeEnabled
                sw.addTarget(self, action: #selector(swipeChanged(_:)), for: .valueChanged)
            } else {
                cell.textLabel?.text = "Circle Gesture"
                cell.detailTextLabel?.text = "One-finger Hook ○"
                sw.isOn = AppSettings.drawingGesturesEnabled
                sw.addTarget(self, action: #selector(drawingChanged(_:)), for: .valueChanged)
            }
            cell.accessoryView = sw
        case .bindings:
            let shape = GestureShape.allCases[indexPath.row]
            cell.textLabel?.text = shape.displayName
            cell.detailTextLabel?.text = GestureActionMap.action(for: shape, respectingToggles: false).displayName
            cell.imageView?.image = UIImage(systemName: shape.symbolName)
            cell.accessoryType = .disclosureIndicator
        case .practice:
            cell.textLabel?.text = "Practice Pad"
            cell.detailTextLabel?.text = "Try drawing with one finger"
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .toggles:
            break
        case .bindings:
            presentActionPicker(for: GestureShape.allCases[indexPath.row])
        case .practice:
            navigationController?.pushViewController(GesturePracticeViewController(), animated: true)
        }
    }

    private func presentActionPicker(for shape: GestureShape) {
        let sheet = UIAlertController(title: shape.displayName, message: "Choose action", preferredStyle: .actionSheet)
        for action in GestureBrowserAction.allCases {
            let title = action == GestureActionMap.action(for: shape, respectingToggles: false) ? "✓ \(action.displayName)" : action.displayName
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                GestureActionMap.setAction(action, for: shape)
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = tableView
            pop.sourceRect = tableView.rectForRow(at: IndexPath(row: GestureShape.allCases.firstIndex(of: shape) ?? 0, section: Section.bindings.rawValue))
        }
        present(sheet, animated: true)
    }

    @objc private func swipeChanged(_ sw: UISwitch) {
        AppSettings.navigationSwipeEnabled = sw.isOn
    }

    @objc private func drawingChanged(_ sw: UISwitch) {
        AppSettings.drawingGesturesEnabled = sw.isOn
    }
}

// MARK: - Practice

final class GesturePracticeViewController: UIViewController, DrawingGestureControllerDelegate {
    private let pad = UIView()
    private let resultLabel = UILabel()
    private let hintLabel = UILabel()
    private let drawing = DrawingGestureController()
    private var savedInteractivePopEnabled = true

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Practice"
        BrowserTheme.applyScreenChrome(to: self)
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyNavigationBar(to: navigationBar)
        }

        hintLabel.text = "Draw with one finger: Hook → ← or ○"
        hintLabel.textColor = BrowserTheme.textSecondary
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.textAlignment = .center

        resultLabel.text = "—"
        resultLabel.textColor = BrowserTheme.textPrimary
        resultLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 2

        pad.backgroundColor = BrowserTheme.card
        pad.layer.cornerRadius = 16
        pad.clipsToBounds = true
        pad.isMultipleTouchEnabled = true

        view.addSubview(hintLabel)
        view.addSubview(pad)
        view.addSubview(resultLabel)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        pad.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            pad.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 16),
            pad.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pad.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pad.heightAnchor.constraint(equalTo: pad.widthAnchor, multiplier: 1.1),

            resultLabel.topAnchor.constraint(equalTo: pad.bottomAnchor, constant: 20),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        drawing.delegate = self
        drawing.ignoresGlobalToggle = true
        // Attach to the full screen so competing nav pans can't steal the stroke;
        // the visible pad is still the drawing target area users aim for.
        drawing.attach(to: view, lockScrollView: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        BrowserTheme.applyScreenChrome(to: self)
        // Practice pans were also driving the interactive pop gesture,
        // which slid the whole page under the stroke.
        savedInteractivePopEnabled = navigationController?.interactivePopGestureRecognizer?.isEnabled ?? true
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = savedInteractivePopEnabled
    }

    deinit {
        drawing.detach()
    }

    func drawingGestureController(_ controller: DrawingGestureController, didRecognize shape: GestureShape, action: GestureBrowserAction) {
        let actionText = action == .none ? "Off" : action.displayName
        resultLabel.text = "\(shape.displayName)\n→ \(actionText)"
    }
}
