import AppKit
import ReviewQueueCore
import UserNotifications

/// macOS notifications: one per new reason a PR needs you. Clicking one opens the PR.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Bundles only: `UNUserNotificationCenter` crashes in a bare executable (`swift run`).
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// At most five at a time, so a big change does not flood Notification Center.
    func announce(_ prs: [PR]) {
        guard let center else { return }
        for pr in prs.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = pr.isMine ? "Your PR · \(pr.label)" : "\(pr.label) · \(pr.author)"
            c.body = pr.title
            c.userInfo = ["url": pr.url.absoluteString]
            center.add(UNNotificationRequest(identifier: pr.key, content: c, trigger: nil))
        }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let s = r.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        }
        done()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
