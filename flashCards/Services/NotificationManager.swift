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
            scheduleDailyReminder(dayOffset: dayOffset, badgeCount: dueOnDay)
            scheduled += 1
        }
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
