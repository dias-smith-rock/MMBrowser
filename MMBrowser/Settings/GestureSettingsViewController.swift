import UIKit
import SnapKit

final class GestureSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private enum Section: Int, CaseIterable { case toggles, bindings, practice }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Gestures"
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
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        case .toggles: return "Browsing Gestures"
        case .bindings: return "Drawing Shapes"
        case .practice: return "Practice"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .toggles:
            return "Swipe left/right with one finger for back and forward. Draw shapes with two fingers on the page."
        case .bindings:
            return "Assign an action to each shape, or turn a shape off."
        case .practice:
            return "Use two fingers on the practice pad to preview recognition."
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        cell.backgroundColor = BrowserTheme.card
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = BrowserTheme.textSecondary
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
                cell.textLabel?.text = "Navigation Swipes"
                cell.detailTextLabel?.text = "One-finger left / right → back / forward"
                sw.isOn = AppSettings.navigationSwipeEnabled
                sw.addTarget(self, action: #selector(swipeChanged(_:)), for: .valueChanged)
            } else {
                cell.textLabel?.text = "Drawing Gestures"
                cell.detailTextLabel?.text = "Two-finger shapes on the page"
                sw.isOn = AppSettings.drawingGesturesEnabled
                sw.addTarget(self, action: #selector(drawingChanged(_:)), for: .valueChanged)
            }
            cell.accessoryView = sw
        case .bindings:
            let shape = GestureShape.allCases[indexPath.row]
            cell.textLabel?.text = shape.displayName
            cell.detailTextLabel?.text = GestureActionMap.action(for: shape).displayName
            cell.imageView?.image = UIImage(systemName: shape.symbolName)
            cell.accessoryType = .disclosureIndicator
        case .practice:
            cell.textLabel?.text = "Practice Pad"
            cell.detailTextLabel?.text = "Try drawing with two fingers"
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
            let title = action == GestureActionMap.action(for: shape) ? "✓ \(action.displayName)" : action.displayName
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

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Practice"
        view.backgroundColor = BrowserTheme.background
        if let navigationBar = navigationController?.navigationBar {
            BrowserTheme.applyDarkNavigationBar(to: navigationBar)
        }

        hintLabel.text = "Draw with two fingers"
        hintLabel.textColor = BrowserTheme.textSecondary
        hintLabel.font = .systemFont(ofSize: 14)
        hintLabel.textAlignment = .center

        resultLabel.text = "—"
        resultLabel.textColor = .white
        resultLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 2

        pad.backgroundColor = BrowserTheme.card
        pad.layer.cornerRadius = 16
        pad.clipsToBounds = true

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
        drawing.attach(to: pad)
    }

    func drawingGestureController(_ controller: DrawingGestureController, didRecognize shape: GestureShape, action: GestureBrowserAction) {
        let actionText = action == .none ? "Off" : action.displayName
        resultLabel.text = "\(shape.displayName)\n→ \(actionText)"
    }
}
