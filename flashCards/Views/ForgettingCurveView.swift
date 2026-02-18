import SwiftUI
import SwiftData
import Charts

struct ForgettingCurveView: View {
    @Query(sort: \ReviewRecord.reviewDate)
    private var allReviews: [ReviewRecord]
    @Query private var allCards: [FlashCard]
    @State private var selectedCard: FlashCard?
    @State private var searchText = ""

    private var reviewedCards: [FlashCard] {
        allCards.filter { $0.totalReviews > 0 && $0.interval > 0 }
    }

    private var filteredCards: [FlashCard] {
        if searchText.isEmpty { return reviewedCards }
        let q = searchText.lowercased()
        return reviewedCards.filter {
            $0.targetText.lowercased().contains(q) ||
            $0.sourceText.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let card = selectedCard {
                    wordCurveSection(card)
                } else {
                    aggregateCurveSection
                }
                summaryStatsSection
                wordPickerSection
            }
            .padding()
        }
        .navigationTitle("Forgetting Curves")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search words...")
    }

    // MARK: - Aggregate Curve

    private var tierCurves: [TierCurveData] {
        ForgettingCurveCalculator.aggregateCurves(cards: allCards)
    }

    private var actualPoints: [ActualRetentionPoint] {
        ForgettingCurveCalculator.actualRetentionData(reviews: allReviews)
    }

    private var aggregateCurveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Decay by Strength")
                .font(.headline)
            Text("How retention drops over days since review")
                .font(.caption)
                .foregroundStyle(.secondary)

            if tierCurves.isEmpty {
                Text("Not enough reviewed cards to show curves.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart {
                    // Tier area curves
                    ForEach(tierCurves) { tier in
                        ForEach(tier.curve) { point in
                            AreaMark(
                                x: .value("Days", point.day),
                                y: .value("Retention", point.retention)
                            )
                            .foregroundStyle(tierColor(tier.tier).opacity(0.15))
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Days", point.day),
                                y: .value("Retention", point.retention)
                            )
                            .foregroundStyle(tierColor(tier.tier))
                            .interpolationMethod(.catmullRom)
                        }
                    }

                    // Actual review scatter
                    ForEach(actualPoints) { point in
                        PointMark(
                            x: .value("Days", point.daysSinceReview),
                            y: .value("Retention", point.wasCorrect ? 1.0 : 0.0)
                        )
                        .foregroundStyle(point.wasCorrect ? .green.opacity(0.4) : .red.opacity(0.4))
                        .symbolSize(20)
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                    }
                }
                .chartXAxisLabel("Days since review")
                .frame(height: 250)

                // Legend
                HStack(spacing: 16) {
                    ForEach(tierCurves) { tier in
                        HStack(spacing: 4) {
                            Circle().fill(tierColor(tier.tier)).frame(width: 8, height: 8)
                            Text("\(tier.tier.rawValue) (\(tier.cardCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Single Word Curve

    private func wordCurveSection(_ card: FlashCard) -> some View {
        let data = ForgettingCurveCalculator.wordCurve(card: card)
        let reviewPoints = ForgettingCurveCalculator.wordReviewPoints(card: card)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        if let article = card.article, !article.isEmpty {
                            Text(article).foregroundStyle(.secondary)
                        }
                        Text(card.targetText).font(.headline)
                    }
                    Text(card.sourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Show All") {
                    withAnimation { selectedCard = nil }
                }
                .font(.subheadline)
            }

            Chart {
                ForEach(data.curve) { point in
                    AreaMark(
                        x: .value("Days", point.day),
                        y: .value("Retention", point.retention)
                    )
                    .foregroundStyle(.blue.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Days", point.day),
                        y: .value("Retention", point.retention)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                }

                ForEach(reviewPoints) { point in
                    PointMark(
                        x: .value("Days", point.daysSinceReview),
                        y: .value("Outcome", point.wasCorrect ? 1.0 : 0.0)
                    )
                    .foregroundStyle(point.wasCorrect ? .green : .red)
                    .symbolSize(40)
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%")
                        }
                    }
                }
            }
            .chartXAxisLabel("Days since review")
            .frame(height: 250)

            HStack(spacing: 16) {
                statBadge(label: "Stability", value: String(format: "%.1fd", data.stability))
                statBadge(label: "Interval", value: "\(card.interval)d")
                statBadge(label: "Ease", value: String(format: "%.2f", card.easeFactor))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Summary Stats

    private var summaryStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optimal Review Timing")
                .font(.headline)

            if tierCurves.isEmpty {
                Text("No data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tierCurves) { tier in
                    let optimalDay = ForgettingCurveCalculator.optimalReviewDay(stability: tier.averageStability)
                    HStack {
                        Circle().fill(tierColor(tier.tier)).frame(width: 10, height: 10)
                        Text(tier.tier.rawValue)
                            .font(.subheadline)
                        Spacer()
                        Text("Review by day \(Int(ceil(optimalDay)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("(S = \(String(format: "%.1f", tier.averageStability)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Word Picker

    private var wordPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore Individual Words")
                .font(.headline)
            Text("Tap a word to see its forgetting curve")
                .font(.caption)
                .foregroundStyle(.secondary)

            if filteredCards.isEmpty {
                Text("No reviewed words found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(filteredCards.prefix(20), id: \.wordId) { card in
                    Button {
                        withAnimation { selectedCard = card }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if let article = card.article, !article.isEmpty {
                                        Text(article).foregroundStyle(.secondary)
                                    }
                                    Text(card.targetText).fontWeight(.medium)
                                }
                                Text(card.sourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let tier = RetentionTier.tier(for: card.easeFactor)
                            Text(tier.rawValue)
                                .font(.caption)
                                .foregroundStyle(tierColor(tier))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tierColor(tier).opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Helpers

    private func tierColor(_ tier: RetentionTier) -> Color {
        switch tier {
        case .strong: return .green
        case .moderate: return .orange
        case .weak: return .red
        }
    }

    private func statBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
