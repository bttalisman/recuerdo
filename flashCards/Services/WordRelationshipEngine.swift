import Foundation
import CoreGraphics

enum RelationshipType: String, CaseIterable {
    case synonym = "Synonyms"
    case wordFamily = "Word Family"
    case sharedExample = "Shared Example"
    case genderPair = "Gender Pair"
    case category = "Category"

    var icon: String {
        switch self {
        case .synonym: return "equal.circle"
        case .wordFamily: return "tree"
        case .sharedExample: return "text.quote"
        case .genderPair: return "person.2"
        case .category: return "folder"
        }
    }
}

struct WordNode: Identifiable {
    let id: String
    let label: String
    let article: String?
    let category: String?
    let accuracy: Double
    var position: CGPoint

    init(card: FlashCard, position: CGPoint = .zero) {
        self.id = card.wordId
        self.label = card.targetText
        self.article = card.article
        self.category = card.category
        self.accuracy = card.totalReviews > 0 ? Double(card.totalCorrect) / Double(card.totalReviews) : 1.0
        self.position = position
    }
}

struct WordEdge: Identifiable {
    let id = UUID()
    let from: String
    let to: String
    let type: RelationshipType
}

struct WordRelationshipEngine {

    // MARK: - Build Graph

    static func buildGraph(cards: [FlashCard], centerWordId: String, maxNodes: Int = 20, activeTypes: Set<RelationshipType> = Set(RelationshipType.allCases)) -> (nodes: [WordNode], edges: [WordEdge]) {
        guard let centerCard = cards.first(where: { $0.wordId == centerWordId }) else {
            return ([], [])
        }

        var edges: [WordEdge] = []
        var connectedIds: Set<String> = []
        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.wordId, $0) })
        let targetMap = Dictionary(grouping: cards, by: { $0.targetText.lowercased() })

        // Find all edges from center
        for card in cards where card.wordId != centerWordId {
            let rels = findRelationships(a: centerCard, b: card, targetMap: targetMap)
            for rel in rels where activeTypes.contains(rel) {
                edges.append(WordEdge(from: centerWordId, to: card.wordId, type: rel))
                connectedIds.insert(card.wordId)
            }
        }

        // Limit to maxNodes - 1 connections (plus center)
        let limitedIds = Array(connectedIds.prefix(maxNodes - 1))
        edges = edges.filter { limitedIds.contains($0.to) }

        // Build nodes
        var nodes: [WordNode] = [WordNode(card: centerCard)]
        for wid in limitedIds {
            if let card = cardMap[wid] {
                nodes.append(WordNode(card: card))
            }
        }

        // Layout
        layoutRadial(nodes: &nodes, canvasSize: CGSize(width: 350, height: 350))

        return (nodes, edges)
    }

    // MARK: - Find Relationships

    private static func findRelationships(a: FlashCard, b: FlashCard, targetMap: [String: [FlashCard]]) -> [RelationshipType] {
        var rels: [RelationshipType] = []

        if areSynonyms(a: a, b: b, targetMap: targetMap) { rels.append(.synonym) }
        if areWordFamily(a: a, b: b) { rels.append(.wordFamily) }
        if haveSharedExample(a: a, b: b) { rels.append(.sharedExample) }
        if areGenderPair(a: a, b: b) { rels.append(.genderPair) }
        if sameCategory(a: a, b: b) { rels.append(.category) }

        return rels
    }

    // 1. Synonyms — look for "[also X]" or "also: X" patterns in sourceText
    private static func areSynonyms(a: FlashCard, b: FlashCard, targetMap: [String: [FlashCard]]) -> Bool {
        let patterns = ["[also ", "(also ", "also: ", "/ "]
        for pattern in patterns {
            if a.sourceText.lowercased().contains(pattern + b.targetText.lowercased()) { return true }
            if b.sourceText.lowercased().contains(pattern + a.targetText.lowercased()) { return true }
        }
        // Check if they share the same English meaning (same sourceText base)
        let aBase = a.sourceText.lowercased().components(separatedBy: CharacterSet(charactersIn: "([/")).first?.trimmingCharacters(in: .whitespaces) ?? ""
        let bBase = b.sourceText.lowercased().components(separatedBy: CharacterSet(charactersIn: "([/")).first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !aBase.isEmpty && aBase == bBase && a.wordId != b.wordId { return true }
        return false
    }

    // 2. Word families — shared prefix of 4+ chars
    private static func areWordFamily(a: FlashCard, b: FlashCard) -> Bool {
        let aText = a.targetText.lowercased()
        let bText = b.targetText.lowercased()
        guard aText != bText else { return false }
        let minLen = min(aText.count, bText.count)
        guard minLen >= 4 else { return false }

        let aChars = Array(aText)
        let bChars = Array(bText)
        var shared = 0
        for i in 0..<minLen {
            if aChars[i] == bChars[i] { shared += 1 }
            else { break }
        }
        return shared >= 4
    }

    // 3. Shared examples — a word appears in another's example
    private static func haveSharedExample(a: FlashCard, b: FlashCard) -> Bool {
        let aTarget = a.targetText.lowercased()
        let bTarget = b.targetText.lowercased()
        guard aTarget.count >= 3, bTarget.count >= 3 else { return false }

        for example in a.examples {
            if example.es.lowercased().contains(bTarget) { return true }
        }
        for example in b.examples {
            if example.es.lowercased().contains(aTarget) { return true }
        }
        return false
    }

    // 4. Gender pairs — same root with -o/-a endings
    private static func areGenderPair(a: FlashCard, b: FlashCard) -> Bool {
        guard let aArt = a.article?.lowercased(), let bArt = b.article?.lowercased() else { return false }
        guard (aArt == "el" && bArt == "la") || (aArt == "la" && bArt == "el") else { return false }

        let aText = a.targetText.lowercased()
        let bText = b.targetText.lowercased()
        guard aText.count >= 3, bText.count >= 3 else { return false }

        let aRoot = String(aText.dropLast())
        let bRoot = String(bText.dropLast())
        return aRoot == bRoot
    }

    // 5. Same category
    private static func sameCategory(a: FlashCard, b: FlashCard) -> Bool {
        guard let aCat = a.category, let bCat = b.category else { return false }
        return aCat == bCat && !aCat.isEmpty
    }

    // MARK: - Radial Layout

    static func layoutRadial(nodes: inout [WordNode], canvasSize: CGSize) {
        guard !nodes.isEmpty else { return }

        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        nodes[0].position = center

        let connected = Array(nodes.dropFirst())
        guard !connected.isEmpty else { return }

        let radius = min(canvasSize.width, canvasSize.height) * 0.38
        let angleStep = 2 * Double.pi / Double(connected.count)

        for (i, _) in connected.enumerated() {
            let angle = angleStep * Double(i) - Double.pi / 2
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius
            nodes[i + 1].position = CGPoint(x: x, y: y)
        }
    }
}
