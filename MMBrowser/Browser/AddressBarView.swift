import UIKit
import SnapKit

protocol AddressBarViewDelegate: AnyObject {
    func addressBarDidSubmit(_ text: String)
    func addressBarDidTapShare()
    func addressBarDidTapLens()
}

final class AddressBarView: UIView, UITextFieldDelegate {
    weak var delegate: AddressBarViewDelegate?

    private let container = UIView()
    private let lensButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    let textField = UITextField()
    private let progressView = UIProgressView(progressViewStyle: .bar)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BrowserTheme.background

        container.backgroundColor = BrowserTheme.elevated
        container.layer.cornerRadius = 22
        addSubview(container)

        lensButton.setImage(UIImage(systemName: "camera.viewfinder"), for: .normal)
        lensButton.tintColor = BrowserTheme.textSecondary
        lensButton.addTarget(self, action: #selector(lensTapped), for: .touchUpInside)

        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = BrowserTheme.textSecondary
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        textField.textColor = BrowserTheme.textPrimary
        textField.tintColor = BrowserTheme.chromeBlue
        textField.font = .systemFont(ofSize: 15, weight: .medium)
        textField.textAlignment = .center
        textField.returnKeyType = .go
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .webSearch
        textField.delegate = self
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search or type URL",
            attributes: [.foregroundColor: BrowserTheme.textSecondary]
        )

        progressView.progressTintColor = BrowserTheme.chromeBlue
        progressView.trackTintColor = .clear
        progressView.isHidden = true

        container.addSubview(lensButton)
        container.addSubview(textField)
        container.addSubview(shareButton)
        addSubview(progressView)

        container.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.top.equalToSuperview().offset(4)
            make.height.equalTo(40)
        }
        lensButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }
        shareButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.size.equalTo(24)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(lensButton.snp.trailing).offset(8)
            make.trailing.equalTo(shareButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }
        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(container.snp.top)
            make.height.equalTo(2)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setURLText(_ text: String) {
        textField.text = text
    }

    func setProgress(_ progress: Double, isLoading: Bool) {
        progressView.isHidden = !isLoading
        progressView.setProgress(Float(progress), animated: true)
        if !isLoading {
            progressView.setProgress(0, animated: false)
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.textAlignment = .left
        textField.selectAll(nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.textAlignment = .center
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.addressBarDidSubmit(textField.text ?? "")
        textField.resignFirstResponder()
        return true
    }

    @objc private func shareTapped() { delegate?.addressBarDidTapShare() }
    @objc private func lensTapped() { delegate?.addressBarDidTapLens() }
}
