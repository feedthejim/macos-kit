import Foundation
import UserNotifications

public enum NotificationService: Sendable {
    public static func send(
        title: String,
        body: String,
        subtitle: String? = nil,
        soundName: String? = nil
    ) async throws {
        let center = UNUserNotificationCenter.current()

        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw MacKitError.permissionDenied(.notifications)
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle {
            content.subtitle = subtitle
        }
        if let soundName {
            content.sound = soundName == "default"
                ? .default
                : UNNotificationSound(named: UNNotificationSoundName(soundName))
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        try await center.add(request)
    }
}
