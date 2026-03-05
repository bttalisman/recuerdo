import SwiftUI
import SwiftData

struct ContentView: View {
    var onStartupComplete: (() -> Void)? = nil

    @AppStorage("appearance") private var appearance: String = "system"
    @State private var showStartup = true
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]
    @State private var pendingDeepLink: URL?
    @State private var quickReviewViewModel: StudySessionViewModel?

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]

    var body: some View {
        ZStack {
            if !showStartup {
                mainContent
                    .transition(.opacity)
            }

            if showStartup {
                StartupView {
                    onStartupComplete?()
                    withAnimation(.easeIn(duration: 0.3)) {
                        showStartup = false
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .preferredColorScheme(colorScheme)
        .onOpenURL { url in
            if showStartup {
                pendingDeepLink = url
            } else {
                handleDeepLink(url)
            }
        }
        .onChange(of: showStartup) { _, isShowing in
            if !isShowing, let url = pendingDeepLink {
                pendingDeepLink = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    handleDeepLink(url)
                }
            }
        }
        .fullScreenCover(item: $quickReviewViewModel) { vm in
            NavigationStack {
                ReviewSessionView(
                    viewModel: vm,
                    title: "Quick Review",
                    backLabel: "Done",
                    onDismiss: { quickReviewViewModel = nil },
                    deckMeta: decks.first
                )
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "recuerdo" else { return }
        switch url.host {
        case "study":
            selectedTab = 0
        case "quickreview":
            launchQuickReview()
        default:
            selectedTab = 0
        }
    }

    private func launchQuickReview() {
        let cardDirection = decks.first?.cardDirection ?? "source_first"

        // Fetch learning cards with low accuracy or broken streaks
        let descriptor = FetchDescriptor<FlashCard>()
        guard let allCards = try? modelContext.fetch(descriptor) else { return }

        let atRisk = allCards.filter { card in
            guard !card.isTrashed, card.status == "learning", card.totalReviews >= 3 else { return false }
            let accuracy = Double(card.totalCorrect) / Double(card.totalReviews)
            return accuracy < 0.7 || card.currentStreak == 0
        }
        .sorted { $0.easeFactor < $1.easeFactor }
        .prefix(10)

        guard !atRisk.isEmpty else {
            // Fall back to due cards if no at-risk
            let now = Date()
            let due = allCards.filter {
                !$0.isTrashed && $0.status != "new" && $0.nextReviewDate != nil && $0.nextReviewDate! <= now
            }
            .prefix(10)
            guard !due.isEmpty else { selectedTab = 0; return }
            let vm = StudySessionViewModel()
            vm.loadCustomReviewSession(cards: Array(due), cardDirection: cardDirection)
            quickReviewViewModel = vm
            return
        }

        let vm = StudySessionViewModel()
        vm.loadCustomReviewSession(cards: Array(atRisk), cardDirection: cardDirection)
        quickReviewViewModel = vm
    }

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            StudySessionView()
                .tag(0)
                .tabItem {
                    Label("Study", image: "StudyIcon")
                }

            LazyTab(isLoaded: loadedTabs.contains(1)) { WordListView() }
                .tag(1)
                .tabItem {
                    Label("Words", systemImage: "book")
                }

            LazyTab(isLoaded: loadedTabs.contains(2)) { ProgressDashboardView() }
                .tag(2)
                .tabItem {
                    Label("Progress", systemImage: "chart.bar")
                }

            LazyTab(isLoaded: loadedTabs.contains(3)) { VergeView() }
                .tag(3)
                .tabItem {
                    Label("Verge", systemImage: "flame")
                }

            LazyTab(isLoaded: loadedTabs.contains(4)) { SettingsView() }
                .tag(4)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onChange(of: selectedTab) { _, newTab in
            loadedTabs.insert(newTab)
        }
        .preferredColorScheme(colorScheme)
    }
}

/// Defers building a tab's content until the tab is first selected.
private struct LazyTab<Content: View>: View {
    let isLoaded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoaded {
            content()
        } else {
            Color.clear
        }
    }
}

#Preview {
    ContentView(onStartupComplete: nil)
        .modelContainer(for: [FlashCard.self, ReviewRecord.self, DeckMetadata.self], inMemory: true)
}
