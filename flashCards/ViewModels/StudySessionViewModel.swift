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
    var cardDirection: String = "source_first" // "source_first", "target_first", "mixed"
    private var mixedDirections: [String: Bool] = [:]

    var effectiveShowTargetFirst: Bool {
        guard let card = currentCard else { return cardDirection == "target_first" }
        if cardDirection == "mixed" {
            return mixedDirections[card.wordId] ?? false
        }
        return cardDirection == "target_first"
    }

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

    func loadLearnSession(deckId: String, scheduled: Bool, accumulatedCount: Int, context: ModelContext) {
        mode = .learn

        // Study tab always shows English -> Spanish
        cardDirection = "source_first"

        let metaDescriptor = FetchDescriptor<DeckMetadata>(
            predicate: #Predicate { $0.deckId == deckId }
        )

        let newCards: [FlashCard]
        if scheduled {
            newCards = CardScheduler.buildFreeNewWordsSession(deckId: deckId, limit: accumulatedCount, context: context)
            // Drain accumulation: reset the drain date
            if let deckMeta = try? context.fetch(metaDescriptor).first {
                deckMeta.lastNewWordsDrainDate = Date()
                try? context.save()
            }
        } else {
            newCards = CardScheduler.buildFreeNewWordsSession(deckId: deckId, limit: accumulatedCount, context: context)
        }

        wordsLearned = 0
        sessionCards = newCards.shuffled()
        totalSessionCards = sessionCards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = newCards.isEmpty
        cardShownAt = Date()
        generateMixedDirections()

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

    func endLearnSession(context: ModelContext) {
        isSessionComplete = true
        NotificationManager.shared.rescheduleNotifications(context: context)
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

    func loadCustomReviewSession(cards: [FlashCard], cardDirection: String) {
        self.mode = .review
        self.cardDirection = cardDirection
        sessionCards = cards
        totalSessionCards = cards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = cards.isEmpty
        cardShownAt = Date()
        generateMixedDirections()
    }

    func loadReviewSession(deckId: String, cardDirection: String, context: ModelContext) {
        self.mode = .review
        self.cardDirection = cardDirection
        let cards = CardScheduler.buildReviewSession(deckId: deckId, context: context)

        sessionCards = cards
        totalSessionCards = cards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = cards.isEmpty
        cardShownAt = Date()
        generateMixedDirections()
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
            studyMode: "review",
            responseTimeSeconds: responseTime,
            cardDirection: effectiveShowTargetFirst ? "target_to_source" : "source_to_target"
        )
        context.insert(record)

        totalReviewed += 1
        if wasCorrect { correctCount += 1 }

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
            try? context.save()
            let container = context.container
            DispatchQueue.global(qos: .utility).async {
                let bgContext = ModelContext(container)
                NotificationManager.shared.rescheduleNotifications(context: bgContext)
            }
        }
    }

    private func generateMixedDirections() {
        mixedDirections = [:]
        if cardDirection == "mixed" {
            for card in sessionCards {
                mixedDirections[card.wordId] = Bool.random()
            }
        }
    }
}
