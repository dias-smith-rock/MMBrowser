import UIKit
import SnapKit

final class GoogleLogoView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        iconView.image = UIImage(named: "MMBrowserLogo")
        iconView.contentMode = .scaleAspectFit
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 12

        label.textAlignment = .left
        label.font = .systemFont(ofSize: 34, weight: .bold)
        label.textColor = .white
        label.text = "MMBrowser"

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)

        iconView.snp.makeConstraints { make in
            make.size.equalTo(48)
        }
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.bottom.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}
