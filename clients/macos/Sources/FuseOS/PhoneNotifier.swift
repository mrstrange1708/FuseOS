import AppKit
import FuseOSCore
import UserNotifications

/// Phone notifications, as macOS notifications.
///
/// The island is the banner; this puts each one in Notification Center so it is still
/// there after the island has gone, keyed by the phone's notification key so an update
/// replaces rather than stacks. Clearing one here clears it on the phone.
@MainActor
final class PhoneNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let category = "phone"
    private let center = UNUserNotificationCenter.current()
    /// Called with the key of a notification the user cleared or clicked on this Mac.
    var onUserDismissed: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
        // customDismissAction is what makes a swipe-away reach the delegate at all.
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [], intentIdentifiers: [], options: [.customDismissAction]),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ n: PhoneNotification) {
        let content = UNMutableNotificationContent()
        content.title = n.title.isEmpty ? n.appName : n.title
        content.subtitle = n.title.isEmpty ? "" : n.appName
        content.body = n.text
        content.categoryIdentifier = Self.category
        center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: nil))
    }

    func remove(key: String) {
        center.removeDeliveredNotifications(withIdentifiers: [key])
    }

    // The island already showed it; a banner too would say the same thing twice.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let key = response.notification.request.identifier
        Task { @MainActor in self.onUserDismissed?(key) }
        completionHandler()
    }
}
