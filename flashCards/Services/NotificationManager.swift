import Foundation
import UserNotifications
import SwiftData

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    /// Daytime check-point hours when we may send a notification
    private let checkHours = [9, 13, 18]

    private override init() {
        super.init()
        center.delegate = self
    }

    // Show notifications even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("[Notifications] Authorization error: \(error)")
            }
            print("[Notifications] Authorization granted: \(granted)")
        }
    }

    func checkStatus(completion: @escaping (String) -> Void) {
        center.getNotificationSettings { settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized: status = "Authorized"
            case .denied: status = "Denied"
            case .provisional: status = "Provisional"
            case .notDetermined: status = "Not Determined"
            case .ephemeral: status = "Ephemeral"
            @unknown default: status = "Unknown"
            }
            self.center.getPendingNotificationRequests { requests in
                DispatchQueue.main.async {
                    completion("\(status) — \(requests.count) pending")
                }
            }
        }
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Recuerdo"
        content.body = "This is a test notification. Your words are waiting!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: "test_\(UUID())", content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                print("[Notifications] Test notification error: \(error)")
            } else {
                print("[Notifications] Test notification scheduled in 3 seconds")
            }
        }
    }

    func updateBadgeCount(context: ModelContext) {
        let now = Date()
        let descriptor = FetchDescriptor<FlashCard>()
        let cards = (try? context.fetch(descriptor)) ?? []
        let dueCount = cards.filter {
            $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= now
        }.count
        center.setBadgeCount(dueCount)
    }

    /// Remove all pending notifications (used when user disables notifications).
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.setBadgeCount(0)
        print("[Notifications] Cancelled all notifications")
    }

    /// Schedule review-due notifications at daytime check points (9 AM, 1 PM, 6 PM)
    /// for the next 14 days. Only schedules a notification when cards are due.
    func rescheduleNotifications(context: ModelContext) {
        center.removeAllPendingNotificationRequests()
        updateBadgeCount(context: context)

        // Respect user opt-out
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            print("[Notifications] Disabled by user — skipping schedule")
            return
        }

        let cardDescriptor = FetchDescriptor<FlashCard>()
        let allCards = (try? context.fetch(cardDescriptor)) ?? []

        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        var scheduled = 0
        let maxNotifications = 60

        for dayOffset in 0..<14 {
            guard scheduled < maxNotifications else { break }

            guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

            for hour in checkHours {
                guard scheduled < maxNotifications else { break }

                // Skip check points that have already passed today
                if dayOffset == 0 && hour <= currentHour { continue }

                let dueCount = estimatedDueCount(cards: allCards, onDay: targetDay, atHour: hour)
                guard dueCount > 0 else { continue }

                scheduleReminder(day: targetDay, hour: hour, dueCount: dueCount, identifier: "review_d\(dayOffset)_h\(hour)")
                scheduled += 1
            }
        }
        print("[Notifications] Scheduled \(scheduled) reminders across \(checkHours.count) daily check points")
    }

    private func estimatedDueCount(cards: [FlashCard], onDay day: Date, atHour hour: Int) -> Int {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = 0
        guard let atTime = Calendar.current.date(from: components) else { return 0 }
        return cards.filter {
            $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= atTime
        }.count
    }

    private func scheduleReminder(day: Date, hour: Int, dueCount: Int, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = "Recuerdo"
        if dueCount == 1 {
            content.body = "1 word is ready for review."
        } else {
            content.body = "\(dueCount) words are ready for review."
        }
        content.sound = .default
        content.badge = dueCount as NSNumber

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
        dateComponents.hour = hour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}
