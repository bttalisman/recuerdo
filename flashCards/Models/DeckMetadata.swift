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
    var showTargetFirst: Bool
    var reviewMode: String // "free" or "scheduled"
    var reviewAccumulationRate: Int // words per hour (1-5)
    var lastReviewDrainDate: Date? // when accumulation was last drained
    var scheduledReviewIntervalMinutes: Int
    var lastScheduledReviewDate: Date?

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
        self.showTargetFirst = false
        self.reviewMode = "free"
        self.reviewAccumulationRate = 3
        self.lastReviewDrainDate = nil
        self.scheduledReviewIntervalMinutes = 120
        self.lastScheduledReviewDate = nil
    }
}
