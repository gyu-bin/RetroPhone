import Foundation
import UserNotifications

nonisolated enum ClockNotificationIDs {
    static let timer = "retrophone.clock.timer"
    static let alarmPrefix = "retrophone.clock.alarm."
    static let alarmCategory = "RETROPHONE_ALARM"
}

/// Notification permission helpers for alarms and the timer.
enum ClockNotifications {
    enum Status { case authorized, denied, notDetermined }

    static func status() async -> Status {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// Requests authorization the first time; returns whether notifications can be delivered.
    static func ensureAuthorized() async -> Bool {
        switch await status() {
        case .authorized: return true
        case .denied: return false
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        }
    }
}

/// Presents RetroPhone's clock notifications while the app is in the foreground (otherwise iOS
/// silently drops them) and plays the in-app alarm sound. Installed only if no other delegate is set.
/// Ideally the app entry point installs it at launch (see report): `ClockNotificationDelegate.shared.install()`.
nonisolated final class ClockNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = ClockNotificationDelegate()

    func install() {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = self }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        if id == ClockNotificationIDs.timer {
            // The timer screen plays its own sound and shows an alert in the foreground.
            await MainActor.run { ClockCountdown.shared.handleDeliveredNotification() }
            return [.list]
        }
        if id.hasPrefix(ClockNotificationIDs.alarmPrefix) {
            await MainActor.run {
                SoundService.shared.play(.alarm)
                ClockAlarmStore.shared.refreshExpired()
            }
            return [.banner, .list, .sound]
        }
        return [.banner, .list, .sound]
    }
}
