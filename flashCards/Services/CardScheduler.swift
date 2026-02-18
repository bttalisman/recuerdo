import Foundation
import SwiftData

struct CardScheduler {
    /// Review session: lapsed cards + due review cards
    static func buildReviewSession(deckId: String, context: ModelContext) -> [FlashCard] {
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

    /// Free new words: return up to `limit` new cards from the unlocked pool, in curated order
    static func buildFreeNewWordsSession(deckId: String, limit: Int, context: ModelContext) -> [FlashCard] {
        guard limit > 0 else { return [] }

        let metaDescriptor = FetchDescriptor<DeckMetadata>(
            predicate: #Predicate { $0.deckId == deckId }
        )
        guard let deckMeta = try? context.fetch(metaDescriptor).first else { return [] }

        let maxIndex = deckMeta.unlockedWordCount
        var descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId && $0.status == "new" && $0.wordIndex < maxIndex
            },
            sortBy: [SortDescriptor(\.wordIndex)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
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

        // Fetch deck metadata for daily limit and unlocked word count
        let metaDescriptor = FetchDescriptor<DeckMetadata>(
            predicate: #Predicate { $0.deckId == deckId }
        )
        guard let deckMeta = try? context.fetch(metaDescriptor).first else { return [] }

        let remaining = max(0, deckMeta.dailyNewCardLimit - introducedTodayCount)
        if remaining == 0 { return [] }

        // Only offer new cards within the unlocked range
        let maxIndex = deckMeta.unlockedWordCount
        var newDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId && $0.status == "new" && $0.wordIndex < maxIndex
            },
            sortBy: [SortDescriptor(\.wordIndex)]
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
