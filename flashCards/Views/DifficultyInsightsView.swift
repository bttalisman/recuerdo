import SwiftUI
import SwiftData

struct DifficultyInsightsView: View {
    @Query(sort: \ReviewRecord.reviewDate)
    private var allReviews: [ReviewRecord]
    @Query private var allCards: [FlashCard]
    @State private var expandedInsightId: String?
    @State private var insights: [Insight] = []
    @State private var detailInsight: Insight?

    var body: some View {
        List {
            if allReviews.count < 50 {
                Section { emptyState.subtleSectionGlow() }
            } else if insights.isEmpty {
                Section { noInsightsState.subtleSectionGlow() }
            } else {
                ForEach(insights) { insight in
                    Section { insightCard(insight).subtleSectionGlow() }
                }
            }
        }
        .navigationTitle("Difficulty Insights")
        .navigationBarTitleDisplayMode(.large)
        .enhancedDarkContrast()
        .sheet(item: $detailInsight) { insight in
            NavigationStack {
                ScrollView {
                    Text(insight.detail ?? "")
                        .padding()
                }
                .navigationTitle(insight.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { detailInsight = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            insights = DifficultyAnalyzer.generateInsights(cards: allCards, reviews: allReviews)
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Keep studying!")
                .font(.headline)
            Text("Insights appear after 50+ reviews. You have \(allReviews.count) so far.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var noInsightsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Looking good!")
                .font(.headline)
            Text("No significant difficulty patterns detected. Keep up the great work!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Insight Card

    private func insightCard(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedInsightId = expandedInsightId == insight.id ? nil : insight.id
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.title3)
                        .foregroundStyle(severityColor(insight.severity))
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(insight.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Circle()
                                .fill(severityColor(insight.severity))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            if insight.detail != nil {
                                Button {
                                    detailInsight = insight
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("More info about \(insight.title)")
                            }
                        }
                        Text(insight.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if !insight.supportingWords.isEmpty {
                        Image(systemName: expandedInsightId == insight.id ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(insight.supportingWords.isEmpty ? "" : "Double tap to \(expandedInsightId == insight.id ? "collapse" : "expand") affected words")

            // Expanded word list
            if expandedInsightId == insight.id && !insight.supportingWords.isEmpty {
                Divider()
                VStack(spacing: 8) {
                    ForEach(insight.supportingWords, id: \.wordId) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    if let article = card.article, !article.isEmpty {
                                        Text(article)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(card.targetText)
                                        .fontWeight(.medium)
                                }
                                Text(card.displaySourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if card.totalReviews > 0 {
                                let acc = Double(card.totalCorrect) / Double(card.totalReviews)
                                Text("\(Int(acc * 100))%")
                                    .font(.caption.bold())
                                    .foregroundStyle(accuracyColor(acc))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(accuracyColor(acc).opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func severityColor(_ severity: Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.8 { return .green }
        if accuracy >= 0.6 { return .orange }
        return .red
    }
}
