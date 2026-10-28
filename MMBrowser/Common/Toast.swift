import UIKit

enum Toast {
    private static weak var currentBanner: UIView?

    /// Non-modal HUD so it never blocks subsequent `present(...)` (e.g. screenshot editor).
    static func show(_ message: String, from viewController: UIViewController) {
        show(message, from: viewController, actionTitle: nil, action: nil, duration: 2.0)
    }

    static func show(
        _ message: String,
        from viewController: UIViewController,
        actionTitle: String?,
        action: (() -> Void)?,
        duration: TimeInterval = 2.0
    ) {
        let host = viewController.viewIfLoaded?.window
            ?? viewController.navigationController?.view
            ?? viewController.tabBarController?.view
            ?? viewController.view
        guard let host = host else { return }

        currentBanner?.removeFromSuperview()

        let banner = UIView()
        banner.backgroundColor = UIColor(white: 0.12, alpha: 1)
        banner.layer.cornerRadius = 22
        banner.layer.cornerCurve = .continuous
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = 0.28
        banner.layer.shadowRadius = 16
        banner.layer.shadowOffset = CGSize(width: 0, height: 8)
        banner.alpha = 0
        banner.transform = CGAffineTransform(translationX: 0, y: 10)
        banner.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = actionTitle == nil ? .center : .left
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(label)

        var actionButton: UIButton?
        if let actionTitle, let action {
            var config = UIButton.Configuration.plain()
            config.title = actionTitle
            config.baseForegroundColor = UIColor(white: 1, alpha: 0.92)
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 16, weight: .bold)
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addAction(UIAction { _ in
                banner.removeFromSuperview()
                if currentBanner === banner { currentBanner = nil }
                action()
            }, for: .touchUpInside)
            banner.addSubview(button)
            actionButton = button
        }

        host.addSubview(banner)
        currentBanner = banner

        // Sit clearly above the bottom address bar + toolbar, not tucked into them.
        let chromeLift = BrowserTheme.chromeHeight + 12
        let maxTextWidth = label.widthAnchor.constraint(
            lessThanOrEqualTo: host.widthAnchor,
            constant: -88
        )
        maxTextWidth.priority = .required

        var constraints: [NSLayoutConstraint] = [
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 18),
            maxTextWidth,

            banner.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: host.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            banner.widthAnchor.constraint(greaterThanOrEqualToConstant: 148),
            banner.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -chromeLift)
        ]

        if let actionButton {
            constraints.append(contentsOf: [
                label.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -4),
                actionButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -8),
                actionButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
            ])
        } else {
            constraints.append(label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -18))
        }

        NSLayoutConstraint.activate(constraints)

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            banner.alpha = 1
            banner.transform = .identity
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak banner] in
            guard let banner = banner else { return }
            UIView.animate(withDuration: 0.22, animations: {
                banner.alpha = 0
                banner.transform = CGAffineTransform(translationX: 0, y: 8)
            }, completion: { _ in
                banner.removeFromSuperview()
                if currentBanner === banner { currentBanner = nil }
            })
        }
    }
}
