import Foundation
import UserNotifications
import SwiftData

class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func rescheduleNotifications(context: ModelContext) {
        center.removeAllPendingNotificationRequests()

        let metaDescriptor = FetchDescriptor<DeckMetadata>()
        guard let deck = try? context.fetch(metaDescriptor).first else { return }

        var scheduled = 0
        let maxNotifications = 60

        // 1. Daily study reminders for next 14 days
        for dayOffset in 0..<14 {
            guard scheduled < maxNotifications else { break }
            scheduleDailyReminder(dayOffset: dayOffset)
            scheduled += 1
        }

        // 2. Scheduled review alerts at the user-configured interval
        let intervalMinutes = max(30, deck.scheduledReviewIntervalMinutes)
        let intervalSeconds = Double(intervalMinutes) * 60
        let startFrom = deck.lastScheduledReviewDate ?? Date()

        // Schedule alerts for the next 7 days
        var nextAlert = startFrom.addingTimeInterval(intervalSeconds)
        let sevenDaysOut = Date().addingTimeInterval(7 * 24 * 3600)
        var alertIndex = 0

        // Skip past alerts that are already in the past
        while nextAlert < Date() {
            nextAlert = nextAlert.addingTimeInterval(intervalSeconds)
        }

        while nextAlert < sevenDaysOut && scheduled < maxNotifications {
            scheduleReviewAlert(date: nextAlert, identifier: "scheduled_\(alertIndex)")
            scheduled += 1
            alertIndex += 1
            nextAlert = nextAlert.addingTimeInterval(intervalSeconds)
        }
    }

    private func scheduleDailyReminder(dayOffset: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Daily Flashcards"
        content.body = "Your daily words are waiting!"
        content.sound = .default

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

    private func scheduleReviewAlert(date: Date, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Review"
        content.body = "Your scheduled review is ready. Keep your memory sharp!"
        content.sound = .default

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
