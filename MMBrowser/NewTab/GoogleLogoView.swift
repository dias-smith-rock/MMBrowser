import UIKit
import SnapKit

final class GoogleLogoView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 40, weight: .bold)
        label.textColor = .white
        label.text = "MMBrowser"
        addSubview(label)
        label.snp.makeConstraints { make in make.edges.equalToSuperview() }
    }

    required init?(coder: NSCoder) { fatalError() }
}
