import Foundation
import SwiftData

struct ExampleSentence: Codable, Hashable {
    let es: String
    let en: String
}

@Model
final class FlashCard {
    @Attribute(.unique) var wordId: String
    var sourceText: String
    var targetText: String
    var article: String?
    var partOfSpeech: String?
    var category: String?
    var frequencyRank: Int
    var deckId: String
    var wordIndex: Int
    var examplesData: Data?

    @Transient
    private var _cachedExamples: [ExampleSentence]?

    @Transient
    var examples: [ExampleSentence] {
        get {
            if let cached = _cachedExamples { return cached }
            guard let data = examplesData else { return [] }
            let decoded = (try? JSONDecoder().decode([ExampleSentence].self, from: data)) ?? []
            _cachedExamples = decoded
            return decoded
        }
        set {
            examplesData = try? JSONEncoder().encode(newValue)
            _cachedExamples = newValue
        }
    }

    // Spaced repetition state
    var status: String // "new", "learning", "mastered"
    var introducedDate: Date?
    var masteredDate: Date?
    var easeFactor: Double
    var interval: Int // days
    var repetitionCount: Int
    var nextReviewDate: Date?
    var lastReviewDate: Date?
    var totalReviews: Int
    var totalCorrect: Int
    var currentStreak: Int
    var longestStreak: Int

    @Relationship(deleteRule: .cascade, inverse: \ReviewRecord.card)
    var reviewHistory: [ReviewRecord]

    /// Display-friendly English text: prepends "to " for verbs that don't already have it.
    /// Modal verbs (could, should, would, etc.) are excluded since "to could" is ungrammatical.
    private static let modalVerbs: Set<String> = ["can", "could", "may", "might", "must", "shall", "should", "will", "would"]

    var displaySourceText: String {
        if partOfSpeech == "verb"
            && !sourceText.lowercased().hasPrefix("to ")
            && !sourceText.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .contains(where: { Self.modalVerbs.contains($0) }) {
            return "to \(sourceText)"
        }
        return sourceText
    }

    init(wordId: String, sourceText: String, targetText: String,
         article: String?, partOfSpeech: String?, category: String?,
         frequencyRank: Int, deckId: String,
         wordIndex: Int = 0, examples: [ExampleSentence] = []) {
        self.wordId = wordId
        self.sourceText = sourceText
        self.targetText = targetText
        self.article = article
        self.partOfSpeech = partOfSpeech
        self.category = category
        self.frequencyRank = frequencyRank
        self.deckId = deckId
        self.wordIndex = wordIndex
        self.examplesData = try? JSONEncoder().encode(examples)
        self.status = "new"
        self.introducedDate = nil
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitionCount = 0
        self.nextReviewDate = nil
        self.lastReviewDate = nil
        self.totalReviews = 0
        self.totalCorrect = 0
        self.currentStreak = 0
        self.longestStreak = 0
        self.reviewHistory = []
    }
}
