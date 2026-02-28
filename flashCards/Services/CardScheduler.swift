import Foundation
import SwiftData

struct CardScheduler {
    /// Review session: all non-new cards that are due now, capped for session size.
    /// Uses in-memory filtering to match the Study tab's due count exactly.
    static func buildReviewSession(deckId: String, context: ModelContext) -> [FlashCard] {
        let now = Date()
        let descriptor = FetchDescriptor<FlashCard>()
        guard let allCards = try? context.fetch(descriptor) else { return [] }

        var due = allCards.filter {
            $0.deckId == deckId &&
            !$0.isTrashed &&
            $0.status != "new" &&
            $0.nextReviewDate != nil &&
            $0.nextReviewDate! <= now
        }

        // Also pick up lapsed cards that lost their nextReviewDate
        let lapsed = allCards.filter {
            $0.deckId == deckId &&
            !$0.isTrashed &&
            $0.status == "learning" &&
            $0.interval == 0 &&
            $0.nextReviewDate == nil &&
            $0.introducedDate != nil
        }
        let dueIds = Set(due.map(\.wordId))
        due.append(contentsOf: lapsed.filter { !dueIds.contains($0.wordId) })

        // Sort: lapsed first, then by next review date
        due.sort { a, b in
            let aLapsed = a.interval == 0
            let bLapsed = b.interval == 0
            if aLapsed != bLapsed { return aLapsed }
            return (a.nextReviewDate ?? .distantPast) < (b.nextReviewDate ?? .distantPast)
        }

        // Cap at 30 per session
        if due.count > 30 {
            due = Array(due.prefix(30))
        }
        return due
    }

    /// Free new words: return up to `limit` new cards from the unlocked pool.
    /// Silently prioritises curated starter words for new users before falling back to frequency order.
    static func buildFreeNewWordsSession(deckId: String, limit: Int, context: ModelContext) -> [FlashCard] {
        guard limit > 0 else { return [] }

        let metaDescriptor = FetchDescriptor<DeckMetadata>(
            predicate: #Predicate { $0.deckId == deckId }
        )
        guard let deckMeta = try? context.fetch(metaDescriptor).first else { return [] }

        // If starter list hasn't been completed, serve curated words first
        if !deckMeta.hasCompletedStarterList {
            let newDescriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate { $0.deckId == deckId && $0.status == "new" && $0.isTrashed != true }
            )
            let allNew = (try? context.fetch(newDescriptor)) ?? []
            let cardMap = Dictionary(uniqueKeysWithValues: allNew.map { ($0.wordId, $0) })

            var starterCards: [FlashCard] = []
            for id in StarterWords.wordIds {
                guard let card = cardMap[id] else { continue }
                starterCards.append(card)
                if starterCards.count >= limit { break }
            }

            if !starterCards.isEmpty { return starterCards }

            // All starter words learned — mark complete, fall through to normal flow
            deckMeta.hasCompletedStarterList = true
            try? context.save()
        }

        let maxIndex = deckMeta.unlockedWordCount
        var descriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId && $0.status == "new" && $0.wordIndex < maxIndex && $0.isTrashed != true
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
                $0.isTrashed != true &&
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

        // Prioritise curated starter words for new users
        if !deckMeta.hasCompletedStarterList {
            let newDescriptor = FetchDescriptor<FlashCard>(
                predicate: #Predicate { $0.deckId == deckId && $0.status == "new" && $0.isTrashed != true }
            )
            let allNew = (try? context.fetch(newDescriptor)) ?? []
            let cardMap = Dictionary(uniqueKeysWithValues: allNew.map { ($0.wordId, $0) })

            var starterCards: [FlashCard] = []
            for id in StarterWords.wordIds {
                guard let card = cardMap[id] else { continue }
                starterCards.append(card)
                if starterCards.count >= remaining { break }
            }

            if !starterCards.isEmpty { return starterCards }

            deckMeta.hasCompletedStarterList = true
            try? context.save()
        }

