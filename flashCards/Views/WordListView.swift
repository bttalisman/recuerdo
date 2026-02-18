import SwiftUI
import SwiftData
import UIKit

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
    @State private var ratingFlash: RatingFlash?

    private var filteredCards: [FlashCard] {
        var cards = learnedCards
        if let filterStatus {
            cards = cards.filter { $0.status == filterStatus }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            cards = cards.filter {
                $0.sourceText.lowercased().contains(query) ||
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
                let left0 = showTargetFirst ? $0.targetText : $0.sourceText
                let left1 = showTargetFirst ? $1.targetText : $1.sourceText
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
            if let viewModel {
                reviewSessionView(viewModel: viewModel)
            } else {
                wordListContent
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
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        Picker("Sort by", selection: $sortOption) {
                            ForEach(WordSortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }

                        Button {
                            withAnimation {
                                showReviewSetup.toggle()
                            }
                        } label: {
                            Label(showReviewSetup ? "Cancel Review" : "Review These Words",
                                  systemImage: showReviewSetup ? "xmark.circle.fill" : "play.circle.fill")
                        }
                    }

                    if showReviewSetup && !filteredCards.isEmpty {
                        Section {
                            Stepper("\(reviewCount) cards", value: $reviewCount, in: 1...max(filteredCards.count, 1))
                            Button {
                                let cards = Array(filteredCards.prefix(reviewCount))
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
                            Text("Review top \(reviewCount) from this list")
                        }
                    }

                    Section("\(filteredCards.count) words") {
                        ForEach(filteredCards, id: \.wordId) { card in
                            NavigationLink {
                                WordDetailView(card: card, showTargetFirst: showTargetFirst)
                            } label: {
                                WordRow(card: card, showTargetFirst: showTargetFirst)
                            }
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
        Group {
            if viewModel.isSessionComplete {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Review Complete!")
                        .font(.title.bold())
                    VStack(spacing: 8) {
                        HStack {
                            Text("Cards reviewed").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.totalReviewed)").fontWeight(.semibold)
                        }
                        HStack {
                            Text("Correct").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.correctCount)").fontWeight(.semibold)
                        }
                        HStack {
                            Text("Accuracy").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(viewModel.accuracy * 100))%").fontWeight(.semibold)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))

                    Button("Back to Words") { self.viewModel = nil }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let card = viewModel.currentCard {
                let deckMeta = decks.first
                VStack(spacing: 0) {
                    FlashCardView(
                        sourceText: card.sourceText,
                        targetText: card.targetText,
                        sourceLanguage: deckMeta?.sourceLanguage ?? "English",
                        targetLanguage: deckMeta?.targetLanguage ?? "Spanish",
                        status: card.status,
                        article: card.article,
                        showTargetFirst: viewModel.effectiveShowTargetFirst,
                        sourceLanguageCode: deckMeta?.sourceLanguageCode ?? "en",
                        targetLanguageCode: deckMeta?.targetLanguageCode ?? "es",
                        examples: card.examples,
                        isFlipped: Binding(
                            get: { viewModel.isFlipped },
                            set: { viewModel.isFlipped = $0 }
                        )
                    )
                    .id(card.wordId)
                    .frame(height: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(ratingFlash == .correct ? Color.green.opacity(0.25) : ratingFlash == .incorrect ? Color.red.opacity(0.25) : Color.clear)
                            .allowsHitTesting(false)
                    )
                    .padding(.horizontal)
                    .padding(.top, 16)

                    Spacer()

                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Button {
                                submitWithFeedback(quality: 1, viewModel: viewModel)
                            } label: {
                                Label("Nope", systemImage: "xmark.circle.fill")
                                    .font(.body.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(GlowButtonStyle(baseColor: .red))

                            Button {
                                submitWithFeedback(quality: 4, viewModel: viewModel)
                            } label: {
                                Label("Got it", systemImage: "checkmark.circle.fill")
                                    .font(.body.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(GlowButtonStyle(baseColor: .green))
                        }
                        .padding(.horizontal)
                        .opacity(viewModel.isFlipped ? 1 : 0)
                        .allowsHitTesting(viewModel.isFlipped)

                        Button {
                            viewModel.isSessionComplete = true
                        } label: {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Custom Review")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.sessionProgress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { self.viewModel = nil }
            }
        }
    }

    private func submitWithFeedback(quality: Int, viewModel: StudySessionViewModel) {
        let correct = quality >= 3
        if correct {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        ratingFlash = correct ? .correct : .incorrect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                viewModel.submitRating(quality, context: modelContext)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ratingFlash = nil
            }
        }
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

    private var leftText: String { showTargetFirst ? card.targetText : card.sourceText }
    private var rightText: String { showTargetFirst ? card.sourceText : card.targetText }
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
