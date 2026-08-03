import UIKit
import UserNotifications

/// Local notifications for finished downloads (banner when backgrounded; tap opens Downloads).
final class DownloadLocalNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DownloadLocalNotifications()

    static let categoryID = "mmbrowser.download.finish"
    static let openActionID = "mmbrowser.download.open"
    static let openDownloadsNotification = Notification.Name("mmbrowser.downloads.openFromNotification")

    private static let requestIDPrefix = "download."

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(
            identifier: Self.openActionID,
            title: "Open",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Prompt only when the user turns the setting on or starts a download.
    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        guard AppSettings.downloadCompletionNotificationsEnabled else {
            completion?(false)
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion?(true) }
            case .denied:
                DispatchQueue.main.async { completion?(false) }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion?(granted) }
                }
            @unknown default:
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    func postFinished(_ item: DownloadItem) {
        guard AppSettings.downloadCompletionNotificationsEnabled else { return }
        guard item.status == .completed || item.status == .failed else { return }

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        content.userInfo = [
            "downloadId": item.id.uuidString,
            "fileName": item.fileName
        ]

        switch item.status {
        case .completed:
            content.title = "Download Complete"
            content.body = item.fileName
        case .failed:
            content.title = "Download Failed"
            let detail = item.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                content.body = "\(item.fileName) · \(detail)"
            } else {
                content.body = item.fileName
            }
        default:
            return
        }

        let id = Self.requestIDPrefix + item.id.uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Foreground: BrowserViewController already shows a toast — skip the banner.
        if UIApplication.shared.applicationState == .active {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        if action == UNNotificationDefaultActionIdentifier || action == Self.openActionID {
            NotificationCenter.default.post(name: Self.openDownloadsNotification, object: nil)
        }
        completionHandler()
    }
}
