import Foundation
import SwiftData
import Observation

enum StudyMode {
    case learn
    case review
}

@Observable
class StudySessionViewModel {
    var mode: StudyMode = .learn
    var currentCardIndex: Int = 0
    var sessionCards: [FlashCard] = []
    var isFlipped: Bool = false
    var isSessionComplete: Bool = false
    var totalSessionCards: Int = 0
    var totalReviewed: Int = 0
    var correctCount: Int = 0
    var wordsLearned: Int = 0
    var cardShownAt: Date = Date()
    var isScheduledReview: Bool = false
    var showTargetFirst: Bool = false

    var currentCard: FlashCard? {
        guard currentCardIndex < sessionCards.count else { return nil }
        return sessionCards[currentCardIndex]
    }

    var sessionProgress: String {
        if mode == .review {
            return "\(sessionCards.count) remaining"
        }
        if totalSessionCards == 0 { return "No cards" }
        return "Card \(min(currentCardIndex + 1, totalSessionCards)) of \(totalSessionCards)"
    }

    var accuracy: Double {
        totalReviewed > 0 ? Double(correctCount) / Double(totalReviewed) : 0
    }

    var isReviewMode: Bool {
        mode == .review
    }

    // MARK: - Learn Mode

    func loadLearnSession(deckId: String, context: ModelContext) {
        mode = .learn
        let newCards = CardScheduler.getNewCardsForToday(deckId: deckId, context: context)

        wordsLearned = 0
        sessionCards = newCards.shuffled()
        totalSessionCards = sessionCards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = newCards.isEmpty
        cardShownAt = Date()

        introduceCurrentCard(context: context)
    }

    func advanceToNextCard(context: ModelContext) {
        isFlipped = false
        currentCardIndex += 1
        if currentCardIndex >= sessionCards.count {
            sessionCards.shuffle()
            currentCardIndex = 0
        }
        cardShownAt = Date()
        introduceCurrentCard(context: context)
    }

    func endLearnSession() {
        isSessionComplete = true
    }

    private func introduceCurrentCard(context: ModelContext) {
        guard let card = currentCard, card.status == "new" else { return }
        card.introducedDate = Date()
        card.status = "learning"
        card.nextReviewDate = Date()
        wordsLearned += 1
        try? context.save()
    }

    // MARK: - Review Mode

    func loadCustomReviewSession(cards: [FlashCard], showTargetFirst: Bool) {
        self.mode = .review
        self.isScheduledReview = false
        self.showTargetFirst = showTargetFirst
        sessionCards = cards
        totalSessionCards = cards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = cards.isEmpty
        cardShownAt = Date()
    }

    func loadReviewSession(deckId: String, scheduled: Bool, accumulatedCount: Int, showTargetFirst: Bool, context: ModelContext) {
        self.mode = .review
        self.isScheduledReview = scheduled
        self.showTargetFirst = showTargetFirst
        let cards: [FlashCard]
        if scheduled {
            cards = CardScheduler.buildScheduledReviewSession(deckId: deckId, context: context)
        } else {
            cards = CardScheduler.buildFreeReviewSession(deckId: deckId, limit: accumulatedCount, context: context)
            // Drain accumulation: reset the drain date
            let metaDescriptor = FetchDescriptor<DeckMetadata>()
            if let deckMeta = try? context.fetch(metaDescriptor).first {
                deckMeta.lastReviewDrainDate = Date()
                try? context.save()
            }
        }

        sessionCards = cards
        totalSessionCards = cards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = cards.isEmpty
        cardShownAt = Date()
    }

    func submitRating(_ quality: Int, context: ModelContext) {
        guard let card = currentCard else { return }

        let previousInterval = card.interval
        let previousEF = card.easeFactor

        let result = SpacedRepetitionEngine.processReview(
            currentInterval: card.interval,
            currentEaseFactor: card.easeFactor,
            currentRepetitionCount: card.repetitionCount,
            currentStatus: card.status,
            quality: quality
        )

        card.interval = result.newInterval
        card.easeFactor = result.newEaseFactor
        card.repetitionCount = result.newRepetitionCount
        card.status = result.newStatus
        card.lastReviewDate = Date()
        card.nextReviewDate = Calendar.current.date(
            byAdding: .day, value: max(result.newInterval, 1), to: Date()
        )
        card.totalReviews += 1

        let wasCorrect = quality >= 3
        if wasCorrect {
            card.totalCorrect += 1
            card.currentStreak += 1
            card.longestStreak = max(card.longestStreak, card.currentStreak)
        } else {
            card.currentStreak = 0
        }

        let responseTime = Date().timeIntervalSince(cardShownAt)
        let record = ReviewRecord(
            card: card,
            reviewDate: Date(),
            quality: quality,
            wasCorrect: wasCorrect,
            previousInterval: previousInterval,
            newInterval: result.newInterval,
            previousEaseFactor: previousEF,
            newEaseFactor: result.newEaseFactor,
            studyMode: isScheduledReview ? "scheduled_review" : "free_review",
            responseTimeSeconds: responseTime,
            cardDirection: showTargetFirst ? "target_to_source" : "source_to_target"
        )
        context.insert(record)

        totalReviewed += 1
        if wasCorrect { correctCount += 1 }

        try? context.save()

        if wasCorrect {
            sessionCards.remove(at: currentCardIndex)
            if !sessionCards.isEmpty && currentCardIndex >= sessionCards.count {
                currentCardIndex = 0
            }
        } else {
            currentCardIndex += 1
            if currentCardIndex >= sessionCards.count {
                currentCardIndex = 0
            }
        }
        isFlipped = false
        cardShownAt = Date()

        if sessionCards.isEmpty {
            isSessionComplete = true

            // Record review completion time if in scheduled mode
            let metaDescriptor = FetchDescriptor<DeckMetadata>()
            if let deckMeta = try? context.fetch(metaDescriptor).first,
               deckMeta.reviewMode == "scheduled" {
                deckMeta.lastScheduledReviewDate = Date()
                try? context.save()
            }

            NotificationManager.shared.rescheduleNotifications(context: context)
        }
    }
}
