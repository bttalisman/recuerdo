import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @State private var showStartup = true

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
                    withAnimation(.easeIn(duration: 0.5)) {
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
        TabView {
            StudySessionView()
                .tabItem {
                    Label("Study", image: "StudyIcon")
                }

            WordListView()
                .tabItem {
                    Label("Words", systemImage: "book")
                }

            ProgressDashboardView()
                .tabItem {
                    Label("Progress", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }

            DebugView()
                .tabItem {
                    Label("Debug", systemImage: "ant")
                }
        }
        .preferredColorScheme(colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FlashCard.self, ReviewRecord.self, DeckMetadata.self], inMemory: true)
}