        // Only offer new cards within the unlocked range
        let maxIndex = deckMeta.unlockedWordCount
        var newDescriptor = FetchDescriptor<FlashCard>(
            predicate: #Predicate {
                $0.deckId == deckId && $0.status == "new" && $0.wordIndex < maxIndex && $0.isTrashed != true
            },
            sortBy: [SortDescriptor(\.wordIndex)]
        )
        newDescriptor.fetchLimit = remaining

        return (try? context.fetch(newDescriptor)) ?? []
    }

    // MARK: - Category Sessions

    /// All parent categories with word counts, sorted by total descending.
    static func allCategories(deckId: String, context: ModelContext) -> [(name: String, total: Int, learned: Int)] {
        let (categories, _) = allCategoriesWithSubcategories(deckId: deckId, context: context)
        return categories
    }

    /// Subcategories within a parent category, sorted by total descending.
    static func subcategories(deckId: String, parent: String, context: ModelContext) -> [(name: String, total: Int, learned: Int)] {
        let (_, subs) = allCategoriesWithSubcategories(deckId: deckId, context: context)
        return subs[parent] ?? []
    }

    /// Single-fetch method that computes both parent categories and all subcategories at once.
    static func allCategoriesWithSubcategories(deckId: String, context: ModelContext) -> (
        categories: [(name: String, total: Int, learned: Int)],
        subcategories: [String: [(name: String, total: Int, learned: Int)]]
    ) {
        let descriptor = FetchDescriptor<FlashCard>()
        guard let allCards = try? context.fetch(descriptor) else { return ([], [:]) }

        let deckCards = allCards.filter { $0.deckId == deckId && !$0.isTrashed }
        var parentGrouped: [String: (total: Int, learned: Int)] = [:]
        var subGrouped: [String: [String: (total: Int, learned: Int)]] = [:]

        for card in deckCards {
            guard let category = card.category, !category.isEmpty else { continue }
            let parts = category.split(separator: "/", maxSplits: 1)
            let parent = String(parts[0])
            let sub = parts.count > 1 ? String(parts[1]) : "general"
            let isLearned = card.status != "new" ? 1 : 0

            let existing = parentGrouped[parent] ?? (total: 0, learned: 0)
            parentGrouped[parent] = (total: existing.total + 1, learned: existing.learned + isLearned)

            var parentSubs = subGrouped[parent] ?? [:]
            let subExisting = parentSubs[sub] ?? (total: 0, learned: 0)
            parentSubs[sub] = (total: subExisting.total + 1, learned: subExisting.learned + isLearned)
            subGrouped[parent] = parentSubs
        }

        let categories = parentGrouped
            .map { (name: $0.key, total: $0.value.total, learned: $0.value.learned) }
            .sorted { $0.total > $1.total }

        var subcategories: [String: [(name: String, total: Int, learned: Int)]] = [:]
        for (parent, subs) in subGrouped {
            subcategories[parent] = subs
                .map { (name: $0.key, total: $0.value.total, learned: $0.value.learned) }
                .sorted { $0.total > $1.total }
        }

        return (categories, subcategories)
    }

    /// Build a category learn session — bypasses the unlock system.
    /// Prefers new cards first, then due cards, then already-learned.
    /// Matches by parent category or exact "parent/sub" category.
    static func buildCategoryLearnSession(deckId: String, category: String, limit: Int = 10, context: ModelContext) -> [FlashCard] {
        let descriptor = FetchDescriptor<FlashCard>()
        guard let allCards = try? context.fetch(descriptor) else { return [] }

        let categoryCards = allCards.filter {
            guard $0.deckId == deckId, !$0.isTrashed, let cat = $0.category else { return false }
            if category.contains("/") {
                // Exact subcategory match
                return cat == category
            }
            // Parent match: "actions" matches "actions" and "actions/movement & physical"
            let parent = cat.split(separator: "/").first.map(String.init) ?? cat
            return parent == category
        }

        // Prioritize: new cards first, then due, then the rest
        let now = Date()
        let newCards = categoryCards.filter { $0.status == "new" }
        let dueCards = categoryCards.filter {
            $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= now
        }
        let restCards = categoryCards.filter {
            $0.status != "new" && ($0.nextReviewDate == nil || $0.nextReviewDate! > now)
        }

        var result: [FlashCard] = []
        result.append(contentsOf: newCards.sorted { $0.wordIndex < $1.wordIndex })
        result.append(contentsOf: dueCards.sorted { ($0.nextReviewDate ?? .distantPast) < ($1.nextReviewDate ?? .distantPast) })
        result.append(contentsOf: restCards.sorted { $0.wordIndex < $1.wordIndex })

        return Array(result.prefix(limit))
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
                    $0.isTrashed != true &&
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
