import SwiftUI
import SwiftData

struct DebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @Query private var allCards: [FlashCard]
    @State private var confirmAction: ConfirmAction?
    @State private var notificationStatus: String = "Tap to check"
    @State private var showStartup = false

    private var activeDeckId: String? { decks.first?.deckId }
    private var deck: DeckMetadata? { decks.first }

    private var newCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        return allCards.filter { $0.deckId == deckId && $0.status == "new" }.count
    }

    private var learningCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        return allCards.filter { $0.deckId == deckId && $0.status == "learning" }.count
    }

    private var masteredCount: Int {
        guard let deckId = activeDeckId else { return 0 }
        return allCards.filter { $0.deckId == deckId && $0.status == "mastered" }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                deckStateSection
                stateManipulationSection
                seedingSection
                notificationsSection
                uiSection
                dangerZoneSection
            }
            .navigationTitle("Debug")
            .enhancedDarkContrast()
            .fullScreenCover(isPresented: $showStartup) {
                StartupView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                showStartup = false
                            }
                        }
                    }
            }
            .alert(
                    confirmAction?.title ?? "",
                    isPresented: Binding(
                        get: { confirmAction != nil },
                        set: { if !$0 { confirmAction = nil } }
                    )
                ) {
                    Button("Confirm", role: .destructive) { confirmAction?.perform(); confirmAction = nil }
                    Button("Cancel", role: .cancel) { confirmAction = nil }
                } message: {
                    Text(confirmAction?.message ?? "")
                }
        }
    }

    // MARK: - Deck State

    private var deckStateSection: some View {
        Section("Deck State") {
            if let deck {
                LabeledContent("JSON Version", value: "\(deck.jsonVersion)")
                LabeledContent("Total Words", value: "\(deck.totalWords)")
                LabeledContent("Unlocked", value: "\(deck.unlockedWordCount)")
                LabeledContent("Cards in DB", value: "\(allCards.count)")
                HStack {
                    Label("\(newCount)", systemImage: "circle")
                        .foregroundStyle(.blue)
                    Label("\(learningCount)", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                    Label("\(masteredCount)", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
                .font(.caption)
                if let seedDate = deck.lastSeedDate {
                    LabeledContent("Last Seeded", value: seedDate.formatted(.dateTime.month().day().hour().minute()))
                }
            } else {
                Text("No deck loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - State Manipulation

    private var stateManipulationSection: some View {
        Section("State Manipulation") {
            Button("Reset All Cards to New") {
                confirmAction = ConfirmAction(
                    title: "Reset All Cards?",
                    message: "This will reset all \(allCards.count) cards to 'new' status, clearing all SR progress and review history."
                ) {
                    resetAllCards()
                }
            }
            .foregroundStyle(.orange)

            Button("Simulate 50 Learned Cards") {
                simulateLearnedCards(count: 50)
            }

            Button("Simulate 200 Learned Cards") {
                simulateLearnedCards(count: 200)
            }

            Button("Make 10 Cards Due Now") {
                makeDueNow(count: 10)
            }

            Button("Reset Daily Counters") {
                resetDailyCounters()
            }
        }
    }

    // MARK: - Seeding

    private var seedingSection: some View {
        Section {
            Button("Force Re-Seed (Deck Expansion)") {
                forceReseed()
            }
        } header: {
            Text("Seeding & Expansion")
        } footer: {
            Text("Adds any new words from the JSON without resetting progress. Simulates what happens when a user gets an app update with more words.")
        }
    }

    // MARK: - Danger Zone

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            LabeledContent("Status", value: notificationStatus)

            Button("Check Notification Status") {
                NotificationManager.shared.checkStatus { status in
                    notificationStatus = status
                }
            }

            Button("Send Test Notification (3s)") {
                NotificationManager.shared.sendTestNotification()
            }

            Button("Reschedule All Notifications") {
                NotificationManager.shared.rescheduleNotifications(context: modelContext)
                NotificationManager.shared.checkStatus { status in
                    notificationStatus = status
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Test notification fires in 3 seconds. If in foreground, it shows as a banner.")
        }
    }

    // MARK: - UI

    private var uiSection: some View {
        Section("UI") {
            Button("Play Startup Animation") {
                showStartup = true
            }
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button("Delete All Data (Fresh Install)") {
                confirmAction = ConfirmAction(
                    title: "Delete Everything?",
                    message: "This deletes ALL cards, review history, and deck metadata. The app will re-seed on next launch as if freshly installed."
                ) {
                    deleteAllData()
                }
            }
            .foregroundStyle(.red)
        } header: {
            Text("Danger Zone")
        }
    }

    // MARK: - Actions

    private func resetAllCards() {
        for card in allCards {
            card.status = "new"
            card.introducedDate = nil
            card.easeFactor = 2.5
            card.interval = 0
            card.repetitionCount = 0
            card.nextReviewDate = nil
            card.lastReviewDate = nil
            card.totalReviews = 0
            card.totalCorrect = 0
            card.currentStreak = 0
            card.longestStreak = 0
            for record in card.reviewHistory {
                modelContext.delete(record)
            }
            card.reviewHistory = []
        }
        try? modelContext.save()
    }

    private func simulateLearnedCards(count: Int) {
        guard let deckId = activeDeckId else { return }
        let newCards = allCards
            .filter { $0.deckId == deckId && $0.status == "new" }
            .sorted { $0.wordIndex < $1.wordIndex }
            .prefix(count)

        let calendar = Calendar.current
        let now = Date()
        let direction = deck?.cardDirection ?? "source_first"

        for card in newCards {
            // Simulate a realistic learning journey over the past few weeks
            // Each card gets 3-8 reviews spread over time
            let totalSessions = Int.random(in: 3...8)
            // Harder words (higher frequencyRank) fail more often
            let failRate = min(0.4, Double(card.frequencyRank) / 10000.0 + 0.05)

            // Start date: random day in the past 7-30 days
            let daysAgo = Int.random(in: 7...30)
            guard let introducedDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }

            card.introducedDate = introducedDate
            card.easeFactor = 2.5
            card.interval = 0
            card.repetitionCount = 0
            card.totalReviews = 0
            card.totalCorrect = 0
            card.currentStreak = 0
            card.longestStreak = 0

            var reviewDate = introducedDate
            var prevInterval = 0
            var prevEF = 2.5

            for session in 0..<totalSessions {
                // First review is more likely wrong; later reviews more likely correct
                let sessionFailBoost = session == 0 ? 0.2 : 0.0
                let correct = Double.random(in: 0...1) > (failRate + sessionFailBoost)
                let quality = correct ? Int.random(in: 3...5) : Int.random(in: 1...2)

                let result = SpacedRepetitionEngine.processReview(
                    currentInterval: card.interval,
                    currentEaseFactor: card.easeFactor,
                    currentRepetitionCount: card.repetitionCount,
                    currentStatus: card.status,
                    quality: quality
                )

                // Response time: 1.5-8s, faster for easier/later reviews
                let baseTime = correct ? Double.random(in: 1.5...4.0) : Double.random(in: 3.0...8.0)
                let responseTime = max(1.0, baseTime - Double(session) * 0.2)

                // Match the deck's card direction setting
                let reviewDirection: String
                switch direction {
                case "target_first":
                    reviewDirection = "target_to_source"
                case "mixed":
                    reviewDirection = Bool.random() ? "source_to_target" : "target_to_source"
                default:
                    reviewDirection = "source_to_target"
                }

                let record = ReviewRecord(
                    card: card,
                    reviewDate: reviewDate,
                    quality: quality,
                    wasCorrect: correct,
                    previousInterval: prevInterval,
                    newInterval: result.newInterval,
                    previousEaseFactor: prevEF,
                    newEaseFactor: result.newEaseFactor,
                    studyMode: "free_review",
                    responseTimeSeconds: responseTime,
                    cardDirection: reviewDirection
                )
                modelContext.insert(record)

                prevInterval = card.interval
                prevEF = card.easeFactor

                card.interval = result.newInterval
                card.easeFactor = result.newEaseFactor
                card.repetitionCount = result.newRepetitionCount
                card.status = result.newStatus
                card.lastReviewDate = reviewDate
                card.totalReviews += 1
                if correct {
                    card.totalCorrect += 1
                    card.currentStreak += 1
                    card.longestStreak = max(card.longestStreak, card.currentStreak)
                } else {
                    card.currentStreak = 0
                }

                // Next review: advance by the interval (or 1 day if lapsed)
                let advance = max(1, result.newInterval)
                // Add some jitter so not all reviews land on the same day
                let jitter = Int.random(in: 0...1)
                guard let next = calendar.date(byAdding: .day, value: advance + jitter, to: reviewDate) else { break }
                reviewDate = min(next, now) // don't go past today

                if reviewDate >= now { break }
            }

            // Set next review date based on final state
            if card.interval > 0 {
                card.nextReviewDate = calendar.date(byAdding: .day, value: card.interval, to: card.lastReviewDate ?? now)
            } else {
                card.nextReviewDate = now // lapsed, due now
            }
        }
        try? modelContext.save()
    }

    private func makeDueNow(count: Int) {
        guard let deckId = activeDeckId else { return }
        let learningCards = allCards
            .filter { $0.deckId == deckId && $0.status != "new" && $0.interval > 0 }
            .prefix(count)

        let past = Date().addingTimeInterval(-3600)
        for card in learningCards {
            card.nextReviewDate = past
        }
        try? modelContext.save()
    }

    private func resetDailyCounters() {
        guard let deck else { return }
        deck.lastNewWordsDrainDate = nil
        try? modelContext.save()
    }

    private func forceReseed() {
        guard let deck else { return }
        deck.jsonVersion = 0
        try? modelContext.save()
        DataLoader.seedIfNeeded(container: modelContext.container)
    }

    private func deleteAllData() {
        for card in allCards {
            modelContext.delete(card)
        }
        for deck in decks {
            modelContext.delete(deck)
        }
        try? modelContext.save()
    }
}

// MARK: - Confirm Action

private struct ConfirmAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let perform: () -> Void
}
