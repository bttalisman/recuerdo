import SwiftUI
import SwiftData

struct VergeView: View {
    @Query private var allCards: [FlashCard]
    @Query(sort: \ReviewRecord.reviewDate)
    private var allReviews: [ReviewRecord]
    @State private var vergeWords: [VergeWord] = []

    private var almostMastered: [VergeWord] {
        vergeWords.filter { $0.category == .almostMastered }
    }

    private var tipOfTongue: [VergeWord] {
        vergeWords.filter { $0.category == .tipOfTongue }
    }

    private var stillBuilding: [VergeWord] {
        vergeWords.filter { $0.category == .stillBuilding }
    }

    var body: some View {
        NavigationStack {
            List {
                if allReviews.count < 50 {
                    Section { earlyState.subtleSectionGlow() }
                } else if vergeWords.isEmpty {
                    Section { emptyState.subtleSectionGlow() }
                } else {
                    if !almostMastered.isEmpty {
                        Section {
                            summaryHeader
                                .subtleSectionGlow()
                        }
                    }

                    if !almostMastered.isEmpty {
                        Section {
                            ForEach(almostMastered) { word in
                                wordRow(word)
                            }
                            .subtleSectionGlow()
                        } header: {
                            categoryHeader(
                                title: "Almost Mastered",
                                icon: "checkmark.circle",
                                color: .green,
                                count: almostMastered.count
                            )
                        }
                    }

                    if !tipOfTongue.isEmpty {
                        Section {
                            ForEach(tipOfTongue) { word in
                                wordRow(word)
                            }
                            .subtleSectionGlow()
                        } header: {
                            categoryHeader(
                                title: "Tip of Tongue",
                                icon: "lightbulb",
                                color: .orange,
                                count: tipOfTongue.count
                            )
                        }
                    }

                    if !stillBuilding.isEmpty {
                        Section {
                            ForEach(stillBuilding) { word in
                                wordRow(word)
                            }
                            .subtleSectionGlow()
                        } header: {
                            categoryHeader(
                                title: "Still Building",
                                icon: "hammer",
                                color: .blue,
                                count: stillBuilding.count
                            )
                        }
                    }
                }
            }
            .navigationTitle("On the Verge")
            .navigationBarTitleDisplayMode(.large)
            .enhancedDarkContrast()
            .onAppear {
                vergeWords = VergeAnalyzer.analyze(cards: allCards, reviews: allReviews)
            }
        }
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            let total = vergeWords.count
            let almostCount = almostMastered.count
            Text("\(total) word\(total == 1 ? "" : "s") on the verge")
                .font(.headline)
            if almostCount > 0 {
                Text("\(almostCount) almost mastered — keep it up!")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Category Header

    private func categoryHeader(title: String, icon: String, color: Color, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(title) (\(count))")
        }
    }

    // MARK: - Word Row

    private func wordRow(_ word: VergeWord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let article = word.card.article, !article.isEmpty {
                        Text(article)
                            .foregroundStyle(.secondary)
                    }
                    Text(word.card.targetText)
                        .fontWeight(.medium)
                }
                Text(word.card.displaySourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            attemptBadge(word)
        }
    }

    private func attemptBadge(_ word: VergeWord) -> some View {
        let (text, color) = badgeContent(word)
        return Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func badgeContent(_ word: VergeWord) -> (String, Color) {
        switch word.category {
        case .almostMastered:
            return ("1st try", .green)
        case .tipOfTongue:
            return ("2nd try", .orange)
        case .stillBuilding:
            let tries = Int(ceil(word.avgAttemptsBeforeCorrect)) + 1
            return ("\(tries) tries", .blue)
        }
    }

    // MARK: - Empty States

    private var earlyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Keep studying!")
                .font(.headline)
            Text("Verge analysis appears after 50+ reviews. You have \(allReviews.count) so far.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("No words on the verge")
                .font(.headline)
            Text("As you review more words, cards that are close to mastery will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
