import SwiftUI
import SwiftData

struct StudySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: StudySessionViewModel?
    @Query(filter: #Predicate<DeckMetadata> { _ in true })
    private var decks: [DeckMetadata]
    @Query private var allCards: [FlashCard]

    private var activeDeckId: String? {
        decks.first?.deckId
    }

    private var newCardCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let introducedToday = allCards.filter {
            $0.deckId == deckId && $0.introducedDate != nil && $0.introducedDate! >= startOfToday
        }.count
        let limit = decks.first?.dailyNewCardLimit ?? 10
        let remaining = max(0, limit - introducedToday)
        let availableNew = allCards.filter { $0.deckId == deckId && $0.status == "new" }.count
        return min(remaining, availableNew)
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

    private var isScheduledMode: Bool {
        decks.first?.reviewMode == "scheduled"
    }

    private var accumulatedReviewCount: Int {
        guard let deck = decks.first else { return 0 }
        guard learnedCardCount > 0 else { return 0 }
        let drainDate = deck.lastReviewDrainDate ?? deck.lastSeedDate ?? Date.distantPast
        let elapsedHours = Date().timeIntervalSince(drainDate) / 3600
        let accumulated = Int(elapsedHours * Double(deck.reviewAccumulationRate))
        return min(max(accumulated, 0), learnedCardCount)
    }

    private var reviewEnabled: Bool {
        if !isScheduledMode {
            return accumulatedReviewCount > 0
        }
        // Scheduled mode: need due cards + interval elapsed
        guard dueReviewCount > 0 else { return false }
        guard let deck = decks.first else { return false }
        guard let lastReview = deck.lastScheduledReviewDate else { return true }
        let nextAllowed = lastReview.addingTimeInterval(Double(deck.scheduledReviewIntervalMinutes) * 60)
        return Date() >= nextAllowed
    }

    private var reviewSubtitle: String {
        guard decks.first != nil else { return "No deck" }
        if !isScheduledMode {
            if learnedCardCount == 0 { return "No words learned yet" }
            if accumulatedReviewCount == 0 { return "Accumulating..." }
            return "\(accumulatedReviewCount) words ready"
        }
        // Scheduled mode
        if dueReviewCount == 0 { return "No cards due" }
        guard let deck = decks.first,
              let lastReview = deck.lastScheduledReviewDate else {
            return "\(dueReviewCount) cards due"
        }
        let nextAllowed = lastReview.addingTimeInterval(Double(deck.scheduledReviewIntervalMinutes) * 60)
        if Date() >= nextAllowed {
            return "\(dueReviewCount) cards due"
        }
        let remaining = nextAllowed.timeIntervalSince(Date())
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "Available in \(hours)h \(minutes)m"
        }
        return "Available in \(minutes)m"
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
                        vm.loadLearnSession(deckId: deckId, context: modelContext)
                    }
                    viewModel = vm
                } label: {
                    modeButtonLabel(
                        icon: "sparkles",
                        title: "Learn New Words",
                        subtitle: "\(newCardCount) new words available"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(newCardCount == 0)

                // Review
                Button {
                    let vm = StudySessionViewModel()
                    if let deckId = activeDeckId {
                        vm.loadReviewSession(deckId: deckId, scheduled: isScheduledMode, accumulatedCount: accumulatedReviewCount, showTargetFirst: decks.first?.showTargetFirst ?? false, context: modelContext)
                    }
                    viewModel = vm
                } label: {
                    modeButtonLabel(
                        icon: reviewEnabled ? "arrow.clockwise" : "lock.fill",
                        title: "Review",
                        subtitle: reviewSubtitle
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(reviewEnabled ? .orange : .gray)
                .disabled(!reviewEnabled)
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("")
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

            if viewModel.mode == .learn {
                learnButtons(viewModel: viewModel)
            } else {
                VStack(spacing: 12) {
                    if viewModel.isFlipped {
                        reviewButtons(viewModel: viewModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .animation(.easeInOut(duration: 0.3), value: viewModel.isFlipped)
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
                viewModel.endLearnSession()
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
