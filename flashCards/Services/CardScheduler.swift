import Foundation
import SwiftData

struct CardScheduler {
    /// Free review session: picks `limit` learned words, semi-randomly ordered with recency bias
    static func buildFreeReviewSession(deckId: String, limit: Int, context: ModelContext) -> [FlashCard] {
        let descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId && $0.status != "new"
            }
        )
        guard let cards = try? context.fetch(descriptor), !cards.isEmpty else { return [] }

        // Sort with recency bias: recently introduced words toward the front,
        // with randomness so the order isn't identical every time.
        let now = Date()
        let sorted = cards.shuffled().sorted { a, b in
            let aDays = (a.introducedDate ?? now).timeIntervalSince(now) / -86400
            let bDays = (b.introducedDate ?? now).timeIntervalSince(now) / -86400
            // Add jitter: ±7 days of randomness so it's not a strict sort
            let aScore = aDays + Double.random(in: -7...7)
            let bScore = bDays + Double.random(in: -7...7)
            return aScore < bScore // lower score = more recent → appears first
        }
        let capped = min(limit, sorted.count)
        return Array(sorted.prefix(capped))
    }

    /// Scheduled review session: lapsed cards + due review cards (no new cards)
    static func buildScheduledReviewSession(deckId: String, context: ModelContext) -> [FlashCard] {
        let now = Date()
        var session: [FlashCard] = []

        // 1. Failed/lapsed cards (interval = 0, due now)
        let lapsedDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId &&
                $0.status == "learning" &&
                $0.interval == 0 &&
                $0.introducedDate != nil
            },
            sortBy: [SortDescriptor(\.lastReviewDate)]
        )
        if let lapsed = try? context.fetch(lapsedDescriptor) {
            session.append(contentsOf: lapsed)
        }

        // 2. Due review cards (nextReviewDate <= now)
        let dueDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId &&
                $0.status != "new" &&
                $0.interval > 0 &&
                $0.nextReviewDate != nil &&
                $0.nextReviewDate! <= now
            },
            sortBy: [SortDescriptor(\.nextReviewDate)]
        )
        if let dueCards = try? context.fetch(dueDescriptor) {
            let existingIds = Set(session.map(\.wordId))
            let filtered = dueCards.filter { !existingIds.contains($0.wordId) }
            session.append(contentsOf: filtered.prefix(20))
        }

        return session
    }

    static func getNewCardsForToday(deckId: String, context: ModelContext) -> [FlashCard] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        // Count how many cards were introduced today
        let introducedDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId &&
                $0.introducedDate != nil &&
                $0.introducedDate! >= startOfToday
            }
        )
        let introducedTodayCount = (try? context.fetchCount(introducedDescriptor)) ?? 0

        // Fetch deck metadata for daily limit
        let metaDescriptor = FetchDescriptor<DeckMetadata>(
            predicate: #Predicate { $0.deckId == deckId }
        )
        guard let deckMeta = try? context.fetch(metaDescriptor).first else { return [] }

        let remaining = max(0, deckMeta.dailyNewCardLimit - introducedTodayCount)
        if remaining == 0 { return [] }

        var newDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId && $0.status == "new"
            },
            sortBy: [SortDescriptor(\.intrinsicDifficulty)]
        )
        newDescriptor.fetchLimit = remaining

        return (try? context.fetch(newDescriptor)) ?? []
    }

    static func getDueCardCount(deckId: String, context: ModelContext, withinDays days: Int) -> [Int: Int] {
        var result: [Int: Int] = [:]
        let calendar = Calendar.current

        for dayOffset in 0..<days {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: Date().startOfDay),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let descriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate {
                    $0.deckId == deckId &&
                    $0.nextReviewDate != nil &&
                    $0.nextReviewDate! >= dayStart &&
                    $0.nextReviewDate! < dayEnd
                }
            )
            result[dayOffset] = (try? context.fetchCount(descriptor)) ?? 0
        }

        return result
    }
}
