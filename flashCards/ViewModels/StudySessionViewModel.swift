import Foundation
import SwiftData
import Observation

enum StudyMode {
    case learn
    case review
}

@Observable
class StudySessionViewModel: Identifiable {
    let id = UUID()
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
    var flipResponseTime: Double? = nil
    var cardDirection: String = "source_first" // "source_first", "target_first", "mixed"
    var isCategorySession: Bool = false
    var autoStartHandsFree: Bool = false
    private var mixedDirections: [String: Bool] = [:]
    private var pendingRecords: [ReviewRecord] = []
    var sessionRecordsFlushed: Bool = false
    var pendingRecordCount: Int { pendingRecords.count }
    var masteredCount: Int = 0

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

        let newCards = CardScheduler.buildFreeNewWordsSession(deckId: deckId, limit: accumulatedCount, context: context)


        wordsLearned = 0
        sessionCards = newCards.shuffled()
        totalSessionCards = sessionCards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = newCards.isEmpty
        cardShownAt = Date()
        flipResponseTime = nil
        generateMixedDirections()

        introduceCurrentCard(context: context)
    }

    func advanceToNextCard(context: ModelContext) {
        let previousCard = currentCard
        isFlipped = false
        currentCardIndex += 1
        if currentCardIndex >= sessionCards.count {
            sessionCards.shuffle()
            currentCardIndex = 0
        }
        cardShownAt = Date()
        flipResponseTime = nil

        // Defer @Model mutations so the card transition renders first
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let card = previousCard, card.status == "new" {
                card.introducedDate = Date()
                card.status = "learning"
                card.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                self.wordsLearned += 1
            }
        }
    }

    func endLearnSession(context: ModelContext) {
        isSessionComplete = true
        NotificationManager.shared.rescheduleNotifications(context: context)
        let container = context.container
        DispatchQueue.global(qos: .utility).async {
            WidgetStatsWriter.update(container: container)
        }
    }

    private func introduceCurrentCard(context: ModelContext) {
        guard let card = currentCard, card.status == "new" else { return }
        card.introducedDate = Date()
        card.status = "learning"
        // First review tomorrow — don't make cards immediately due
        card.nextReviewDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        wordsLearned += 1
    }

    // MARK: - Category Learn Mode

    func loadCategoryLearnSession(cards: [FlashCard], context: ModelContext) {
        mode = .learn
        isCategorySession = true
        cardDirection = "source_first"
        wordsLearned = 0
        sessionCards = cards.shuffled()
        totalSessionCards = sessionCards.count
        currentCardIndex = 0
        isFlipped = false
        isSessionComplete = cards.isEmpty
        cardShownAt = Date()
        flipResponseTime = nil
        generateMixedDirections()
        // Don't introduce until user flips the card
    }

    /// Call when the user flips a category card to mark it as learning.
    func introduceOnFlipIfNeeded(context: ModelContext) {
        guard isCategorySession else { return }
        introduceCurrentCard(context: context)
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
        flipResponseTime = nil
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
        flipResponseTime = nil
        generateMixedDirections()
    }

    func submitRating(_ quality: Int, recallModality: String = "visual", context: ModelContext) {
        guard let card = currentCard else { return }

        // Capture everything we need BEFORE advancing the card
        let previousInterval = card.interval
        let previousEF = card.easeFactor
        let result = SpacedRepetitionEngine.processReview(
            currentInterval: card.interval,
            currentEaseFactor: card.easeFactor,
            currentRepetitionCount: card.repetitionCount,
            currentStatus: card.status,
            quality: quality,
            introducedDate: card.introducedDate
        )
        let wasCorrect = quality >= 3
        let responseTime = flipResponseTime ?? Date().timeIntervalSince(cardShownAt)
        let direction = effectiveShowTargetFirst ? "target_to_source" : "source_to_target"

        // --- Phase 1: Advance the UI immediately (no @Model mutations) ---
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
        flipResponseTime = nil

        let sessionDone = sessionCards.isEmpty
        if sessionDone {
            isSessionComplete = true
        }

        // --- Phase 2: Defer @Model mutations to after the render ---
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Apply spaced repetition updates to the card
            card.interval = result.newInterval
            card.easeFactor = result.newEaseFactor
            card.repetitionCount = result.newRepetitionCount
            card.status = result.newStatus
            if result.newStatus == "mastered" && card.masteredDate == nil {
                card.masteredDate = Date()
                self.masteredCount += 1
            } else if result.newStatus != "mastered" {
                card.masteredDate = nil
            }
            card.lastReviewDate = Date()
            card.nextReviewDate = Calendar.current.date(
                byAdding: .day, value: max(result.newInterval, 1), to: Date()
            )
            card.totalReviews += 1
            if wasCorrect {
                card.totalCorrect += 1
                card.currentStreak += 1
                card.longestStreak = max(card.longestStreak, card.currentStreak)
            } else {
                card.currentStreak = 0
            }

            // Create review record
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
                cardDirection: direction,
                recallModality: recallModality
            )
            self.pendingRecords.append(record)

            if sessionDone {
                self.flushPendingRecords(context: context)
                // Yield a frame so the completion screen renders before the save blocks main thread
                DispatchQueue.main.async {
                    try? context.save()
                    self.sessionRecordsFlushed = true
                    let container = context.container
                    DispatchQueue.global(qos: .utility).async {
                        let bgContext = ModelContext(container)
                        NotificationManager.shared.rescheduleNotifications(context: bgContext)
                        WidgetStatsWriter.update(container: container)
                    }
                }
            }
        }
    }

    /// Insert all pending ReviewRecords into the context at once.
    func flushPendingRecords(context: ModelContext) {
        for record in pendingRecords {
            context.insert(record)
        }
        pendingRecords.removeAll()
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
