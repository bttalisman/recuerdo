import Foundation
import SwiftData

enum VergeCategory: Comparable, Sendable {
    case almostMastered
    case tipOfTongue
    case stillBuilding

    var sortOrder: Int {
        switch self {
        case .stillBuilding: return 0
        case .tipOfTongue: return 1
        case .almostMastered: return 2
        }
    }
}

struct VergeWord: Identifiable {
    let id: String
    let card: FlashCard
    let category: VergeCategory
    let avgAttemptsBeforeCorrect: Double
    let sessionsAnalyzed: Int
}

/// Lightweight result for passing across thread boundaries (no @Model references).
struct VergeAnalysisResult: Sendable {
    let id: String
    let category: VergeCategory
    let avgAttemptsBeforeCorrect: Double
    let sessionsAnalyzed: Int
}

struct VergeAnalyzer {

    /// Run analysis on a background thread using a fresh ModelContext.
    static func analyzeInBackground(
        container: ModelContainer,
        forcedSessionBoundary: Date? = nil
    ) async -> [VergeAnalysisResult] {
        await Task.detached {
            let context = ModelContext(container)
            let cards = (try? context.fetch(FetchDescriptor<FlashCard>())) ?? []
            let reviews = (try? context.fetch(FetchDescriptor<ReviewRecord>())) ?? []
            return analyze(cards: cards, reviews: reviews, forcedSessionBoundary: forcedSessionBoundary)
                .map { VergeAnalysisResult(id: $0.id, category: $0.category, avgAttemptsBeforeCorrect: $0.avgAttemptsBeforeCorrect, sessionsAnalyzed: $0.sessionsAnalyzed) }
        }.value
    }

    /// Minimum total reviews a card must have to be considered.
    private static let minReviews = 3

    /// Maximum gap (seconds) between reviews of the same card to be considered the same session.
    private static let sessionGap: TimeInterval = 30 * 60 // 30 minutes

    /// Number of recent sessions to analyze per card.
    private static let recentSessionCount = 3

    static func analyze(cards: [FlashCard], reviews: [ReviewRecord], forcedSessionBoundary: Date? = nil) -> [VergeWord] {
        // Only consider learning cards with enough reviews
        let candidates = cards.filter { $0.status == "learning" && $0.totalReviews >= minReviews }
        guard !candidates.isEmpty else { return [] }

        // Group reviews by card wordId
        var reviewsByCard: [String: [ReviewRecord]] = [:]
        for review in reviews {
            guard let wordId = review.card?.wordId else { continue }
            reviewsByCard[wordId, default: []].append(review)
        }

        var results: [VergeWord] = []

        for card in candidates {
            guard let cardReviews = reviewsByCard[card.wordId], cardReviews.count >= minReviews else {
                continue
            }

            // Sort reviews chronologically
            let sorted = cardReviews.sorted { $0.reviewDate < $1.reviewDate }

            // Split into sessions
            let sessions = splitIntoSessions(sorted, forcedBoundary: forcedSessionBoundary)
            guard !sessions.isEmpty else { continue }

            // Take the most recent sessions
            let recent = Array(sessions.suffix(recentSessionCount))

            // For each session, count attempts before first correct
            var attemptsPerSession: [Int] = []
            for session in recent {
                let attempts = attemptsBeforeCorrect(session)
                attemptsPerSession.append(attempts)
            }

            guard !attemptsPerSession.isEmpty else { continue }

            let avgAttempts = Double(attemptsPerSession.reduce(0, +)) / Double(attemptsPerSession.count)

            // Classify
            let category = classify(attemptsPerSession: attemptsPerSession, card: card)
            guard let category else { continue }

            results.append(VergeWord(
                id: card.wordId,
                card: card,
                category: category,
                avgAttemptsBeforeCorrect: avgAttempts,
                sessionsAnalyzed: recent.count
            ))
        }

        return results.sorted { a, b in
            if a.category.sortOrder != b.category.sortOrder {
                return a.category.sortOrder < b.category.sortOrder
            }
            return a.avgAttemptsBeforeCorrect < b.avgAttemptsBeforeCorrect
        }
    }

    // MARK: - Helpers

    /// Split a chronologically-sorted array of reviews into sessions.
    /// A new session starts when the gap between consecutive reviews exceeds `sessionGap`.
    private static func splitIntoSessions(_ reviews: [ReviewRecord], forcedBoundary: Date? = nil) -> [[ReviewRecord]] {
        guard let first = reviews.first else { return [] }
        var sessions: [[ReviewRecord]] = [[first]]

        for i in 1..<reviews.count {
            let gap = reviews[i].reviewDate.timeIntervalSince(reviews[i - 1].reviewDate)
            let crossesBoundary = forcedBoundary.map { boundary in
                reviews[i - 1].reviewDate < boundary && reviews[i].reviewDate >= boundary
            } ?? false
            if gap > sessionGap || crossesBoundary {
                sessions.append([reviews[i]])
            } else {
                sessions[sessions.count - 1].append(reviews[i])
            }
        }

        return sessions
    }

    /// How many attempts before the first correct answer in a session.
    /// Returns 0 if the first attempt was correct.
    /// Returns the total session count if no correct answer was given.
    private static func attemptsBeforeCorrect(_ session: [ReviewRecord]) -> Int {
        for (index, review) in session.enumerated() {
            if review.wasCorrect {
                return index // 0 = got it first try, 1 = missed once then got it, etc.
            }
        }
        return session.count // never got it right
    }

    /// Classify a card based on its recent session patterns.
    private static func classify(attemptsPerSession: [Int], card: FlashCard) -> VergeCategory? {
        guard !attemptsPerSession.isEmpty else { return nil }

        let mostRecent = attemptsPerSession.last!

        // Almost Mastered: most recent session(s) were first-try correct,
        // but earlier sessions had misses (showing improvement)
        if attemptsPerSession.count >= 2 {
            let recentCorrectFirstTry = mostRecent == 0
            let hadPreviousMisses = attemptsPerSession.dropLast().contains(where: { $0 > 0 })
            if recentCorrectFirstTry && hadPreviousMisses {
                return .almostMastered
            }
        }

        // If most recent session was first-try correct and we don't have enough
        // history to show improvement, skip this card (it's fine)
        if mostRecent == 0 {
            return nil
        }

        // Tip of Tongue: missed once then got it (1 attempt before correct)
        let avgAttempts = Double(attemptsPerSession.reduce(0, +)) / Double(attemptsPerSession.count)
        if avgAttempts <= 1.5 {
            return .tipOfTongue
        }

        // Still Building: needed 2+ attempts on average
        return .stillBuilding
    }
}
