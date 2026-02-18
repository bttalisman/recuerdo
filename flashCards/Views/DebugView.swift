import SwiftUI
import SwiftData

struct DebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @Query private var allCards: [FlashCard]
    @State private var reviewCount: Int = 5
    @State private var viewModel: StudySessionViewModel?

    private var activeDeckId: String? { decks.first?.deckId }

    private var learnedCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        return allCards.filter { $0.deckId == deckId && $0.status != "new" }.count
    }

    var body: some View {
        NavigationStack {
            if let viewModel {
                ReviewSessionView(
                    viewModel: viewModel,
                    title: "Debug Review",
                    backLabel: "Back",
                    onDismiss: { self.viewModel = nil }
                )
            } else {
                Form {
                    Section("Quick Review") {
                        Stepper("\(reviewCount) cards", value: $reviewCount, in: 1...max(learnedCount, 1))

                        Button("Start Review") {
                            let vm = StudySessionViewModel()
                            if let deckId = activeDeckId {
                                vm.loadReviewSession(deckId: deckId, cardDirection: decks.first?.cardDirection ?? "source_first", context: modelContext)
                            }
                            viewModel = vm
                        }
                        .disabled(learnedCount == 0)

                        Text("\(learnedCount) learned words available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("")
                .enhancedDarkContrast()
            }
        }
    }
}
