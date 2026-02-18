import Foundation
import UserNotifications
import SwiftData

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

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
        content.title = "Daily Flashcards"
        content.body = "This is a test notification. Your daily words are waiting!"
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

    func rescheduleNotifications(context: ModelContext) {
        center.removeAllPendingNotificationRequests()
        updateBadgeCount(context: context)

        let cardDescriptor = FetchDescriptor<FlashCard>()
        let allCards = (try? context.fetch(cardDescriptor)) ?? []

        var scheduled = 0
        let maxNotifications = 60

        // Daily study reminders for next 14 days
        for dayOffset in 0..<14 {
            guard scheduled < maxNotifications else { break }
            let dueOnDay = estimatedDueCount(cards: allCards, daysFromNow: dayOffset)
            // Skip today if it's already past 9 AM — schedule for tomorrow onwards
            if dayOffset == 0 {
                let hour = Calendar.current.component(.hour, from: Date())
                if hour >= 9 { continue }
            }
            scheduleDailyReminder(dayOffset: dayOffset, badgeCount: dueOnDay)
            scheduled += 1
        }
        print("[Notifications] Scheduled \(scheduled) reminders")
    }

    private func estimatedDueCount(cards: [FlashCard], daysFromNow: Int) -> Int {
        let targetDate = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        components.hour = 9
        let atTime = Calendar.current.date(from: components) ?? targetDate
        return cards.filter {
            $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= atTime
        }.count
    }

    private func scheduleDailyReminder(dayOffset: Int, badgeCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Daily Flashcards"
        content.body = badgeCount > 0
            ? "\(badgeCount) words due for review. Your daily words are waiting!"
            : "Your daily words are waiting!"
        content.sound = .default
        content.badge = badgeCount as NSNumber

        guard let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) else { return }
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "daily_\(dayOffset)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
