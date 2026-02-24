import Foundation

enum Severity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Insight: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    var detail: String? = nil
    let severity: Severity
    let supportingWords: [FlashCard]
}

struct DifficultyAnalyzer {

    // MARK: - Public

    static func generateInsights(cards: [FlashCard], reviews: [ReviewRecord]) -> [Insight] {
        let reviewed = cards.filter { $0.totalReviews > 0 }
        let totalReviews = reviews.count
        guard totalReviews >= 50 else { return [] }

        var insights: [Insight] = []

        if let gender = genderTrouble(cards: reviewed) { insights.append(gender) }
        if let pos = posDeepDive(cards: reviewed) { insights.append(pos) }
        if let slow = slowWords(cards: reviewed, reviews: reviews) { insights.append(slow) }
        if let cognate = cognateEffect(cards: reviewed) { insights.append(cognate) }
        if let falseCog = falseCognates(cards: cards) { insights.append(falseCog) }
        if let lapse = lapsePatterns(cards: reviewed) { insights.append(lapse) }
        if let length = wordLengthEffect(cards: reviewed) { insights.append(length) }

        return insights.sorted { $0.severity > $1.severity }
    }

    // MARK: - 1. Gender Trouble

    private static func genderTrouble(cards: [FlashCard]) -> Insight? {
        var elCards: [FlashCard] = []
        var laCards: [FlashCard] = []

        for card in cards {
            guard let article = card.article?.lowercased(), card.totalReviews >= 1 else { continue }
            if article == "el" { elCards.append(card) }
            else if article == "la" { laCards.append(card) }
        }

        guard elCards.count >= 10, laCards.count >= 10 else { return nil }

        let elAcc = accuracy(of: elCards)
        let laAcc = accuracy(of: laCards)
        let diff = abs(elAcc - laAcc)

        guard diff > 0.10 else { return nil }

        let worse = elAcc < laAcc ? "masculine (el)" : "feminine (la)"
        let worseAcc = min(elAcc, laAcc)
        let betterAcc = max(elAcc, laAcc)
        let worseCards = (elAcc < laAcc ? elCards : laCards)
            .sorted { accuracy(of: [$0]) < accuracy(of: [$1]) }

        let severity: Severity = diff > 0.25 ? .critical : .warning

        return Insight(
            id: "gender",
            icon: "textformat.abc",
            title: "Gender Trouble",
            description: "You score \(pct(worseAcc)) on \(worse) words vs \(pct(betterAcc)) on the other gender. Focus on \(worse) nouns.",
            severity: severity,
            supportingWords: Array(worseCards.prefix(10))
        )
    }

    // MARK: - 2. Part of Speech Deep Dive

    private static func posDeepDive(cards: [FlashCard]) -> Insight? {
        var byPOS: [String: [FlashCard]] = [:]
        for card in cards where card.totalReviews >= 1 {
            let pos = card.partOfSpeech ?? "unknown"
            byPOS[pos, default: []].append(card)
        }

        let ranked = byPOS
            .filter { $0.value.count >= 5 }
            .map { (pos: $0.key, cards: $0.value, acc: accuracy(of: $0.value)) }
            .sorted { $0.acc < $1.acc }

        guard let worst = ranked.first else { return nil }

        let overallAcc = accuracy(of: cards)
        let diff = overallAcc - worst.acc
        guard diff > 0.05 else { return nil }

        let severity: Severity = worst.acc < 0.5 ? .critical : (worst.acc < 0.7 ? .warning : .info)
        let strugglers = worst.cards.sorted { accuracy(of: [$0]) < accuracy(of: [$1]) }

        return Insight(
            id: "pos",
            icon: "text.book.closed",
            title: "\(worst.pos.capitalized) Struggles",
            description: "Your \(worst.pos) accuracy is \(pct(worst.acc)), \(Int(diff * 100))pp below your overall \(pct(overallAcc)).",
            severity: severity,
            supportingWords: Array(strugglers.prefix(10))
        )
    }

    // MARK: - 3. Slow Words

