import SwiftUI
import SwiftData

struct StudySessionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: StudySessionViewModel?
    @State private var justUnlocked = false
    @State private var showCategoryBrowser = false
    @State private var showPremiumGate = false
    private var isPremium: Bool { PremiumManager.shared.isPremium }
    @Query(filter: #Predicate<DeckMetadata> { _ in true })
    private var decks: [DeckMetadata]
    @Query private var allCards: [FlashCard]

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
        let alreadyDrainedToday = Calendar.current.isDateInToday(drainDate)
        if alreadyDrainedToday { return 0 }
        return min(deck.newWordsAccumulationRate, availableNewInPool)
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
        // Scheduled mode: daily batch
        if availableNewInPool == 0 { return "All words introduced" }
        if accumulatedNewWordsCount == 0 { return "Today's words done — come back tomorrow" }
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
            modeSelectionView
        }
        .fullScreenCover(item: $viewModel) { (vm: StudySessionViewModel) in
            NavigationStack {
                sessionView(viewModel: vm)
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
                .accessibilityHidden(true)

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
                .accessibilityLabel("Learn new words")
                .accessibilityHint(learnSubtitle)

                // Review
                Button {
                    let vm = StudySessionViewModel()
                    if let deckId = activeDeckId {
                        vm.loadReviewSession(deckId: deckId, cardDirection: "source_first", context: modelContext)
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
                .accessibilityLabel("Review")
                .accessibilityHint(reviewSubtitle)

                // Categories
                Button {
                    if isPremium {
                        showCategoryBrowser = true
                    } else {
                        showPremiumGate = true
                    }
                } label: {
                    modeButtonLabel(
                        icon: "tag.fill",
                        title: "Study by Category",
                        subtitle: "Pick a topic to learn"
                    )
                }
                .buttonStyle(GlowButtonStyle(baseColor: .purple))
                .accessibilityLabel("Study by category")
                .accessibilityHint("Pick a topic to learn")
            }
            .padding(.horizontal)

            if let deck = decks.first {
                tierProgressView(deck: deck)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .navigationTitle("")
        .sheet(isPresented: $showCategoryBrowser) {
            CategoryBrowserView { vm in
                viewModel = vm
            }
        }
        .sheet(isPresented: $showPremiumGate) {
            PremiumGateView(
                feature: "Study by Category",
                description: "Focus on topics that matter to you — travel, food, work, and more. Learn words by category instead of frequency order."
            )
        }
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
                .accessibilityLabel("Learning progress")
                .accessibilityValue("\(Int(progress * 100)) percent")

            if shouldShowExpansionPrompt && !justUnlocked {
                if isPremium {
                    Button {
                        deck.unlockedWordCount = min(unlocked + nextBatch, deck.totalWords)
                        try? modelContext.save()
                        justUnlocked = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.open.fill")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unlock \(nextBatch) More Words")
                                    .fontWeight(.semibold)
                                Text("You've learned \(Int(progress * 100))% of your current set!")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .accessibilityHidden(true)
                        }
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button {
                        showPremiumGate = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.fill")
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Unlock More Words")
                                    .fontWeight(.semibold)
                                Text("Get Recuerdo Premium to expand beyond \(unlocked) words")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .accessibilityHidden(true)
                        }
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
    }

    private func modeButtonLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Session View

    @ViewBuilder
    private func sessionView(viewModel: StudySessionViewModel) -> some View {
        ReviewSessionView(
            viewModel: viewModel,
            title: viewModel.mode == .learn ? "Learn" : "Review",
            backLabel: "Back to Study",
            onDismiss: { self.viewModel = nil }
        )
    }

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
