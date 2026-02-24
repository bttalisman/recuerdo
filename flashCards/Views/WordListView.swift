import SwiftUI
import SwiftData

enum WordSortOption: String, CaseIterable {
    case dateNewest = "Newest"
    case dateOldest = "Oldest"
    case accuracyLow = "Lowest Accuracy"
    case accuracyHigh = "Highest Accuracy"
    case streakLow = "Lowest Streak"
    case streakHigh = "Highest Streak"
    case mostReviewed = "Most Reviewed"
    case leastReviewed = "Least Reviewed"
    case hardest = "Hardest"
    case alphabetical = "A → Z"
}

struct WordListView: View {
    @Query(filter: #Predicate<FlashCard> { $0.status != "new" },
           sort: [SortDescriptor(\FlashCard.introducedDate, order: .reverse)])
    private var learnedCards: [FlashCard]
    @Query private var decks: [DeckMetadata]

    private var cardDirection: String { decks.first?.cardDirection ?? "source_first" }
    private var showTargetFirst: Bool { cardDirection == "target_first" }

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var filterStatus: String? = nil
    @State private var sortOption: WordSortOption = .dateNewest
    @State private var reviewCount: Int = 10
    @State private var showReviewSetup = false
    @State private var viewModel: StudySessionViewModel?
    @State private var filterCategory: String? = nil
    private var isPremium: Bool { PremiumManager.shared.isPremium }

    private var availableCategories: [String] {
        let parents = Set(learnedCards.compactMap(\.category).filter { !$0.isEmpty }.map {
            $0.split(separator: "/").first.map(String.init) ?? $0
        })
        return parents.sorted()
    }

    private var filteredCards: [FlashCard] {
        var cards = learnedCards
        if let filterStatus {
            cards = cards.filter { $0.status == filterStatus }
        }
        if let filterCategory {
            cards = cards.filter {
                guard let cat = $0.category else { return false }
                let parent = cat.split(separator: "/").first.map(String.init) ?? cat
                return parent == filterCategory
            }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            cards = cards.filter {
                $0.displaySourceText.lowercased().contains(query) ||
                $0.targetText.lowercased().contains(query) ||
                ($0.article?.lowercased().contains(query) ?? false)
            }
        }
        return sortCards(cards)
    }

    private func cardAccuracy(_ card: FlashCard) -> Double {
        guard card.totalReviews > 0 else { return -1 }
        return Double(card.totalCorrect) / Double(card.totalReviews)
    }

    private func sortCards(_ cards: [FlashCard]) -> [FlashCard] {
        switch sortOption {
        case .dateNewest:
            return cards.sorted { ($0.introducedDate ?? .distantPast) > ($1.introducedDate ?? .distantPast) }
        case .dateOldest:
            return cards.sorted { ($0.introducedDate ?? .distantPast) < ($1.introducedDate ?? .distantPast) }
        case .accuracyLow:
            return cards.sorted {
                let a0 = cardAccuracy($0), a1 = cardAccuracy($1)
                if a0 < 0 { return false }
                if a1 < 0 { return true }
                return a0 < a1
            }
        case .accuracyHigh:
            return cards.sorted {
                let a0 = cardAccuracy($0), a1 = cardAccuracy($1)
                if a0 < 0 { return false }
                if a1 < 0 { return true }
                return a0 > a1
            }
        case .streakLow:
            return cards.sorted { $0.currentStreak < $1.currentStreak }
        case .streakHigh:
            return cards.sorted { $0.currentStreak > $1.currentStreak }
        case .mostReviewed:
            return cards.sorted { $0.totalReviews > $1.totalReviews }
        case .leastReviewed:
            return cards.sorted { $0.totalReviews < $1.totalReviews }
        case .hardest:
            return cards.sorted { $0.easeFactor < $1.easeFactor }
        case .alphabetical:
            return cards.sorted {
                let left0 = showTargetFirst ? $0.targetText : $0.displaySourceText
                let left1 = showTargetFirst ? $1.targetText : $1.displaySourceText
                return left0.localizedCaseInsensitiveCompare(left1) == .orderedAscending
            }
        }
    }

    private var learningCount: Int {
        learnedCards.filter { $0.status == "learning" }.count
    }

    private var masteredCount: Int {
        learnedCards.filter { $0.status == "mastered" }.count
    }

    var body: some View {
        NavigationStack {
            wordListContent
        }
        .fullScreenCover(item: $viewModel) { (vm: StudySessionViewModel) in
            NavigationStack {
                reviewSessionView(viewModel: vm)
            }
        }
    }

