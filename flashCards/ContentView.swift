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
                StartupView()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                            withAnimation(.easeOut(duration: 0.8)) {
                                showStartup = false
                            }
                        }
                    }
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
