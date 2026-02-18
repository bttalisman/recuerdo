import SwiftUI
import SwiftData
import UIKit

/// Shared review/learn session view used by StudySessionView, WordListView, and DebugView.
struct ReviewSessionView: View {
    var viewModel: StudySessionViewModel
    let title: String
    let backLabel: String
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @State private var ratingFlash: RatingFlash?
    private let hapticGenerator = UINotificationFeedbackGenerator()

    var body: some View {
        Group {
            if viewModel.isSessionComplete {
                sessionCompleteView
            } else if let card = viewModel.currentCard {
                cardView(card: card)
            } else {
                emptyStateView
            }
        }
        .onAppear { hapticGenerator.prepare() }
        .navigationTitle(title)
        .toolbar {
            if !viewModel.sessionCards.isEmpty && !viewModel.isSessionComplete {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.sessionProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { onDismiss() }
            }
        }
    }

    // MARK: - Card View

    @ViewBuilder
    private func cardView(card: FlashCard) -> some View {
        let deckMeta = decks.first
        VStack(spacing: 0) {
            FlashCardView(
                sourceText: card.sourceText,
                targetText: card.targetText,
                sourceLanguage: deckMeta?.sourceLanguage ?? "English",
                targetLanguage: deckMeta?.targetLanguage ?? "Spanish",
                status: card.status,
                article: card.article,
                partOfSpeech: card.partOfSpeech,
                showTargetFirst: viewModel.effectiveShowTargetFirst,
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
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(ratingFlash == .correct ? Color.green.opacity(0.25) : ratingFlash == .incorrect ? Color.red.opacity(0.25) : Color.clear)
                    .allowsHitTesting(false)
            )
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()

            if viewModel.mode == .learn {
                learnButtons
            } else {
                VStack(spacing: 12) {
                    reviewButtons
                        .opacity(viewModel.isFlipped ? 1 : 0)
                        .allowsHitTesting(viewModel.isFlipped)

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
        }
        .padding()
    }

    // MARK: - Learn Mode Buttons

    private var learnButtons: some View {
        HStack(spacing: 16) {
            if viewModel.isFlipped {
                Button {
                    viewModel.advanceToNextCard(context: modelContext)
                } label: {
                    Label("Next", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            Button {
                viewModel.endLearnSession(context: modelContext)
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(.horizontal)
    }

    // MARK: - Review Mode Buttons

    private var reviewButtons: some View {
        HStack(spacing: 16) {
            Button {
                submitWithFeedback(quality: 1)
            } label: {
                Label("Nope", systemImage: "xmark.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(GlowButtonStyle(baseColor: .red))

            Button {
                submitWithFeedback(quality: 4)
            } label: {
                Label("Got it", systemImage: "checkmark.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(GlowButtonStyle(baseColor: .green))
        }
        .padding(.horizontal)
    }

    private func submitWithFeedback(quality: Int) {
        let correct = quality >= 3
        hapticGenerator.notificationOccurred(correct ? .success : .error)
        hapticGenerator.prepare()
        ratingFlash = correct ? .correct : .incorrect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.submitRating(quality, context: modelContext)
                ratingFlash = nil
            }
        }
    }

    // MARK: - Session Complete

    private var sessionCompleteView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(viewModel.mode == .learn ? "Words Learned!" : "Review Complete!")
                .font(.title.bold())

            VStack(spacing: 8) {
                if viewModel.mode == .learn {
                    statRow(label: "New words seen", value: "\(viewModel.wordsLearned)")
                } else {
                    statRow(label: "Cards reviewed", value: "\(viewModel.totalReviewed)")
                    statRow(label: "Correct", value: "\(viewModel.correctCount)")
                    statRow(label: "Accuracy", value: "\(Int(viewModel.accuracy * 100))%")
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))

            Button(backLabel) { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding()
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("No cards available")
                .font(.title2)
            Text("Check back later.")
                .foregroundStyle(.secondary)

            Button("Back") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding()
    }
}

// MARK: - Rating Flash

enum RatingFlash {
    case correct, incorrect
}
