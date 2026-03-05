import Foundation
import SwiftData
import WidgetKit

struct WidgetStatsWriter {

    static func update(container: ModelContainer) {
        let context = ModelContext(container)

        let cardDescriptor = FetchDescriptor<FlashCard>()
        guard let allCards = try? context.fetch(cardDescriptor) else { return }
        let activeCards = allCards.filter { !$0.isTrashed }

        let now = Date()
        let dueCount = activeCards.filter {
            $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= now
        }.count

        let learningCount = activeCards.filter { $0.status == "learning" }.count
        let masteredCount = activeCards.filter { $0.status == "mastered" }.count
        let totalIntroduced = learningCount + masteredCount

        let deckDescriptor = FetchDescriptor<DeckMetadata>()
        let unlockedWordCount = (try? context.fetch(deckDescriptor).first?.unlockedWordCount) ?? 500

        let dayStreak = computeDayStreak(context: context)

        var reviewDescriptor = FetchDescriptor<ReviewRecord>(
            sortBy: [SortDescriptor(\ReviewRecord.reviewDate, order: .reverse)]
        )
        reviewDescriptor.fetchLimit = 1
        let lastStudied = try? context.fetch(reviewDescriptor).first?.reviewDate

        // At-risk: learning cards with low accuracy or broken streaks
        let atRiskCount = activeCards.filter { card in
            guard card.status == "learning", card.totalReviews >= 3 else { return false }
            let accuracy = Double(card.totalCorrect) / Double(card.totalReviews)
            return accuracy < 0.7 || card.currentStreak == 0
        }.count

        let stats = WidgetStats(
            dueCount: dueCount,
            learningCount: learningCount,
            masteredCount: masteredCount,
            totalIntroduced: totalIntroduced,
            unlockedWordCount: unlockedWordCount,
            currentDayStreak: dayStreak,
            lastStudiedDate: lastStudied,
            lastUpdated: now,
            atRiskCount: atRiskCount
        )

        WidgetStats.save(stats)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func computeDayStreak(context: ModelContext) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let descriptor = FetchDescriptor<ReviewRecord>(
            sortBy: [SortDescriptor(\ReviewRecord.reviewDate, order: .reverse)]
        )
        guard let records = try? context.fetch(descriptor), !records.isEmpty else { return 0 }

        var reviewDays = Set<Date>()
        for record in records {
            reviewDays.insert(calendar.startOfDay(for: record.reviewDate))
        }

        var streak = 0
        var checkDate = today

        if reviewDays.contains(today) {
            streak = 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: today) else { return streak }
            checkDate = prev
        } else {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            checkDate = yesterday
            if reviewDays.contains(checkDate) {
                streak = 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return streak }
                checkDate = prev
            } else {
                return 0
            }
        }

        while reviewDays.contains(checkDate) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prev
        }

        return streak
    }
}
