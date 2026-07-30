import UIKit
import SnapKit

/// iOS-style passcode digits row (hollow / filled circles).
final class PasscodeDotsView: UIView {
    private var dots: [UIView] = []
    private let count: Int

    init(count: Int = 4) {
        self.count = count
        super.init(frame: .zero)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 22
        stack.alignment = .center
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        for _ in 0..<count {
            let dot = UIView()
            dot.backgroundColor = .clear
            dot.layer.borderWidth = 1.5
            dot.layer.borderColor = UIColor.white.cgColor
            dot.snp.makeConstraints { $0.size.equalTo(13) }
            dot.layer.cornerRadius = 6.5
            dots.append(dot)
            stack.addArrangedSubview(dot)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setFilledCount(_ filled: Int, animated: Bool = true) {
        for (i, dot) in dots.enumerated() {
            let on = i < filled
            let apply = {
                dot.backgroundColor = on ? UIColor.white : .clear
            }
            if animated {
                UIView.animate(withDuration: 0.08, animations: apply)
            } else {
                apply()
            }
        }
    }

    func shake() {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.duration = 0.4
        anim.values = [-12, 12, -10, 10, -6, 6, -2, 2, 0]
        layer.add(anim, forKey: "shake")
    }
}

protocol PasscodeKeypadViewDelegate: AnyObject {
    func passcodeKeypad(_ view: PasscodeKeypadView, didTapDigit digit: String)
    func passcodeKeypadDidTapDelete(_ view: PasscodeKeypadView)
}

/// Circular translucent keypad matching iOS passcode chrome.
/// Bottom-left slot mirrors the system lock screen (Emergency / Face ID); Delete sits bottom-right.
final class PasscodeKeypadView: UIView {
    weak var delegate: PasscodeKeypadViewDelegate?

    private let keySize: CGFloat = 76
    private let bottomLeftSlot = UIView()
    private var bottomLeftContent: UIView?

    private let letters: [String: String] = [
        "2": "A B C", "3": "D E F", "4": "G H I", "5": "J K L",
        "6": "M N O", "7": "P Q R S", "8": "T U V", "9": "W X Y Z"
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        let columnStack = UIStackView()
        columnStack.axis = .vertical
        columnStack.spacing = 16
        columnStack.alignment = .center
        addSubview(columnStack)
        columnStack.snp.makeConstraints { $0.edges.equalToSuperview() }

        let rows: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"]
        ]
        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 24
            rowStack.alignment = .center
            for key in row {
                rowStack.addArrangedSubview(makeDigitKey(key))
            }
            columnStack.addArrangedSubview(rowStack)
        }

        let bottomRow = UIStackView()
        bottomRow.axis = .horizontal
        bottomRow.spacing = 24
        bottomRow.alignment = .center
        bottomLeftSlot.snp.makeConstraints { $0.size.equalTo(keySize) }
        bottomRow.addArrangedSubview(bottomLeftSlot)
        bottomRow.addArrangedSubview(makeDigitKey("0"))
        bottomRow.addArrangedSubview(makeDeleteKey())
        columnStack.addArrangedSubview(bottomRow)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Places a control in the system bottom-left slot (typically Face ID / Touch ID).
    func setBottomLeftAccessory(_ view: UIView?) {
        bottomLeftContent?.removeFromSuperview()
        bottomLeftContent = view
        guard let view = view else { return }
        bottomLeftSlot.addSubview(view)
        view.snp.makeConstraints { $0.center.equalToSuperview() }
    }

    private func makeDigitKey(_ key: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = Int(key) ?? -1
        button.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        button.layer.cornerRadius = keySize / 2
        button.clipsToBounds = true
        button.snp.makeConstraints { $0.size.equalTo(keySize) }

        let number = UILabel()
        number.text = key
        number.textColor = .white
        number.font = .systemFont(ofSize: 32, weight: .regular)
        number.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [number])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = -2
        stack.isUserInteractionEnabled = false

        if let letters = letters[key] {
            let sub = UILabel()
            sub.text = letters
            sub.textColor = UIColor.white.withAlphaComponent(0.7)
            sub.font = .systemFont(ofSize: 9, weight: .semibold)
            sub.textAlignment = .center
            stack.addArrangedSubview(sub)
        } else if key == "0" {
            let sub = UILabel()
            sub.text = " "
            sub.font = .systemFont(ofSize: 9, weight: .semibold)
            stack.addArrangedSubview(sub)
        }

        button.addSubview(stack)
        stack.snp.makeConstraints { $0.center.equalToSuperview() }
        button.addTarget(self, action: #selector(digitTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(digitTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.addTarget(self, action: #selector(digitTapped(_:)), for: .touchUpInside)
        return button
    }

    private func makeDeleteKey() -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("Delete", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        button.snp.makeConstraints { $0.size.equalTo(keySize) }
        button.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        return button
    }

    @objc private func digitTouchDown(_ sender: UIButton) {
        sender.backgroundColor = UIColor.white.withAlphaComponent(0.45)
    }

    @objc private func digitTouchUp(_ sender: UIButton) {
        sender.backgroundColor = UIColor.white.withAlphaComponent(0.18)
    }

    @objc private func digitTapped(_ sender: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.passcodeKeypad(self, didTapDigit: "\(sender.tag)")
    }

    @objc private func deleteTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.passcodeKeypadDidTapDelete(self)
    }
}
