import UserNotifications

/// Local notifications; permission is requested the first time one is needed.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied: return false
        default: return true
        }
    }

    func post(_ title: String, _ body: String) {
        Task {
            guard await requestPermission() else { return }
            let content = UNMutableNotificationContent()
            (content.title, content.body) = (title, body)
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Show banners even while OnIt is the active app.
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
