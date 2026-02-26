import Foundation

struct ReviewResult {
    let newInterval: Int
    let newEaseFactor: Double
    let newRepetitionCount: Int
    let newStatus: String
}

struct SpacedRepetitionEngine {
    static func processReview(
        currentInterval: Int,
        currentEaseFactor: Double,
        currentRepetitionCount: Int,
        currentStatus: String,
        quality: Int,
        introducedDate: Date? = nil
    ) -> ReviewResult {
        var ef = currentEaseFactor
        var interval = currentInterval
        var reps = currentRepetitionCount
        var status = currentStatus

        // SM-2 ease factor adjustment
        let efDelta = 0.1 - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02)
        ef = max(1.3, ef + efDelta)

        if quality < 3 {
            // Failed: reset to learning
            reps = 0
            interval = 0
            status = "learning"
        } else {
            reps += 1

            switch reps {
            case 1:
                interval = 1
            case 2:
                interval = 3
            default:
                interval = Int(ceil(Double(currentInterval) * ef))
            }

            interval = min(interval, 180)

            let daysSinceIntroduced = introducedDate.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 0
            if reps >= 6 && interval >= 21 && daysSinceIntroduced >= 21 {
                status = "mastered"
            } else {
                status = "learning"
            }
        }

        return ReviewResult(
            newInterval: interval,
            newEaseFactor: ef,
            newRepetitionCount: reps,
            newStatus: status
        )
    }
}
