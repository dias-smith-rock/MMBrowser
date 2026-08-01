import UIKit
import SnapKit

protocol FindInPageBarDelegate: AnyObject {
    func findBar(_ bar: FindInPageBar, didSearch text: String, forward: Bool)
    func findBarDidDismiss(_ bar: FindInPageBar)
}

final class FindInPageBar: UIView, UITextFieldDelegate {
    weak var delegate: FindInPageBarDelegate?
    private let field = UITextField()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BrowserTheme.elevated
        field.textColor = BrowserTheme.textPrimary
        field.tintColor = BrowserTheme.chromeBlue
        field.placeholder = "Find in page"
        field.returnKeyType = .search
        field.delegate = self
        field.borderStyle = .roundedRect
        field.backgroundColor = BrowserTheme.card
        field.autocapitalizationType = .none

        countLabel.textColor = BrowserTheme.textSecondary
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.text = ""

        let prev = UIButton(type: .system)
        prev.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        prev.tintColor = BrowserTheme.textPrimary
        prev.addTarget(self, action: #selector(prevTapped), for: .touchUpInside)
        let next = UIButton(type: .system)
        next.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        next.tintColor = BrowserTheme.textPrimary
        next.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = BrowserTheme.textPrimary
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [field, countLabel, prev, next, close])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }
        field.snp.makeConstraints { $0.width.greaterThanOrEqualTo(140) }
        countLabel.snp.makeConstraints { $0.width.greaterThanOrEqualTo(44) }
        countLabel.textAlignment = .center
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCountText(_ text: String) { countLabel.text = text }
    func focus() { field.becomeFirstResponder() }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.findBar(self, didSearch: textField.text ?? "", forward: true)
        return true
    }

    @objc private func prevTapped() { delegate?.findBar(self, didSearch: field.text ?? "", forward: false) }
    @objc private func nextTapped() { delegate?.findBar(self, didSearch: field.text ?? "", forward: true) }
    @objc private func closeTapped() {
        field.resignFirstResponder()
        delegate?.findBarDidDismiss(self)
    }
}
