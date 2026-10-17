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

        let isLight = ThemeManager.shared.current.isLight
        // Invert against the page chrome so the toast always pops.
        let fill = isLight ? UIColor(white: 0.12, alpha: 0.96) : UIColor(white: 0.97, alpha: 0.98)
        let text = isLight ? UIColor.white : UIColor(white: 0.08, alpha: 1)

        let banner = UIView()
        banner.backgroundColor = fill
        banner.layer.cornerRadius = 14
        banner.clipsToBounds = false
        banner.layer.shadowColor = UIColor.black.cgColor
        banner.layer.shadowOpacity = isLight ? 0.22 : 0.45
        banner.layer.shadowRadius = 14
        banner.layer.shadowOffset = CGSize(width: 0, height: 6)
        banner.alpha = 0
        banner.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        banner.translatesAutoresizingMaskIntoConstraints = false

        let accent = UIView()
        accent.backgroundColor = BrowserTheme.chromeBlue
        accent.layer.cornerRadius = 2
        accent.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = text
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textAlignment = actionTitle == nil ? .center : .left
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        banner.addSubview(accent)
        banner.addSubview(label)

        var actionButton: UIButton?
        if let actionTitle, let action {
            var config = UIButton.Configuration.plain()
            config.title = actionTitle
            config.baseForegroundColor = BrowserTheme.chromeBlue
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
        let chromeLift = BrowserTheme.chromeHeight + 16

        var constraints: [NSLayoutConstraint] = [
            accent.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 10),
            accent.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            accent.widthAnchor.constraint(equalToConstant: 4),
            accent.heightAnchor.constraint(equalToConstant: 22),

            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 14),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -14),
            label.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 12),

            banner.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            banner.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: host.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: host.safeAreaLayoutGuide.trailingAnchor, constant: -28),
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

        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.6, options: [.curveEaseOut]) {
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
