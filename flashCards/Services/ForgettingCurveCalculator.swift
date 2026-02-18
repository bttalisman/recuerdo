import Foundation

enum RetentionTier: String, CaseIterable {
    case strong = "Strong"
    case moderate = "Moderate"
    case weak = "Weak"

    var easeRange: ClosedRange<Double> {
        switch self {
        case .strong: return 2.5...10.0
        case .moderate: return 1.8...2.4999
        case .weak: return 0.0...1.7999
        }
    }

    static func tier(for easeFactor: Double) -> RetentionTier {
        if easeFactor >= 2.5 { return .strong }
        if easeFactor >= 1.8 { return .moderate }
        return .weak
    }
}

struct RetentionPoint: Identifiable {
    let id = UUID()
    let day: Double
    let retention: Double
}

struct ActualRetentionPoint: Identifiable {
    let id = UUID()
    let daysSinceReview: Double
    let wasCorrect: Bool
}

struct TierCurveData: Identifiable {
    let id = UUID()
    let tier: RetentionTier
    let curve: [RetentionPoint]
    let cardCount: Int
    let averageStability: Double
}

struct ForgettingCurveCalculator {

    // MARK: - Core Ebbinghaus Model

    /// R(t) = e^(-t/S) where S = stability
    static func retention(at day: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return exp(-day / stability)
    }

    /// Stability from interval: S = interval / -ln(0.9)
    static func stability(from interval: Int) -> Double {
        guard interval > 0 else { return 1.0 }
        return Double(interval) / 0.10536
    }

    // MARK: - Curve Generation

    static func retentionCurve(stability: Double, maxDays: Double = 30) -> [RetentionPoint] {
        let steps = 60
        return (0...steps).map { i in
            let day = maxDays * Double(i) / Double(steps)
            return RetentionPoint(day: day, retention: retention(at: day, stability: stability))
        }
    }

    // MARK: - Aggregate Tier Curves

    static func aggregateCurves(cards: [FlashCard]) -> [TierCurveData] {
        let reviewed = cards.filter { $0.totalReviews > 0 && $0.interval > 0 }
        guard !reviewed.isEmpty else { return [] }

        return RetentionTier.allCases.compactMap { tier in
            let tierCards = reviewed.filter { RetentionTier.tier(for: $0.easeFactor) == tier }
            guard !tierCards.isEmpty else { return nil }

            let avgStability = tierCards.map { stability(from: $0.interval) }.reduce(0, +) / Double(tierCards.count)
            let curve = retentionCurve(stability: avgStability, maxDays: 30)

            return TierCurveData(
                tier: tier,
                curve: curve,
                cardCount: tierCards.count,
                averageStability: avgStability
            )
        }
    }

    // MARK: - Actual Retention Data

    static func actualRetentionData(reviews: [ReviewRecord]) -> [ActualRetentionPoint] {
        var points: [ActualRetentionPoint] = []

        // Group reviews by card, sorted by date
        var byCard: [String: [ReviewRecord]] = [:]
        for review in reviews {
            guard let wordId = review.card?.wordId else { continue }
            byCard[wordId, default: []].append(review)
        }

        for (_, cardReviews) in byCard {
            let sorted = cardReviews.sorted { $0.reviewDate < $1.reviewDate }
            for i in 1..<sorted.count {
                let elapsed = sorted[i].reviewDate.timeIntervalSince(sorted[i-1].reviewDate) / 86400.0
                if elapsed > 0 && elapsed <= 30 {
                    points.append(ActualRetentionPoint(
                        daysSinceReview: elapsed,
                        wasCorrect: sorted[i].wasCorrect
                    ))
                }
            }
        }

        return points
    }

    // MARK: - Per-Word Curve

    static func wordCurve(card: FlashCard) -> (curve: [RetentionPoint], stability: Double) {
        let s = stability(from: max(card.interval, 1))
        let curve = retentionCurve(stability: s, maxDays: 30)
        return (curve, s)
    }

    static func wordReviewPoints(card: FlashCard) -> [ActualRetentionPoint] {
        let sorted = card.reviewHistory.sorted { $0.reviewDate < $1.reviewDate }
        var points: [ActualRetentionPoint] = []
        for i in 1..<sorted.count {
            let elapsed = sorted[i].reviewDate.timeIntervalSince(sorted[i-1].reviewDate) / 86400.0
            if elapsed > 0 && elapsed <= 30 {
                points.append(ActualRetentionPoint(
                    daysSinceReview: elapsed,
                    wasCorrect: sorted[i].wasCorrect
                ))
            }
        }
        return points
    }

    // MARK: - Summary Stats

    static func optimalReviewDay(stability: Double, targetRetention: Double = 0.85) -> Double {
        guard stability > 0, targetRetention > 0, targetRetention < 1 else { return 1 }
        return -stability * log(targetRetention)
    }
}
