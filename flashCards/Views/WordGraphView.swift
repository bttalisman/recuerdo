import SwiftUI
import SwiftData

struct WordGraphView: View {
    @Query private var allCards: [FlashCard]
    @State private var searchText = ""
    @State private var selectedWordId: String?
    @State private var activeTypes: Set<RelationshipType> = Set(RelationshipType.allCases)
    @State private var suggestedCards: [FlashCard] = []

    private var sortedCards: [FlashCard] {
        allCards.filter { $0.totalReviews > 0 }.sorted { $0.targetText < $1.targetText }
    }

    private var filteredCards: [FlashCard] {
        if searchText.isEmpty { return sortedCards }
        let q = searchText.lowercased()
        return sortedCards.filter {
            $0.targetText.lowercased().contains(q) ||
            $0.sourceText.lowercased().contains(q)
        }
    }

    private var graphData: (nodes: [WordNode], edges: [WordEdge]) {
        guard let wid = selectedWordId else { return ([], []) }
        return WordRelationshipEngine.buildGraph(
            cards: allCards,
            centerWordId: wid,
            maxNodes: 20,
            activeTypes: activeTypes
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                wordSearchSection
                if selectedWordId != nil {
                    graphSection
                    filterSection
                } else {
                    promptState
                }
            }
            .padding()
        }
        .navigationTitle("Word Connections")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if suggestedCards.isEmpty {
                suggestedCards = Array(sortedCards.shuffled().prefix(10))
            }
        }
    }

    // MARK: - Word Search

    private var wordSearchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(searchText.isEmpty ? "Suggestions" : "Search Results")
                .font(.headline)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search words...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))

            if true {
                let cards = searchText.isEmpty
                    ? Array(suggestedCards.prefix(10))
                    : Array(filteredCards.prefix(15))
                if cards.isEmpty {
                    Text("No words found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cards, id: \.wordId) { card in
                        Button {
                            withAnimation {
                                selectedWordId = card.wordId
                                searchText = ""
                            }
                        } label: {
                            HStack {
                                HStack(spacing: 4) {
                                    if let article = card.article, !article.isEmpty {
                                        Text(article).foregroundStyle(.secondary)
                                    }
                                    Text(card.targetText).fontWeight(.medium)
                                }
                                Spacer()
                                Text(card.sourceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Graph Canvas

    private var graphSection: some View {
        let data = graphData

        return VStack(alignment: .leading, spacing: 12) {
            if data.nodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No connections found for this word.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Text("\(data.nodes.count) words, \(data.edges.count) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Canvas { context, size in
                    let scaleX = size.width / 350
                    let scaleY = size.height / 350

                    // Draw edges
                    for edge in data.edges {
                        guard let fromNode = data.nodes.first(where: { $0.id == edge.from }),
                              let toNode = data.nodes.first(where: { $0.id == edge.to }) else { continue }

                        let from = CGPoint(x: fromNode.position.x * scaleX, y: fromNode.position.y * scaleY)
                        let to = CGPoint(x: toNode.position.x * scaleX, y: toNode.position.y * scaleY)

                        var path = Path()
                        path.move(to: from)
                        path.addLine(to: to)

                        let style: StrokeStyle
                        let color: Color
                        switch edge.type {
                        case .synonym:
                            style = StrokeStyle(lineWidth: 2)
                            color = .blue
                        case .wordFamily:
                            style = StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                            color = .purple
                        case .sharedExample:
                            style = StrokeStyle(lineWidth: 1)
                            color = .cyan
                        case .genderPair:
                            style = StrokeStyle(lineWidth: 2)
                            color = .pink
                        case .category:
                            style = StrokeStyle(lineWidth: 0.8, dash: [2, 2])
                            color = .gray
                        }

                        context.stroke(path, with: .color(color.opacity(0.6)), style: style)
                    }

                    // Draw nodes
                    for (i, node) in data.nodes.enumerated() {
                        let pos = CGPoint(x: node.position.x * scaleX, y: node.position.y * scaleY)
                        let radius: CGFloat = i == 0 ? 28 : 22

                        // Node circle
                        let circle = Path(ellipseIn: CGRect(
                            x: pos.x - radius, y: pos.y - radius,
                            width: radius * 2, height: radius * 2
                        ))
                        let fillColor = nodeColor(category: node.category)
                        context.fill(circle, with: .color(fillColor.opacity(0.85)))

                        // Border by accuracy
                        let borderColor = accuracyColor(node.accuracy)
                        context.stroke(circle, with: .color(borderColor), style: StrokeStyle(lineWidth: i == 0 ? 3 : 2))

                        // Label
                        let label = node.label
                        let text = Text(label)
                            .font(.system(size: i == 0 ? 10 : 8, weight: i == 0 ? .bold : .medium))
                            .foregroundColor(.white)
                        context.draw(context.resolve(text), at: pos)
                    }
                }
                .frame(height: 350)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                .onTapGesture { location in
                    handleTap(at: location, in: CGSize(width: 350, height: 350), data: data)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(graphAccessibilityLabel(data: data))

                // Edge type legend
                HStack(spacing: 12) {
                    ForEach(Array(Set(data.edges.map(\.type))).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                        HStack(spacing: 3) {
                            Circle().fill(edgeColor(type)).frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                            Text(type.rawValue)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Filter Toggles

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Relationship Types")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(RelationshipType.allCases, id: \.self) { type in
                    Button {
                        withAnimation {
                            if activeTypes.contains(type) {
                                activeTypes.remove(type)
                            } else {
                                activeTypes.insert(type)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.caption2)
                            Text(type.rawValue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(activeTypes.contains(type) ? edgeColor(type).opacity(0.2) : Color(.systemGray5))
                        .foregroundStyle(activeTypes.contains(type) ? edgeColor(type) : .secondary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(activeTypes.contains(type) ? "enabled" : "disabled")
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - Prompt State

    private var promptState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.grid.3x3.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Select a word above to see its connections")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func graphAccessibilityLabel(data: (nodes: [WordNode], edges: [WordEdge])) -> String {
        guard let center = data.nodes.first else { return "Word connections graph" }
        let connected = data.nodes.dropFirst().prefix(5).map(\.label)
        if connected.isEmpty {
            return "Word connections graph centered on \(center.label). No connections."
        }
        return "Word connections graph centered on \(center.label). Connected to: \(connected.joined(separator: ", "))"
    }

    private func handleTap(at location: CGPoint, in size: CGSize, data: (nodes: [WordNode], edges: [WordEdge])) {
        // Scale the tap location to the 350x350 coordinate space
        let geo = UIScreen.main.bounds.width - 32 // approximate padding
        let scaleX = 350 / geo
        let scaleY = 350 / 350.0

        let mapped = CGPoint(x: location.x * scaleX, y: location.y * scaleY)

        for node in data.nodes {
            let dist = hypot(mapped.x - node.position.x, mapped.y - node.position.y)
            if dist < 30 {
                withAnimation {
                    selectedWordId = node.id
                }
                return
            }
        }
    }

    private func nodeColor(category: String?) -> Color {
        guard let cat = category?.lowercased() else { return .gray }
        switch cat {
        case "family", "people": return .blue
        case "food", "drink": return .orange
        case "nature", "animals": return .green
        case "travel", "places": return .purple
        case "work", "business": return .indigo
        case "body", "health": return .pink
        case "time", "numbers": return .cyan
        default: return .gray
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.8 { return .green }
        if accuracy >= 0.6 { return .orange }
        return .red
    }

    private func edgeColor(_ type: RelationshipType) -> Color {
        switch type {
        case .synonym: return .blue
        case .wordFamily: return .purple
        case .sharedExample: return .cyan
        case .genderPair: return .pink
        case .category: return .gray
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
