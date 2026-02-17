import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @State private var showingResetAlert = false
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var notificationStatus: String?

    private var activeDeck: DeckMetadata? {
        decks.first
    }

    var body: some View {
        NavigationStack {
            Form {
                if let deck = activeDeck {
                    Section("Active Deck") {
                        LabeledContent("Total Words") {
                            Text("\(deck.totalWords)")
                        }

                        Toggle(isOn: Binding(
                            get: { deck.showTargetFirst },
                            set: { deck.showTargetFirst = $0 }
                        )) {
                            VStack(alignment: .leading) {
                                Text("Card Direction")
                                Text(deck.showTargetFirst
                                     ? "\(deck.targetLanguage) → \(deck.sourceLanguage)"
                                     : "\(deck.sourceLanguage) → \(deck.targetLanguage)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Daily New Cards") {
                        Stepper(
                            "\(deck.dailyNewCardLimit) cards per day",
                            value: Binding(
                                get: { deck.dailyNewCardLimit },
                                set: { deck.dailyNewCardLimit = $0 }
                            ),
                            in: 1...30
                        )
                    }

                    Section("Review Mode") {
                        Picker("Mode", selection: Binding(
                            get: { deck.reviewMode },
                            set: { deck.reviewMode = $0 }
                        )) {
                            Text("Free Review").tag("free")
                            Text("Scheduled Review").tag("scheduled")
                        }
                        .pickerStyle(.segmented)

                        if deck.reviewMode == "free" {
                            Text("Words accumulate for review over time.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Review is locked until the scheduled interval passes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if deck.reviewMode == "free" {
                        Section("Accumulation Rate") {
                            Stepper(
                                "\(deck.reviewAccumulationRate) words per hour",
                                value: Binding(
                                    get: { deck.reviewAccumulationRate },
                                    set: { deck.reviewAccumulationRate = $0 }
                                ),
                                in: 1...5
                            )
                        }
                    }

                    if deck.reviewMode == "scheduled" {
                        Section("Scheduled Review") {
                            Picker("Review every", selection: Binding(
                                get: { deck.scheduledReviewIntervalMinutes },
                                set: {
                                    deck.scheduledReviewIntervalMinutes = $0
                                    NotificationManager.shared.rescheduleNotifications(context: modelContext)
                                }
                            )) {
                                Text("30 minutes").tag(30)
                                Text("1 hour").tag(60)
                                Text("2 hours").tag(120)
                                Text("3 hours").tag(180)
                                Text("4 hours").tag(240)
                                Text("6 hours").tag(360)
                                Text("8 hours").tag(480)
                            }
                        }
                    }

                    Section("Appearance") {
                        Picker("Theme", selection: $appearance) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Notifications") {
                        Button("Enable Notifications") {
                            let center = UNUserNotificationCenter.current()
                            center.getNotificationSettings { settings in
                                DispatchQueue.main.async {
                                    switch settings.authorizationStatus {
                                    case .notDetermined:
                                        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                                            DispatchQueue.main.async {
                                                if granted {
                                                    notificationStatus = "granted"
                                                    NotificationManager.shared.rescheduleNotifications(context: modelContext)
                                                } else {
                                                    notificationStatus = "denied"
                                                }
                                            }
                                        }
                                    case .denied:
                                        if let url = URL(string: UIApplication.openSettingsURLString) {
                                            UIApplication.shared.open(url)
                                        }
                                    case .authorized, .provisional, .ephemeral:
                                        notificationStatus = "already"
                                        NotificationManager.shared.rescheduleNotifications(context: modelContext)
                                    @unknown default:
                                        break
                                    }
                                }
                            }
                        }

                        if let notificationStatus {
                            switch notificationStatus {
                            case "granted":
                                Text("Notifications enabled!")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            case "denied":
                                Text("Notifications denied. Opening Settings...")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            case "already":
                                Text("Notifications already enabled!")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            default:
                                EmptyView()
                            }
                        }
                    }

                    Section {
                        Button("Reset All Progress", role: .destructive) {
                            showingResetAlert = true
                        }
                    }
                } else {
                    Section {
                        Text("No deck loaded. Restart the app to load word data.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("")
            .enhancedDarkContrast()
            .alert("Reset Progress", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetProgress()
                }
            } message: {
                Text("This will reset all your learning progress. Your word data will be preserved, but all cards will return to 'new' status. This cannot be undone.")
            }
        }
    }

    private func resetProgress() {
        let descriptor = FetchDescriptor<FlashCard>()
        guard let cards = try? modelContext.fetch(descriptor) else { return }

        for card in cards {
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
        }

        // Delete all review records
        let reviewDescriptor = FetchDescriptor<ReviewRecord>()
        if let reviews = try? modelContext.fetch(reviewDescriptor) {
            for review in reviews {
                modelContext.delete(review)
            }
        }

        try? modelContext.save()
    }
}
