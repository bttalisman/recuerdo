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
                debugSessionView(viewModel: viewModel)
            } else {
                Form {
                    Section("Quick Review") {
                        Stepper("\(reviewCount) cards", value: $reviewCount, in: 1...max(learnedCount, 1))

                        Button("Start Review") {
                            let vm = StudySessionViewModel()
                            if let deckId = activeDeckId {
                                vm.loadReviewSession(deckId: deckId, scheduled: false, accumulatedCount: reviewCount, showTargetFirst: decks.first?.showTargetFirst ?? false, context: modelContext)
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

    @ViewBuilder
    private func debugSessionView(viewModel: StudySessionViewModel) -> some View {
        Group {
            if viewModel.isSessionComplete {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Review Complete!")
                        .font(.title.bold())
                    VStack(spacing: 8) {
                        HStack {
                            Text("Cards reviewed")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.totalReviewed)")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("Correct")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.correctCount)")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("Accuracy")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(viewModel.accuracy * 100))%")
                                .fontWeight(.semibold)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))

                    Button("Back") { self.viewModel = nil }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let card = viewModel.currentCard {
                let deckMeta = decks.first
                VStack(spacing: 24) {
                    Spacer()
                    FlashCardView(
                        sourceText: card.sourceText,
                        targetText: card.targetText,
                        sourceLanguage: deckMeta?.sourceLanguage ?? "English",
                        targetLanguage: deckMeta?.targetLanguage ?? "Spanish",
                        status: card.status,
                        article: card.article,
                        showTargetFirst: deckMeta?.showTargetFirst ?? false,
                        sourceLanguageCode: deckMeta?.sourceLanguageCode ?? "en",
                        targetLanguageCode: deckMeta?.targetLanguageCode ?? "es",
                        examples: card.examples,
                        isFlipped: Binding(
                            get: { viewModel.isFlipped },
                            set: { viewModel.isFlipped = $0 }
                        )
                    )
                    .id(card.wordId)
                    .frame(height: 300)
                    .padding(.horizontal)
                    Spacer()

                    VStack(spacing: 12) {
                        if viewModel.isFlipped {
                            HStack(spacing: 16) {
                                Button {
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        viewModel.submitRating(1, context: modelContext)
                                    }
                                } label: {
                                    Label("Nope", systemImage: "xmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)

                                Button {
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        viewModel.submitRating(4, context: modelContext)
                                    }
                                } label: {
                                    Label("Got it", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                            .padding(.horizontal)
                        }

                        Button {
                            viewModel.isSessionComplete = true
                        } label: {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .padding(.horizontal)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.isFlipped)
                .padding()
            } else {
                VStack {
                    Text("No cards available")
                    Button("Back") { self.viewModel = nil }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Debug Review")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.sessionProgress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { self.viewModel = nil }
            }
        }
    }
}
