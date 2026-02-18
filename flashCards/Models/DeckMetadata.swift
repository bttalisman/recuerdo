import Foundation
import SwiftData

@Model
final class DeckMetadata {
    @Attribute(.unique) var deckId: String
    var sourceLanguage: String
    var sourceLanguageCode: String
    var targetLanguage: String
    var targetLanguageCode: String
    var totalWords: Int
    var lastSeedDate: Date?
    var jsonVersion: Int
    var dailyNewCardLimit: Int
    var cardDirection: String // "source_first", "target_first", "mixed"
    var unlockedWordCount: Int
    var newWordsMode: String // "free" or "scheduled"
    var newWordsAccumulationRate: Int // words per hour, used in scheduled mode
    var lastNewWordsDrainDate: Date? // when scheduled-mode accumulation was last drained

    init(deckId: String, sourceLanguage: String, sourceLanguageCode: String,
         targetLanguage: String, targetLanguageCode: String,
         totalWords: Int, jsonVersion: Int) {
        self.deckId = deckId
        self.sourceLanguage = sourceLanguage
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguage = targetLanguage
        self.targetLanguageCode = targetLanguageCode
        self.totalWords = totalWords
        self.lastSeedDate = nil
        self.jsonVersion = jsonVersion
        self.dailyNewCardLimit = 10
        self.cardDirection = "source_first"
        self.unlockedWordCount = 500
        self.newWordsMode = "free"
        self.newWordsAccumulationRate = 2
        self.lastNewWordsDrainDate = nil
    }
}
