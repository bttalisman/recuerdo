import SwiftUI
import SwiftData
import Charts

struct ForgettingCurveView: View {
    @Query(sort: \ReviewRecord.reviewDate)
    private var allReviews: [ReviewRecord]
    @Query private var allCards: [FlashCard]
    @State private var selectedCard: FlashCard?
    @State private var searchText = ""
    @State private var showCurveInfo = false
    @State private var showTimingInfo = false

    private var reviewedCards: [FlashCard] {
        allCards.filter { $0.totalReviews > 0 && $0.interval > 0 }
    }

    private var filteredCards: [FlashCard] {
        if searchText.isEmpty { return reviewedCards }
        let q = searchText.lowercased()
        return reviewedCards.filter {
            $0.targetText.lowercased().contains(q) ||
            $0.displaySourceText.lowercased().contains(q)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    if let card = selectedCard {
                        wordCurveSection(card)
                            .id("curveChart")
                            .subtleSectionGlow()
                    } else {
                        aggregateCurveSection
                            .id("curveChart")
                            .subtleSectionGlow()
                    }
                }
                Section { summaryStatsSection.subtleSectionGlow() }
                Section { wordPickerSection(scrollProxy: proxy).subtleSectionGlow() }
            }
        }
        .navigationTitle("Word Retention")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search words...")
        .enhancedDarkContrast()
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
            HStack {
                Text("Memory Decay by Strength")
                    .font(.headline)
                Spacer()
                Button {
                    showCurveInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info")
            }
            .alert("About Memory Decay", isPresented: $showCurveInfo) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("This chart groups your reviewed words into three tiers by ease factor, then models a decay curve for each tier.\n\nStrong (green): words you find easy — memory decays slowly.\nModerate (orange): average difficulty — medium decay.\nWeak (red): words you struggle with — memory fades quickly.\n\nThe Y-axis is retention: 100% means perfect recall. The scattered dots are your real results — green = correct, red = incorrect. Use \"Explore Individual Words\" below to see any single word's curve.")
            }
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
                    // Tier area curves — use series to separate tiers
                    ForEach(tierCurves) { tier in
                        ForEach(tier.curve) { point in
                            LineMark(
                                x: .value("Days", point.day),
                                y: .value("Retention", point.retention),
                                series: .value("Tier", tier.tier.rawValue)
                            )
                            .foregroundStyle(tierColor(tier.tier))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }

                    // Actual review scatter
                    ForEach(actualPoints) { point in
                        PointMark(
                            x: .value("Days", point.daysSinceReview),
                            y: .value("Outcome", point.wasCorrect ? 0.95 : 0.05)
                        )
                        .foregroundStyle(point.wasCorrect ? .green.opacity(0.7) : .red.opacity(0.7))
                        .symbolSize(30)
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
                .padding(.top, 12)
                .clipped()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(aggregateChartAccessibilityLabel)

                // Legend
                HStack(spacing: 16) {
                    ForEach(tierCurves) { tier in
                        HStack(spacing: 4) {
                            Circle().fill(tierColor(tier.tier)).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text("\(tier.tier.rawValue) (\(tier.cardCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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
                    Text(card.displaySourceText)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Forgetting curve for \(card.targetText). Stability \(String(format: "%.1f", data.stability)) days, interval \(card.interval) days")

            HStack(spacing: 16) {
                statBadge(label: "Stability", value: String(format: "%.1fd", data.stability))
                statBadge(label: "Interval", value: "\(card.interval)d")
                statBadge(label: "Ease", value: String(format: "%.2f", card.easeFactor))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stability \(String(format: "%.1f", data.stability)) days, Interval \(card.interval) days, Ease \(String(format: "%.2f", card.easeFactor))")
        }
    }

    // MARK: - Summary Stats

    private var summaryStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Optimal Review Timing")
                    .font(.headline)
                Spacer()
                Button {
                    showTimingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info")
            }
            .alert("About Review Timing", isPresented: $showTimingInfo) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("Each word has a stability value (S) — the number of days it takes for your recall to drop to 90%. Higher stability means the memory lasts longer.\n\n\"Review by day X\" is the latest you should review words in that tier before retention drops below 90%. Recuerdo uses these values to schedule your reviews automatically.\n\nStrong words have high stability and can wait longer between reviews. Weak words fade faster and need more frequent practice.")
            }

            if tierCurves.isEmpty {
                Text("No data yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tierCurves) { tier in
                    let optimalDay = ForgettingCurveCalculator.optimalReviewDay(stability: tier.averageStability)
                    HStack {
                        Circle().fill(tierColor(tier.tier)).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
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
    }

    // MARK: - Word Picker

    private func wordPickerSection(scrollProxy proxy: ScrollViewProxy) -> some View {
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
                        withAnimation {
                            selectedCard = card
                            proxy.scrollTo("curveChart", anchor: .top)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if let article = card.article, !article.isEmpty {
                                        Text(article).foregroundStyle(.secondary)
                                    }
                                    Text(card.targetText).fontWeight(.medium)
                                }
                                Text(card.displaySourceText)
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
    }

    // MARK: - Helpers

    private var aggregateChartAccessibilityLabel: String {
        let tierSummaries = tierCurves.map { "\($0.tier.rawValue): \($0.cardCount) words" }
        return "Memory decay chart with \(tierCurves.count) tiers. \(tierSummaries.joined(separator: ", "))"
    }

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
