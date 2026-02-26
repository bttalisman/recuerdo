import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var showStartup = true
    @State private var selectedTab = 0
    @State private var loadedTabs: Set<Int> = [0]

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            mainContent
                .opacity(showStartup ? 0 : 1)

            if showStartup {
                StartupView {
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
    ContentView()
        .modelContainer(for: [FlashCard.self, ReviewRecord.self, DeckMetadata.self], inMemory: true)
}
