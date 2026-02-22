import SwiftUI
import SwiftData

struct CategoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var decks: [DeckMetadata]
    @State private var searchText = ""
    @State private var wordCount: Int = 10
    @State private var categories: [(name: String, total: Int, learned: Int)] = []
    @State private var subcategoryCache: [String: [(name: String, total: Int, learned: Int)]] = [:]
    @State private var expandedCategory: String?

    let onStartSession: (StudySessionViewModel) -> Void

    private var deckId: String {
        decks.first?.deckId ?? ""
    }

    private var filteredCategories: [(name: String, total: Int, learned: Int)] {
        if searchText.isEmpty { return categories }
        let q = searchText.lowercased()
        return categories.filter { cat in
            if cat.name.lowercased().contains(q) { return true }
            let subs = subcategoryCache[cat.name] ?? []
            return subs.contains { $0.name.lowercased().contains(q) }
        }
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
                    if categories.isEmpty {
                        ProgressView("Loading categories...")
                    } else if filteredCategories.isEmpty {
                        Text("No categories found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredCategories, id: \.name) { category in
                            categoryRow(category)
                        }
                    }
                } header: {
                    if !categories.isEmpty {
                        Text("\(categories.count) Categories")
                    }
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
            .task {
                let (cats, subs) = CardScheduler.allCategoriesWithSubcategories(deckId: deckId, context: modelContext)
                categories = cats
                subcategoryCache = subs
            }
        }
    }

    /// Visible subcategories: when searching, only show matching subs; otherwise show all when expanded.
    private func visibleSubs(for category: (name: String, total: Int, learned: Int)) -> [(name: String, total: Int, learned: Int)] {
        let subs = subcategoryCache[category.name] ?? []
        guard subs.count > 1 else { return [] }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            let parentMatches = category.name.lowercased().contains(q)
            if parentMatches {
                // Parent name matched — show all subs when expanded normally
                return expandedCategory == category.name ? subs : []
            }
            // Parent didn't match — we got here via subcategory match, auto-show matching subs
            return subs.filter { $0.name.lowercased().contains(q) }
        }

        return expandedCategory == category.name ? subs : []
    }

    /// Whether subcategories are showing (either manually expanded or auto-expanded by search).
    private func isShowingSubs(for category: (name: String, total: Int, learned: Int)) -> Bool {
        let subs = subcategoryCache[category.name] ?? []
        guard subs.count > 1 else { return false }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            if !category.name.lowercased().contains(q) {
                // Matched via subcategory — always show expanded
                return true
            }
        }

        return expandedCategory == category.name
    }

    @ViewBuilder
    private func categoryRow(_ category: (name: String, total: Int, learned: Int)) -> some View {
        let subs = subcategoryCache[category.name] ?? []
        let hasSubcategories = subs.count > 1
        let expanded = isShowingSubs(for: category)
        let displayedSubs = visibleSubs(for: category)

        // Parent row
        HStack {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(hasSubcategories ? Color.secondary : Color.clear)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name.capitalized)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(category.learned) of \(category.total) learned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                startSession(category: category.name)
            } label: {
                Label("Study", systemImage: "play.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if hasSubcategories {
                withAnimation {
                    expandedCategory = expandedCategory == category.name ? nil : category.name
                }
            } else {
                startSession(category: category.name)
            }
        }

        // Subcategory rows
        if !displayedSubs.isEmpty {
            ForEach(displayedSubs, id: \.name) { sub in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.name.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Text("\(sub.learned) of \(sub.total) learned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        if sub.name == "general" {
                            startSession(category: category.name)
                        } else {
                            startSession(category: "\(category.name)/\(sub.name)")
                        }
                    } label: {
                        Label("Study", systemImage: "play.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.leading, 28)
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
