import Foundation
import SwiftData

struct CardBackup: Codable {
    let wordId: String
    let status: String
    let introducedDate: Date?
    let easeFactor: Double
    let interval: Int
    let repetitionCount: Int
    let nextReviewDate: Date?
    let lastReviewDate: Date?
    let totalReviews: Int
    let totalCorrect: Int
    let currentStreak: Int
    let longestStreak: Int
}

struct ReviewBackup: Codable {
    let wordId: String
    let reviewDate: Date
    let quality: Int
    let wasCorrect: Bool
    let previousInterval: Int
    let newInterval: Int
    let previousEaseFactor: Double
    let newEaseFactor: Double
    let studyMode: String
    let responseTimeSeconds: Double
    let cardDirection: String
}

struct SettingsBackup: Codable {
    let dailyNewCardLimit: Int
    let cardDirection: String
    let unlockedWordCount: Int
    let newWordsMode: String?
    let newWordsAccumulationRate: Int?
}

struct ProgressBackup: Codable {
    let backupDate: Date
    let deckId: String
    let cardProgress: [CardBackup]
    let reviewHistory: [ReviewBackup]
    let settings: SettingsBackup
}

struct BackupManager {
    static func createBackup(context: ModelContext) -> Data? {
        let metaDescriptor = FetchDescriptor<DeckMetadata>()
        guard let deck = try? context.fetch(metaDescriptor).first else { return nil }

        let cardDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate { $0.status != "new" }
        )
        let cards = (try? context.fetch(cardDescriptor)) ?? []

        let reviewDescriptor = FetchDescriptor<ReviewRecord>(
            sortBy: [SortDescriptor(\.reviewDate)]
        )
        let reviews = (try? context.fetch(reviewDescriptor)) ?? []

        let cardBackups = cards.map { card in
            CardBackup(
                wordId: card.wordId,
                status: card.status,
                introducedDate: card.introducedDate,
                easeFactor: card.easeFactor,
                interval: card.interval,
                repetitionCount: card.repetitionCount,
                nextReviewDate: card.nextReviewDate,
                lastReviewDate: card.lastReviewDate,
                totalReviews: card.totalReviews,
                totalCorrect: card.totalCorrect,
                currentStreak: card.currentStreak,
                longestStreak: card.longestStreak
            )
        }

        let reviewBackups = reviews.map { review in
            ReviewBackup(
                wordId: review.card?.wordId ?? "",
                reviewDate: review.reviewDate,
                quality: review.quality,
                wasCorrect: review.wasCorrect,
                previousInterval: review.previousInterval,
                newInterval: review.newInterval,
                previousEaseFactor: review.previousEaseFactor,
                newEaseFactor: review.newEaseFactor,
                studyMode: review.studyMode,
                responseTimeSeconds: review.responseTimeSeconds,
                cardDirection: review.cardDirection
            )
        }

        let settings = SettingsBackup(
            dailyNewCardLimit: deck.dailyNewCardLimit,
            cardDirection: deck.cardDirection,
            unlockedWordCount: deck.unlockedWordCount,
            newWordsMode: deck.newWordsMode,
            newWordsAccumulationRate: deck.newWordsAccumulationRate
        )

        let backup = ProgressBackup(
            backupDate: Date(),
            deckId: deck.deckId,
            cardProgress: cardBackups,
            reviewHistory: reviewBackups,
            settings: settings
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(backup)
    }

    static func restoreBackup(data: Data, context: ModelContext) -> (cards: Int, reviews: Int)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(ProgressBackup.self, from: data) else { return nil }

        // Restore card progress
        var restoredCards = 0
        for cardBackup in backup.cardProgress {
            let wordId = cardBackup.wordId
            let descriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate { $0.wordId == wordId }
            )
            guard let card = try? context.fetch(descriptor).first else { continue }

            card.status = cardBackup.status
            card.introducedDate = cardBackup.introducedDate
            card.easeFactor = cardBackup.easeFactor
            card.interval = cardBackup.interval
            card.repetitionCount = cardBackup.repetitionCount
            card.nextReviewDate = cardBackup.nextReviewDate
            card.lastReviewDate = cardBackup.lastReviewDate
            card.totalReviews = cardBackup.totalReviews
            card.totalCorrect = cardBackup.totalCorrect
            card.currentStreak = cardBackup.currentStreak
            card.longestStreak = cardBackup.longestStreak
            restoredCards += 1
        }

        // Clear existing reviews and restore from backup
        let existingReviews = FetchDescriptor<ReviewRecord>()
        if let reviews = try? context.fetch(existingReviews) {
            for review in reviews {
                context.delete(review)
            }
        }

        var restoredReviews = 0
        for reviewBackup in backup.reviewHistory {
            let wordId = reviewBackup.wordId
            let descriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate { $0.wordId == wordId }
            )
            guard let card = try? context.fetch(descriptor).first else { continue }

            let record = ReviewRecord(
                card: card,
                reviewDate: reviewBackup.reviewDate,
                quality: reviewBackup.quality,
                wasCorrect: reviewBackup.wasCorrect,
                previousInterval: reviewBackup.previousInterval,
                newInterval: reviewBackup.newInterval,
                previousEaseFactor: reviewBackup.previousEaseFactor,
                newEaseFactor: reviewBackup.newEaseFactor,
                studyMode: reviewBackup.studyMode,
                responseTimeSeconds: reviewBackup.responseTimeSeconds,
                cardDirection: reviewBackup.cardDirection
            )
            context.insert(record)
            restoredReviews += 1
        }

        // Restore settings
        let metaDescriptor = FetchDescriptor<DeckMetadata>()
        if let deck = try? context.fetch(metaDescriptor).first {
            deck.dailyNewCardLimit = backup.settings.dailyNewCardLimit
            deck.cardDirection = backup.settings.cardDirection
            deck.unlockedWordCount = backup.settings.unlockedWordCount
            deck.newWordsMode = backup.settings.newWordsMode ?? "free"
            deck.newWordsAccumulationRate = backup.settings.newWordsAccumulationRate ?? 2
        }

        try? context.save()
        return (cards: restoredCards, reviews: restoredReviews)
    }

    static func backupFileURL(context: ModelContext) -> URL? {
        guard let data = createBackup(context: context) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "flashcards-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }
}
