import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @State private var showingResetAlert = false
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var notificationStatus: String?
    @State private var showingRestoreImporter = false
    @State private var backupStatus: String?
    @State private var showingRestoreAlert = false
    @State private var pendingRestoreData: Data?

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

                        Picker("Card Direction", selection: Binding(
                            get: { deck.cardDirection },
                            set: { deck.cardDirection = $0 }
                        )) {
                            Text("\(deck.sourceLanguage) → \(deck.targetLanguage)")
                                .tag("source_first")
                            Text("\(deck.targetLanguage) → \(deck.sourceLanguage)")
                                .tag("target_first")
                            Text("Mix It Up")
                                .tag("mixed")
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("New Words Mode") {
                        Picker("Mode", selection: Binding(
                            get: { deck.newWordsMode },
                            set: { deck.newWordsMode = $0 }
                        )) {
                            Text("Free").tag("free")
                            Text("Scheduled").tag("scheduled")
                        }
                        .pickerStyle(.segmented)

                        if deck.newWordsMode == "free" {
                            Text("Learn new words anytime you want.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("New words accumulate over time at a set rate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if deck.newWordsMode == "free" {
                        Section("New Words Per Session") {
                            Stepper(
                                "\(deck.dailyNewCardLimit) words",
                                value: Binding(
                                    get: { deck.dailyNewCardLimit },
                                    set: { deck.dailyNewCardLimit = $0 }
                                ),
                                in: 1...30
                            )
                        }
                    }

                    if deck.newWordsMode == "scheduled" {
                        Section("New Words Arrive") {
                            Stepper(
                                "\(deck.newWordsAccumulationRate) words per hour",
                                value: Binding(
                                    get: { deck.newWordsAccumulationRate },
                                    set: { deck.newWordsAccumulationRate = $0 }
                                ),
                                in: 1...5
                            )
                        }
                    }

                    Section("Word Pool") {
                        Stepper(
                            "\(deck.unlockedWordCount) of \(deck.totalWords) words unlocked",
                            value: Binding(
                                get: { deck.unlockedWordCount },
                                set: { deck.unlockedWordCount = $0 }
                            ),
                            in: 100...deck.totalWords,
                            step: 100
                        )
                        Text("New words are introduced from the easiest first. Expand your pool as you progress.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                    Section("Backup & Restore") {
                        if let url = BackupManager.backupFileURL(context: modelContext) {
                            ShareLink(
                                item: url,
                                preview: SharePreview("Flashcards Backup", image: Image(systemName: "doc.text"))
                            ) {
                                Label("Export Backup", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button {
                            showingRestoreImporter = true
                        } label: {
                            Label("Restore from Backup", systemImage: "square.and.arrow.down")
                        }

                        if let backupStatus {
                            Text(backupStatus)
                                .font(.caption)
                                .foregroundStyle(backupStatus.contains("Restored") ? .green : .red)
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
            .fileImporter(
                isPresented: $showingRestoreImporter,
                allowedContentTypes: [.json],
                onCompletion: { result in
                    switch result {
                    case .success(let url):
                        guard url.startAccessingSecurityScopedResource() else {
                            backupStatus = "Could not access file."
                            return
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        guard let data = try? Data(contentsOf: url) else {
                            backupStatus = "Could not read file."
                            return
                        }
                        pendingRestoreData = data
                        showingRestoreAlert = true
                    case .failure:
                        backupStatus = "Import cancelled."
                    }
                }
            )
            .alert("Restore Backup", isPresented: $showingRestoreAlert) {
                Button("Cancel", role: .cancel) {
                    pendingRestoreData = nil
                }
                Button("Restore", role: .destructive) {
                    if let data = pendingRestoreData,
                       let result = BackupManager.restoreBackup(data: data, context: modelContext) {
                        backupStatus = "Restored \(result.cards) cards and \(result.reviews) reviews."
                    } else {
                        backupStatus = "Restore failed. Invalid backup file."
                    }
                    pendingRestoreData = nil
                }
            } message: {
                Text("This will overwrite your current progress with the backup data. This cannot be undone.")
            }
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
