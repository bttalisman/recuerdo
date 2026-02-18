import SwiftUI
import SwiftData
import UIKit

struct StudySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: StudySessionViewModel?
    @Query(filter: #Predicate<DeckMetadata> { _ in true })
    private var decks: [DeckMetadata]
    @Query private var allCards: [FlashCard]
    @State private var ratingFlash: RatingFlash?

    private var activeDeckId: String? {
        decks.first?.deckId
    }

    private var isScheduledNewWordsMode: Bool {
        decks.first?.newWordsMode == "scheduled"
    }

    private var availableNewInPool: Int {
        guard let deckId = activeDeckId, let deck = decks.first else { return 0 }
        let maxIndex = deck.unlockedWordCount
        return allCards.filter { $0.deckId == deckId && $0.status == "new" && $0.wordIndex < maxIndex }.count
    }

    private var accumulatedNewWordsCount: Int {
        guard let deck = decks.first else { return 0 }
        guard availableNewInPool > 0 else { return 0 }
        let drainDate = deck.lastNewWordsDrainDate ?? deck.lastSeedDate ?? Date.distantPast
        let elapsedHours = Date().timeIntervalSince(drainDate) / 3600
        let accumulated = Int(elapsedHours * Double(deck.newWordsAccumulationRate))
        return min(max(accumulated, 0), availableNewInPool)
    }

    private var freeModeBatchSize: Int {
        guard let deck = decks.first else { return 0 }
        return min(deck.dailyNewCardLimit, availableNewInPool)
    }

    private var learnEnabled: Bool {
        if !isScheduledNewWordsMode {
            return availableNewInPool > 0
        }
        return accumulatedNewWordsCount > 0
    }

    private var learnSubtitle: String {
        guard decks.first != nil else { return "No deck" }
        if !isScheduledNewWordsMode {
            // Free mode: always available
            if availableNewInPool == 0 { return "All words introduced" }
            return "\(freeModeBatchSize) new words available"
        }
        // Scheduled mode: accumulation
        if availableNewInPool == 0 { return "All words introduced" }
        if accumulatedNewWordsCount == 0 { return "Accumulating..." }
        return "\(accumulatedNewWordsCount) new words ready"
    }

    private var unlockedLearnedCount: Int {
        guard let deckId = activeDeckId, let deck = decks.first else { return 0 }
        let maxIndex = deck.unlockedWordCount
        return allCards.filter { $0.deckId == deckId && $0.status != "new" && $0.wordIndex < maxIndex }.count
    }

    private var shouldShowExpansionPrompt: Bool {
        guard let deck = decks.first else { return false }
        let unlocked = deck.unlockedWordCount
        guard unlocked < deck.totalWords else { return false }
        return Double(unlockedLearnedCount) / Double(unlocked) >= 0.8
    }

    private var learnedCardCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        return allCards.filter { $0.deckId == deckId && $0.status != "new" }.count
    }

    private var dueReviewCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        let now = Date()
        return allCards.filter {
            $0.deckId == deckId && $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= now
        }.count
    }

    private var reviewSubtitle: String {
        if learnedCardCount == 0 { return "No words learned yet" }
        if dueReviewCount == 0 { return "No cards due" }
        return "\(dueReviewCount) cards due"
    }

    var body: some View {
        NavigationStack {
            if let viewModel {
                sessionView(viewModel: viewModel)
            } else {
                modeSelectionView
            }
        }
    }

    // MARK: - Mode Selection

    private var modeSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("StudyIconLarge")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.blue)

            Text("Ready to Study?")
                .font(.title.bold())

            VStack(spacing: 12) {
                // Learn
                Button {
                    let vm = StudySessionViewModel()
                    if let deckId = activeDeckId {
                        let count = isScheduledNewWordsMode ? accumulatedNewWordsCount : freeModeBatchSize
                        vm.loadLearnSession(
                            deckId: deckId,
                            scheduled: isScheduledNewWordsMode,
                            accumulatedCount: count,
                            context: modelContext
                        )
                    }
                    viewModel = vm
                } label: {
                    modeButtonLabel(
                        icon: learnEnabled ? "sparkles" : "lock.fill",
                        title: "Learn New Words",
                        subtitle: learnSubtitle
                    )
                }
                .buttonStyle(GlowButtonStyle(
                    baseColor: learnEnabled ? .blue : .gray,
                    disabled: !learnEnabled
                ))
                .disabled(!learnEnabled)

                // Review
                Button {
                    let vm = StudySessionViewModel()
                    if let deckId = activeDeckId {
                        vm.loadReviewSession(deckId: deckId, cardDirection: decks.first?.cardDirection ?? "source_first", context: modelContext)
                    }
                    viewModel = vm
                } label: {
                    modeButtonLabel(
                        icon: dueReviewCount > 0 ? "arrow.clockwise" : "lock.fill",
                        title: "Review",
                        subtitle: reviewSubtitle
                    )
                }
                .buttonStyle(GlowButtonStyle(
                    baseColor: dueReviewCount > 0 ? .orange : .gray,
                    disabled: dueReviewCount == 0
                ))
                .disabled(dueReviewCount == 0)
            }
            .padding(.horizontal)

            if let deck = decks.first {
                tierProgressView(deck: deck)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle("")
    }

    private func tierProgressView(deck: DeckMetadata) -> some View {
        let unlocked = deck.unlockedWordCount
        let progress = unlocked > 0 ? Double(unlockedLearnedCount) / Double(unlocked) : 0
        let nextBatch = min(500, deck.totalWords - unlocked)

        return VStack(spacing: 8) {
            HStack {
                Text("\(unlockedLearnedCount) / \(unlocked) words learned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .tint(progress >= 0.8 ? .green : .blue)

            if shouldShowExpansionPrompt {
                Button {
                    deck.unlockedWordCount = min(unlocked + nextBatch, deck.totalWords)
                    try? modelContext.save()
                } label: {
                    HStack {
                        Image(systemName: "lock.open.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock \(nextBatch) More Words")
                                .fontWeight(.semibold)
                            Text("You've learned \(Int(progress * 100))% of your current set!")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    private func modeButtonLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Image(systemName: "chevron.right")
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Session View

    @ViewBuilder
    private func sessionView(viewModel: StudySessionViewModel) -> some View {
        Group {
            if viewModel.isSessionComplete {
                sessionCompleteView(viewModel: viewModel)
            } else if let card = viewModel.currentCard {
                cardView(card: card, viewModel: viewModel)
            } else {
                emptyStateView
            }
        }
        .navigationTitle(sessionTitle(for: viewModel.mode))
        .toolbar {
            if !viewModel.sessionCards.isEmpty && !viewModel.isSessionComplete {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.sessionProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    self.viewModel = nil
                }
            }
        }
    }

    private func sessionTitle(for mode: StudyMode) -> String {
        switch mode {
        case .learn: return "Learn"
        case .review: return "Review"
        }
    }

    @ViewBuilder
    private func cardView(card: FlashCard, viewModel: StudySessionViewModel) -> some View {
        let deckMeta = decks.first
        VStack(spacing: 0) {
            FlashCardView(
                sourceText: card.sourceText,
                targetText: card.targetText,
                sourceLanguage: deckMeta?.sourceLanguage ?? "English",
                targetLanguage: deckMeta?.targetLanguage ?? "Spanish",
                status: card.status,
                article: card.article,
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
                learnButtons(viewModel: viewModel)
            } else {
                VStack(spacing: 12) {
                    reviewButtons(viewModel: viewModel)
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

    private func learnButtons(viewModel: StudySessionViewModel) -> some View {
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

    private func reviewButtons(viewModel: StudySessionViewModel) -> some View {
        HStack(spacing: 16) {
            Button {
                submitWithFeedback(quality: 1, viewModel: viewModel)
            } label: {
                Label("Nope", systemImage: "xmark.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(GlowButtonStyle(baseColor: .red))

            Button {
                submitWithFeedback(quality: 4, viewModel: viewModel)
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

    private func submitWithFeedback(quality: Int, viewModel: StudySessionViewModel) {
        let correct = quality >= 3
        // Haptic
        if correct {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        // Flash
        ratingFlash = correct ? .correct : .incorrect
        // Submit after brief flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.submitRating(quality, context: modelContext)
            }
            // Clear flash after card advances
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ratingFlash = nil
            }
        }
    }

    // MARK: - Session Complete

    private func sessionCompleteView(viewModel: StudySessionViewModel) -> some View {
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

            Button("Back to Study") {
                self.viewModel = nil
            }
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

            Button("Back") {
                viewModel = nil
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
    }
}

// MARK: - Rating Flash

private enum RatingFlash {
    case correct, incorrect
}

// MARK: - Glow Button Style

struct GlowButtonStyle: ButtonStyle {
    let baseColor: Color
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                ZStack {
                    LinearGradient(
                        colors: disabled
                            ? [.gray.opacity(0.5), .gray.opacity(0.3)]
                            : [baseColor, baseColor.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    // Subtle top shine
                    if !disabled {
                        VStack {
                            Color.white.opacity(0.15)
                                .frame(height: 20)
                                .blur(radius: 4)
                            Spacer()
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(
                color: disabled ? .clear : baseColor.opacity(0.35),
                radius: configuration.isPressed ? 2 : 8,
                y: configuration.isPressed ? 1 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