    private var wordListContent: some View {
        Group {
            if learnedCards.isEmpty {
                ContentUnavailableView(
                    "No Words Yet",
                    systemImage: "book.closed",
                    description: Text("Words you learn will appear here.")
                )
            } else {
                List {
                    Section {
                        HStack(spacing: 16) {
                            statBadge(count: learnedCards.count, label: "Total", color: .blue)
                            statBadge(count: learningCount, label: "Learning", color: .orange)
                            statBadge(count: masteredCount, label: "Mastered", color: .green)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        Picker("Filter", selection: $filterStatus) {
                            Text("All").tag(nil as String?)
                            Text("Learning").tag("learning" as String?)
                            Text("Mastered").tag("mastered" as String?)
                        }
                        .pickerStyle(.segmented)
                        .subtleSectionGlow()

                        if isPremium && !availableCategories.isEmpty {
                            Picker("Category", selection: $filterCategory) {
                                Text("All Categories").tag(nil as String?)
                                ForEach(availableCategories, id: \.self) { cat in
                                    Text(cat.capitalized).tag(cat as String?)
                                }
                            }
                            .subtleSectionGlow()
                        }
                    }

                    Section {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(WordSortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .subtleSectionGlow()

                        Button {
                            withAnimation {
                                showReviewSetup.toggle()
                            }
                        } label: {
                            Label(showReviewSetup ? "Cancel Review" : "Review These Words",
                                  systemImage: showReviewSetup ? "xmark.circle.fill" : "play.circle.fill")
                        }
                        .subtleSectionGlow()
                    }

                    if showReviewSetup && !filteredCards.isEmpty {
                        let effectiveCount = min(reviewCount, filteredCards.count)
                        Section {
                            Stepper("\(effectiveCount) cards", value: $reviewCount, in: 1...max(filteredCards.count, 1))
                            Button {
                                let cards = Array(filteredCards.prefix(effectiveCount))
                                let vm = StudySessionViewModel()
                                vm.loadCustomReviewSession(cards: cards, cardDirection: cardDirection)
                                viewModel = vm
                                showReviewSetup = false
                            } label: {
                                Label("Start Review", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .listRowBackground(Color.clear)
                        } header: {
                            Text("Review top \(effectiveCount) from this list")
                        }
                    }

                    Section("\(filteredCards.count) words") {
                        ForEach(filteredCards, id: \.wordId) { card in
                            NavigationLink {
                                WordDetailView(card: card, showTargetFirst: showTargetFirst)
                            } label: {
                                WordRow(card: card, showTargetFirst: showTargetFirst)
                            }
                            .subtleSectionGlow()
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .searchable(text: $searchText, prompt: "Search words")
        .enhancedDarkContrast()
    }

    @ViewBuilder
    private func reviewSessionView(viewModel: StudySessionViewModel) -> some View {
        ReviewSessionView(
            viewModel: viewModel,
            title: "Custom Review",
            backLabel: "Back to Words",
            onDismiss: { self.viewModel = nil },
            deckMeta: decks.first
        )
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WordRow: View {
    let card: FlashCard
    let showTargetFirst: Bool

    private var leftText: String { showTargetFirst ? card.targetText : card.displaySourceText }
    private var rightText: String { showTargetFirst ? card.displaySourceText : card.targetText }
    private var showArticleOnLeft: Bool { showTargetFirst }

    private var accuracyText: String {
        guard card.totalReviews > 0 else { return "—" }
        let pct = Int(Double(card.totalCorrect) / Double(card.totalReviews) * 100)
        return "\(pct)%"
    }

    private var statusColor: Color {
        switch card.status {
        case "learning": return .orange
        case "mastered": return .green
        default: return .gray
        }
    }

    private var summaryLine: String {
        var parts: [String] = []
        if let pos = card.partOfSpeech {
            parts.append(pos)
        }
        if card.totalReviews > 0 {
            parts.append(accuracyText)
        }
        if card.currentStreak > 0 {
            parts.append("\(card.currentStreak) streak")
        }
        parts.append("\(card.totalReviews) reviews")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if showArticleOnLeft, let article = card.article, !article.isEmpty {
                    Text("\(article) \(leftText)")
                        .font(.body.bold())
                } else {
                    Text(leftText)
                        .font(.body.bold())
                }
                Spacer()
                Text(card.status.capitalized)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            if !showArticleOnLeft, let article = card.article, !article.isEmpty {
                Text("\(article) \(rightText)")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            } else {
                Text(rightText)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }

            Text(summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
