import Foundation
import SwiftData

@Model
final class ReviewRecord {
    var card: FlashCard?
    var reviewDate: Date
    var quality: Int
    var wasCorrect: Bool
    var previousInterval: Int
    var newInterval: Int
    var previousEaseFactor: Double
    var newEaseFactor: Double
    var studyMode: String          // "free_review", "scheduled_review"
    var responseTimeSeconds: Double // seconds from card shown to rating
    var cardDirection: String      // "source_to_target" or "target_to_source"
    var recallModality: String = "visual"  // "visual", "spoken", "pronunciation"

    init(card: FlashCard, reviewDate: Date, quality: Int,
         wasCorrect: Bool, previousInterval: Int, newInterval: Int,
         previousEaseFactor: Double, newEaseFactor: Double,
         studyMode: String = "free_review",
         responseTimeSeconds: Double = 0,
         cardDirection: String = "source_to_target",
         recallModality: String = "visual") {
        self.card = card
        self.reviewDate = reviewDate
        self.quality = quality
        self.wasCorrect = wasCorrect
        self.previousInterval = previousInterval
        self.newInterval = newInterval
        self.previousEaseFactor = previousEaseFactor
        self.newEaseFactor = newEaseFactor
        self.studyMode = studyMode
        self.responseTimeSeconds = responseTimeSeconds
        self.cardDirection = cardDirection
        self.recallModality = recallModality
    }
}
