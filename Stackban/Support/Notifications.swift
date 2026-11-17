import Foundation
import UserNotifications
import os

/// Local notifications for silent capture. Permission is requested lazily, the first time
/// a notification is actually needed (or when the user turns "Notify when added" on).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "com.example.stackban", category: "notifications")
    private var center: UNUserNotificationCenter { .current() }

    override init() {
        super.init()
        center.delegate = self
    }

    /// Returns whether notifications are (now) allowed.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.error("Notification permission request failed: \(error.localizedDescription)")
                return false
            }
        default:
            return false
        }
    }

    func post(title: String, body: String) {
        Task {
            guard await requestPermissionIfNeeded() else {
                logger.notice("Notifications not allowed; dropped: \(title) — \(body)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                logger.error("Posting notification failed: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
