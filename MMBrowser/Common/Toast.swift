import UIKit

enum Toast {
    private static weak var currentBanner: UIView?

    /// Non-modal HUD so it never blocks subsequent `present(...)` (e.g. screenshot editor).
    static func show(_ message: String, from viewController: UIViewController) {
        let host = viewController.viewIfLoaded?.window
            ?? viewController.navigationController?.view
            ?? viewController.tabBarController?.view
            ?? viewController.view
        guard let host = host else { return }

        currentBanner?.removeFromSuperview()

        let banner = UIView()
        banner.backgroundColor = UIColor(white: 0.12, alpha: 0.94)
        banner.layer.cornerRadius = 12
        banner.clipsToBounds = true
        banner.alpha = 0
        banner.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(label)
        host.addSubview(banner)
        currentBanner = banner

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -16),
            banner.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: host.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            banner.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        UIView.animate(withDuration: 0.2) { banner.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak banner] in
            guard let banner = banner else { return }
            UIView.animate(withDuration: 0.2, animations: {
                banner.alpha = 0
            }, completion: { _ in
                banner.removeFromSuperview()
                if currentBanner === banner { currentBanner = nil }
            })
        }
    }
}
