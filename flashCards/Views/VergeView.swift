import SwiftUI
import SwiftData

struct VergeView: View {
    @Query private var allCards: [FlashCard]
    @Query private var decks: [DeckMetadata]
    @Environment(\.modelContext) private var modelContext
    @State private var vergeWords: [VergeWord] = []
    @State private var reviewViewModel: StudySessionViewModel?
    @State private var isLoading = true
    @State private var reviewCount: Int = 0

    private static let sectionCap = 15

    private var cardDirection: String { decks.first?.cardDirection ?? "source_first" }

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
                if isLoading {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                    }
                } else if reviewCount < 50 {
                    Section { earlyState.subtleSectionGlow() }
                } else if vergeWords.isEmpty {
                    Section { emptyState.subtleSectionGlow() }
                } else {
                    Section {
                        summaryHeader
                            .subtleSectionGlow()
                    }

                    if !stillBuilding.isEmpty {
                        vergeSection(
                            title: "Still Building",
                            icon: "hammer",
                            color: .blue,
                            words: stillBuilding
                        )
                    }

                    if !tipOfTongue.isEmpty {
                        vergeSection(
                            title: "Tip of Tongue",
                            icon: "lightbulb",
                            color: .orange,
                            words: tipOfTongue
                        )
                    }

                    if !almostMastered.isEmpty {
                        vergeSection(
                            title: "Almost Mastered",
                            icon: "checkmark.circle",
                            color: .green,
                            words: almostMastered
                        )
                    }
                }
            }
            .navigationTitle("On the Verge")
            .navigationBarTitleDisplayMode(.large)
            .enhancedDarkContrast()
            .onAppear { loadVergeData() }
        }
        .fullScreenCover(item: $reviewViewModel) { vm in
            NavigationStack {
                ReviewSessionView(
                    viewModel: vm,
                    title: "Verge Review",
                    backLabel: "Back to Verge",
                    onDismiss: {
                        reviewViewModel = nil
                        loadVergeData()
                    },
                    deckMeta: decks.first
                )
            }
        }
    }

    private func vergeSection(title: String, icon: String, color: Color, words: [VergeWord]) -> some View {
        let capped = Array(words.prefix(Self.sectionCap))
        let overflow = words.count - capped.count
        return Section {
            ForEach(capped) { word in
                wordRow(word)
            }
            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            EmptyView().subtleSectionGlow()
        } header: {
            categoryHeader(title: title, icon: icon, color: color, words: words)
        }
    }

    private func loadVergeData() {
        let container = modelContext.container
        let mainCards = allCards
        isLoading = true
        Task {
            let results = await VergeAnalyzer.analyzeInBackground(container: container)
            let cardMap = Dictionary(uniqueKeysWithValues: mainCards.map { ($0.wordId, $0) })
            vergeWords = results.compactMap { r in
                guard let card = cardMap[r.id] else { return nil }
                return VergeWord(id: r.id, card: card, category: r.category,
                                 avgAttemptsBeforeCorrect: r.avgAttemptsBeforeCorrect,
                                 sessionsAnalyzed: r.sessionsAnalyzed)
            }
            // Get review count for early state check
            let count = await Task.detached {
                let ctx = ModelContext(container)
                return (try? ctx.fetchCount(FetchDescriptor<ReviewRecord>())) ?? 0
            }.value
            reviewCount = count
            isLoading = false
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

    private func categoryHeader(title: String, icon: String, color: Color, words: [VergeWord]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(title) (\(words.count))")

            Spacer()

            Button {
                let cards = words.map(\.card)
                let vm = StudySessionViewModel()
                vm.loadCustomReviewSession(cards: cards, cardDirection: cardDirection)
                reviewViewModel = vm
            } label: {
                Label("Review", systemImage: "play.fill")
                    .font(.caption2.bold())
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
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
            Text("Verge analysis appears after 50+ reviews. You have \(reviewCount) so far.")
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
