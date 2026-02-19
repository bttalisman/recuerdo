import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @State private var showingResetAlert = false
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("isPremium") private var isPremium: Bool = false
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

                        directionRow(deck: deck, label: "\(deck.sourceLanguage) → \(deck.targetLanguage)", value: "source_first")
                        directionRow(deck: deck, label: "\(deck.targetLanguage) → \(deck.sourceLanguage)", value: "target_first")
                        directionRow(deck: deck, label: "Mix It Up!", value: "mixed")
                    }

                    Section("New Words Mode") {
                        HStack {
                            modeButton(deck: deck, label: "Free", value: "free")
                            modeButton(deck: deck, label: "Scheduled", value: "scheduled")
                        }

                        if deck.newWordsMode == "free" {
                            Text("Learn new words anytime you want.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Stepper(
                                "\(deck.dailyNewCardLimit) words per session",
                                value: Binding(
                                    get: { deck.dailyNewCardLimit },
                                    set: { deck.dailyNewCardLimit = $0 }
                                ),
                                in: 1...30
                            )
                        } else {
                            Text("A fresh batch of new words arrives each day.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Stepper(
                                "\(deck.newWordsAccumulationRate) words per day",
                                value: Binding(
                                    get: { deck.newWordsAccumulationRate },
                                    set: { deck.newWordsAccumulationRate = $0 }
                                ),
                                in: 1...50
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
                        Text("New words are introduced, most common first. Expand this pool as you progress.")
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

                    Section {
                        Toggle("Review Reminders", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { _, enabled in
                                if enabled {
                                    requestNotificationPermission()
                                } else {
                                    NotificationManager.shared.cancelAll()
                                }
                            }

                        if let notificationStatus {
                            Text(notificationStatus)
                                .font(.caption)
                                .foregroundStyle(notificationStatus.contains("denied") ? .orange : .green)
                        }
                    } header: {
                        Text("Notifications")
                    } footer: {
                        Text("Get notified at 9 AM, 1 PM, and 6 PM when you have words ready for review.")
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
                        NavigationLink {
                            AboutView()
                        } label: {
                            Label("About Chispa", systemImage: "info.circle")
                        }
                    }

                    Section("Developer") {
                        Toggle("Premium Enabled", isOn: $isPremium)
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

    private func modeButton(deck: DeckMetadata, label: String, value: String) -> some View {
        Button {
            deck.newWordsMode = value
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(deck.newWordsMode == value ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(deck.newWordsMode == value ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func directionRow(deck: DeckMetadata, label: String, value: String) -> some View {
        Button {
            deck.cardDirection = value
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if deck.cardDirection == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            if granted {
                                notificationStatus = "Notifications enabled!"
                                NotificationManager.shared.rescheduleNotifications(context: modelContext)
                            } else {
                                notificationsEnabled = false
                                notificationStatus = "Notifications denied — enable in Settings app."
                            }
                        }
                    }
                case .denied:
                    notificationsEnabled = false
                    notificationStatus = "Notifications denied — enable in Settings app."
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                case .authorized, .provisional, .ephemeral:
                    NotificationManager.shared.rescheduleNotifications(context: modelContext)
                @unknown default:
                    break
                }
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
