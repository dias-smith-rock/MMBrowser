import UIKit

enum AccountColor {
    static let palette: [UIColor] = [
        UIColor(red: 0.357, green: 0.555, blue: 0.937, alpha: 1), // #5B8DEF
        UIColor(red: 0.545, green: 0.486, blue: 0.965, alpha: 1), // #8B7CF6
        UIColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1), // #F59E0B
        UIColor(red: 0.063, green: 0.725, blue: 0.506, alpha: 1), // #10B981
        UIColor(red: 0.925, green: 0.282, blue: 0.600, alpha: 1), // #EC4899
        UIColor(red: 0.024, green: 0.714, blue: 0.831, alpha: 1), // #06B6D4
        UIColor(red: 0.976, green: 0.451, blue: 0.086, alpha: 1), // #F97316
        UIColor(red: 0.639, green: 0.639, blue: 0.639, alpha: 1)  // #A3A3A3
    ]

    static func color(at index: Int) -> UIColor {
        palette[abs(index) % palette.count]
    }

    static func color(for container: BrowserContainer) -> UIColor {
        if let hex = container.customColorHex, let custom = uiColor(fromHex: hex) {
            return custom
        }
        return color(at: container.colorIndex)
    }

    static func truncatedName(_ name: String, maxChars: Int = 10) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxChars else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: max(1, maxChars - 1))
        return String(trimmed[..<end]) + "…"
    }

    static func hexString(from color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let converted = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        converted.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }

    static func uiColor(fromHex hex: String) -> UIColor? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    static func matchesPalette(_ sample: UIColor, at index: Int) -> Bool {
        hexString(from: sample) == hexString(from: color(at: index))
    }
}

/// Compact color swatch grid: preset blocks + custom picker entry (2 rows).
final class AccountColorSwatchView: UIView {
    var onSelectPreset: ((Int) -> Void)?
    var onSelectCustom: (() -> Void)?

    private let column = UIStackView()
    private var swatchButtons: [UIButton] = []
    private let customButton = UIButton(type: .custom)
    private var selectedPresetIndex: Int = 0
    private var customHex: String?
    private let swatchSize: CGFloat = 34

    override init(frame: CGRect) {
        super.init(frame: frame)
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 10
        addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            column.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        let row1 = makeRow()
        let row2 = makeRow()
        column.addArrangedSubview(row1)
        column.addArrangedSubview(row2)

        for i in 0..<AccountColor.palette.count {
            let button = makeSwatchButton()
            button.backgroundColor = AccountColor.color(at: i)
            button.tag = i
            button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            button.accessibilityLabel = "Color \(i + 1)"
            swatchButtons.append(button)
            (i < 5 ? row1 : row2).addArrangedSubview(button)
        }

        styleCustomButton()
        customButton.addTarget(self, action: #selector(customTapped), for: .touchUpInside)
        customButton.accessibilityLabel = "Custom color"
        row2.addArrangedSubview(customButton)

        // Keep trailing flex so blocks stay left-aligned with even gaps.
        let spacer1 = UIView()
        let spacer2 = UIView()
        spacer1.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer2.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row1.addArrangedSubview(spacer1)
        row2.addArrangedSubview(spacer2)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(selectedPresetIndex: Int, customHex: String?) {
        self.selectedPresetIndex = selectedPresetIndex
        self.customHex = customHex
        refreshSelection()
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.distribution = .fill
        return row
    }

    private func makeSwatchButton() -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: swatchSize),
            button.heightAnchor.constraint(equalToConstant: swatchSize)
        ])
        return button
    }

    private func styleCustomButton() {
        customButton.layer.cornerRadius = 10
        customButton.clipsToBounds = true
        customButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            customButton.widthAnchor.constraint(equalToConstant: swatchSize),
            customButton.heightAnchor.constraint(equalToConstant: swatchSize)
        ])
        customButton.layer.borderWidth = 1
        customButton.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.45).cgColor
    }

    private func refreshSelection() {
        let usingCustom = customHex != nil
        for (i, button) in swatchButtons.enumerated() {
            let selected = !usingCustom && i == (selectedPresetIndex % AccountColor.palette.count)
            applySelection(to: button, selected: selected, fill: AccountColor.color(at: i))
        }

        if let hex = customHex, let color = AccountColor.uiColor(fromHex: hex) {
            applySelection(to: customButton, selected: true, fill: color)
        } else {
            customButton.backgroundColor = BrowserTheme.secondaryCard
            customButton.layer.borderWidth = 1
            customButton.layer.borderColor = BrowserTheme.textSecondary.withAlphaComponent(0.45).cgColor
            let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            customButton.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
            customButton.tintColor = BrowserTheme.textPrimary
        }
    }

    private func applySelection(to button: UIButton, selected: Bool, fill: UIColor) {
        button.backgroundColor = fill
        button.layer.borderWidth = selected ? 2.5 : 0
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
        if selected {
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
            button.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
            button.tintColor = contrastingLabel(on: fill)
        } else {
            button.setImage(nil, for: .normal)
        }
    }

    private func contrastingLabel(on color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.62 ? .black : .white
    }

    @objc private func presetTapped(_ sender: UIButton) {
        onSelectPreset?(sender.tag)
    }

    @objc private func customTapped() {
        onSelectCustom?()
    }
}