    private static func slowWords(cards: [FlashCard], reviews: [ReviewRecord]) -> Insight? {
        var timeByCard: [String: (total: Double, count: Int)] = [:]
        for review in reviews where review.responseTimeSeconds > 0 && review.responseTimeSeconds < 60 {
            guard let wordId = review.card?.wordId else { continue }
            var entry = timeByCard[wordId, default: (total: 0, count: 0)]
            entry.total += review.responseTimeSeconds
            entry.count += 1
            timeByCard[wordId] = entry
        }

        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.wordId, $0) })

        let ranked = timeByCard
            .filter { $0.value.count >= 3 }
            .map { (wordId: $0.key, avgTime: $0.value.total / Double($0.value.count)) }
            .sorted { $0.avgTime > $1.avgTime }
            .prefix(5)
            .compactMap { item -> FlashCard? in cardMap[item.wordId] }

        guard ranked.count >= 3 else { return nil }

        let allAvgTimes = timeByCard
            .filter { $0.value.count >= 3 }
            .map { $0.value.total / Double($0.value.count) }

        // Need more cards than just the slow ones to make a meaningful comparison
        guard allAvgTimes.count >= 8 else { return nil }

        let overallAvg = allAvgTimes.reduce(0, +) / Double(allAvgTimes.count)
        let rankedIds = Set(ranked.map(\.wordId))
        let topAvgTimes = timeByCard
            .filter { rankedIds.contains($0.key) }
            .map { $0.value.total / Double($0.value.count) }
        let topAvg = topAvgTimes.reduce(0, +) / Double(topAvgTimes.count)

        // Only show if slow words are meaningfully slower than average
        guard topAvg > overallAvg * 1.3 else { return nil }

        return Insight(
            id: "slow",
            icon: "tortoise",
            title: "Slow Words",
            description: "Your 5 slowest words average \(String(format: "%.1f", topAvg))s vs your overall \(String(format: "%.1f", overallAvg))s.",
            severity: .info,
            supportingWords: Array(ranked)
        )
    }

    // MARK: - 4. Cognate Effect

    private static func cognateEffect(cards: [FlashCard]) -> Insight? {
        var cognates: [FlashCard] = []
        var nonCognates: [FlashCard] = []

        for card in cards where card.totalReviews >= 1 {
            if isCognate(source: card.sourceText, target: card.targetText) {
                cognates.append(card)
            } else {
                nonCognates.append(card)
            }
        }

        guard cognates.count >= 5, nonCognates.count >= 5 else { return nil }

        let cogAcc = accuracy(of: cognates)
        let nonCogAcc = accuracy(of: nonCognates)
        let diff = cogAcc - nonCogAcc

        guard abs(diff) > 0.05 else { return nil }

        let severity: Severity = diff > 0.20 ? .warning : .info
        let worseSet = diff > 0 ? nonCognates : cognates
        let strugglers = worseSet.sorted { accuracy(of: [$0]) < accuracy(of: [$1]) }

        let desc: String
        if diff > 0 {
            desc = "You're \(Int(diff * 100))pp more accurate on cognates (\(pct(cogAcc))) than non-cognates (\(pct(nonCogAcc))). Focus practice on non-cognates."
        } else {
            desc = "Surprisingly, you're better on non-cognates (\(pct(nonCogAcc))) than cognates (\(pct(cogAcc))). Watch for false cognates."
        }

        return Insight(
            id: "cognate",
            icon: "arrow.triangle.branch",
            title: "Cognate Effect",
            description: desc,
            severity: severity,
            supportingWords: Array(strugglers.prefix(10))
        )
    }

    private static func isCognate(source: String, target: String) -> Bool {
        let sClean = source.lowercased().replacingOccurrences(of: " ", with: "")
        let s = sClean.components(separatedBy: CharacterSet.letters.inverted).first ?? sClean
        let t = target.lowercased()
            .replacingOccurrences(of: " ", with: "")

        guard !s.isEmpty, !t.isEmpty else { return false }

        var shared = 0
        let sChars = Array(s)
        let tChars = Array(t)
        for i in 0..<min(sChars.count, tChars.count) {
            if sChars[i] == tChars[i] { shared += 1 }
            else { break }
        }
        return Double(shared) / Double(max(sChars.count, tChars.count)) > 0.5
    }

    // MARK: - 5. False Cognates

    // Spanish word → (looks like English, actually means)
    private static let falseCognateMap: [String: (looksLike: String, actualMeaning: String)] = [
        "actual": ("actual", "current, present"),
        "actualmente": ("actually", "currently"),
        "asistir": ("assist", "to attend"),
        "atender": ("attend", "to assist, pay attention to"),
        "bizarro": ("bizarre", "brave, gallant"),
        "campo": ("camp", "field, countryside"),
        "carpeta": ("carpet", "folder"),
        "collar": ("collar", "necklace"),
        "compromiso": ("compromise", "commitment, obligation"),
        "conducir": ("conduce", "to drive"),
        "constipado": ("constipated", "having a cold"),
        "contestar": ("contest", "to answer"),
        "decepción": ("deception", "disappointment"),
        "delito": ("delight", "crime"),
        "disgusto": ("disgust", "annoyance, upset"),
        "embarazada": ("embarrassed", "pregnant"),
        "eventualmente": ("eventually", "possibly, occasionally"),
        "éxito": ("exit", "success"),
        "fábrica": ("fabric", "factory"),
        "gracioso": ("gracious", "funny"),
        "introducir": ("introduce (a person)", "to insert, enter"),
        "largo": ("large", "long"),
        "lectura": ("lecture", "reading"),
        "librería": ("library", "bookstore"),
        "molestar": ("molest", "to bother, annoy"),
        "once": ("once", "eleven"),
        "pan": ("pan", "bread"),
        "pariente": ("parent", "relative"),
        "pretender": ("pretend", "to try, attempt"),
        "realizar": ("realize", "to accomplish, carry out"),
        "recordar": ("record", "to remember"),
        "ropa": ("rope", "clothing"),
        "salida": ("salad", "exit, departure"),
        "sensible": ("sensible", "sensitive"),
        "sopa": ("soap", "soup"),
        "suceso": ("success", "event, happening"),
        "tuna": ("tuna", "prickly pear, student music group"),
        "vaso": ("vase", "drinking glass"),
    ]

    private static func falseCognates(cards: [FlashCard]) -> Insight? {
        let targetLookup = Dictionary(
            cards.map { ($0.targetText.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var matched: [FlashCard] = []
        for (spanishWord, _) in falseCognateMap {
            if let card = targetLookup[spanishWord] {
                matched.append(card)
            }
        }

        guard !matched.isEmpty else { return nil }

        let desc = "Your deck has \(matched.count) false cognate\(matched.count == 1 ? "" : "s") — words that look like English but mean something different."

        let tips = matched.compactMap { card -> String? in
            guard let entry = falseCognateMap[card.targetText.lowercased()] else { return nil }
            return "\"\(card.targetText)\" looks like \"\(entry.looksLike)\" but means \"\(entry.actualMeaning)\""
        }
        let detail = "False cognates (\"false friends\") are Spanish words that resemble English words but have different meanings. Watch out for these:\n\n" + tips.map { "• \($0)" }.joined(separator: "\n")

        return Insight(
            id: "falsecognate",
            icon: "exclamationmark.triangle",
            title: "False Friends",
            description: desc,
            detail: detail,
            severity: .warning,
            supportingWords: matched
        )
    }

    // MARK: - 6. Lapse Patterns

    private static func lapsePatterns(cards: [FlashCard]) -> Insight? {
        let lapsed = cards.filter { $0.longestStreak >= 3 && $0.currentStreak == 0 && $0.totalReviews >= 3 }
        guard lapsed.count >= 3 else { return nil }

        // Find common POS among lapsed
        let posCount = Dictionary(grouping: lapsed, by: { $0.partOfSpeech ?? "unknown" })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }

        let commonPOS = posCount.first?.key ?? "unknown"
        let commonCount = posCount.first?.value ?? 0

        let severity: Severity = lapsed.count >= 10 ? .critical : (lapsed.count >= 5 ? .warning : .info)

        return Insight(
            id: "lapse",
            icon: "arrow.uturn.down.circle",
            title: "Lapsed Words",
            description: "\(lapsed.count) words you mastered have slipped. \(commonCount) are \(commonPOS)s. Time for targeted review.",
            severity: severity,
            supportingWords: lapsed.sorted { $0.longestStreak > $1.longestStreak }
        )
    }

    // MARK: - 6. Word Length Effect

    private static func wordLengthEffect(cards: [FlashCard]) -> Insight? {
        let shortCards = cards.filter { $0.targetText.count <= 5 && $0.totalReviews >= 1 }
        let longCards = cards.filter { $0.targetText.count > 8 && $0.totalReviews >= 1 }

        guard shortCards.count >= 5, longCards.count >= 5 else { return nil }

        let shortAcc = accuracy(of: shortCards)
        let longAcc = accuracy(of: longCards)
        let diff = shortAcc - longAcc

        guard abs(diff) > 0.08 else { return nil }

        let worseLabel = diff > 0 ? "long (9+ chars)" : "short (1-5 chars)"
        let worseAcc = min(shortAcc, longAcc)
        let betterAcc = max(shortAcc, longAcc)
        let worseCards = (diff > 0 ? longCards : shortCards)
            .sorted { accuracy(of: [$0]) < accuracy(of: [$1]) }

        return Insight(
            id: "length",
            icon: "textformat.size",
            title: "Word Length Effect",
            description: "You score \(pct(worseAcc)) on \(worseLabel) words vs \(pct(betterAcc)) on the other. Length matters!",
            severity: .info,
            supportingWords: Array(worseCards.prefix(10))
        )
    }

    // MARK: - Helpers

    private static func accuracy(of cards: [FlashCard]) -> Double {
        let total = cards.reduce(0) { $0 + $1.totalReviews }
        let correct = cards.reduce(0) { $0 + $1.totalCorrect }
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }

    private static func pct(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}
