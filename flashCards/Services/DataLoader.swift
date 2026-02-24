import Foundation
import SwiftData

struct DeckFile: Codable {
    let deckId: String
    let sourceLanguage: String
    let sourceLanguageCode: String
    let targetLanguage: String
    let targetLanguageCode: String
    let version: Int
    let words: [WordEntry]
}

struct WordEntry: Codable {
    let id: String
    let source: String
    let target: String
    let article: String?
    let partOfSpeech: String?
    let category: String?
    let difficulty: Int
    let examples: [ExampleSentence]?
}

struct DataLoader {
    static func seedIfNeeded(container: ModelContainer) {
        let context = ModelContext(container)

        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return
        }

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let deck = try? JSONDecoder().decode(DeckFile.self, from: data) else {
                continue
            }

            let deckId = deck.deckId
            let descriptor = FetchDescriptor<DeckMetadata>(
                predicate: #Predicate { $0.deckId == deckId }
            )

            let existingMeta = try? context.fetch(descriptor).first

            if let existingMeta, existingMeta.jsonVersion >= deck.version {
                continue
            }

            if existingMeta != nil {
                // Version upgrade: update existing cards without resetting progress
                existingMeta!.jsonVersion = deck.version
                existingMeta!.totalWords = deck.words.count
                existingMeta!.lastSeedDate = Date()

                // Batch-fetch all cards for this deck once to avoid per-word queries
                let allDescriptor = FetchDescriptor<FlashCard>()
                let allCards = (try? context.fetch(allDescriptor)) ?? []
                var cardMap: [String: FlashCard] = [:]
                for card in allCards where card.deckId == deckId {
                    cardMap[card.wordId] = card
                }

                for (index, word) in deck.words.enumerated() {
                    if let existingCard = cardMap[word.id] {
                        // Update JSON-sourced fields only, preserve SR state
                        existingCard.sourceText = word.source
                        existingCard.targetText = word.target
                        existingCard.article = word.article
                        existingCard.partOfSpeech = word.partOfSpeech
                        existingCard.category = word.category
                        existingCard.frequencyRank = word.difficulty
                        existingCard.wordIndex = index
                        existingCard.examples = word.examples ?? []
                    } else {
                        let card = FlashCard(
                            wordId: word.id,
                            sourceText: word.source,
                            targetText: word.target,
                            article: word.article,
                            partOfSpeech: word.partOfSpeech,
                            category: word.category,
                            frequencyRank: word.difficulty,
                            deckId: deck.deckId,
                            wordIndex: index,
                            examples: word.examples ?? []
                        )
                        context.insert(card)
                    }
                }
            } else {
                // First-time seed
                let meta = DeckMetadata(
                    deckId: deck.deckId,
                    sourceLanguage: deck.sourceLanguage,
                    sourceLanguageCode: deck.sourceLanguageCode,
                    targetLanguage: deck.targetLanguage,
                    targetLanguageCode: deck.targetLanguageCode,
                    totalWords: deck.words.count,
                    jsonVersion: deck.version
                )
                meta.hasCompletedStarterList = false
                meta.lastSeedDate = Date()
                context.insert(meta)

                for (index, word) in deck.words.enumerated() {
                    let card = FlashCard(
                        wordId: word.id,
                        sourceText: word.source,
                        targetText: word.target,
                        article: word.article,
                        partOfSpeech: word.partOfSpeech,
                        category: word.category,
                        frequencyRank: word.difficulty,
                        deckId: deck.deckId,
                        wordIndex: index,
                        examples: word.examples ?? []
                    )
                    context.insert(card)
                }
            }

            try? context.save()
        }
    }
}
