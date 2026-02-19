import SwiftUI
import SwiftData

struct CategoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var decks: [DeckMetadata]
    @State private var searchText = ""
    @State private var wordCount: Int = 10

    let onStartSession: (StudySessionViewModel) -> Void

    private var deckId: String {
        decks.first?.deckId ?? ""
    }

    private var categories: [(name: String, total: Int, learned: Int)] {
        CardScheduler.allCategories(deckId: deckId, context: modelContext)
    }

    private var filteredCategories: [(name: String, total: Int, learned: Int)] {
        if searchText.isEmpty { return categories }
        let q = searchText.lowercased()
        return categories.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper("\(wordCount) words per session", value: $wordCount, in: 5...30, step: 5)
                } header: {
                    Text("Session Size")
                }

                Section {
                    if filteredCategories.isEmpty {
                        Text("No categories found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredCategories, id: \.name) { category in
                            Button {
                                startSession(category: category.name)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(category.name.capitalized)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("\(category.learned) of \(category.total) learned")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(category.total)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("\(categories.count) Categories")
                }
            }
            .navigationTitle("Study by Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search categories...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func startSession(category: String) {
        let cards = CardScheduler.buildCategoryLearnSession(
            deckId: deckId,
            category: category,
            limit: wordCount,
            context: modelContext
        )
        guard !cards.isEmpty else { return }

        let vm = StudySessionViewModel()
        vm.loadCategoryLearnSession(cards: cards, context: modelContext)
        dismiss()
        onStartSession(vm)
    }
}
