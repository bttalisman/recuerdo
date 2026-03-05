import Foundation

/// Data shared between the main app and the widget extension via App Group UserDefaults.
struct WidgetStats: Codable {
    let dueCount: Int
    let learningCount: Int
    let masteredCount: Int
    let totalIntroduced: Int
    let unlockedWordCount: Int
    let currentDayStreak: Int
    let lastStudiedDate: Date?
    let lastUpdated: Date
    var atRiskCount: Int

    init(dueCount: Int, learningCount: Int, masteredCount: Int,
         totalIntroduced: Int, unlockedWordCount: Int, currentDayStreak: Int,
         lastStudiedDate: Date?, lastUpdated: Date, atRiskCount: Int = 0) {
        self.dueCount = dueCount
        self.learningCount = learningCount
        self.masteredCount = masteredCount
        self.totalIntroduced = totalIntroduced
        self.unlockedWordCount = unlockedWordCount
        self.currentDayStreak = currentDayStreak
        self.lastStudiedDate = lastStudiedDate
        self.lastUpdated = lastUpdated
        self.atRiskCount = atRiskCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dueCount = try c.decode(Int.self, forKey: .dueCount)
        learningCount = try c.decode(Int.self, forKey: .learningCount)
        masteredCount = try c.decode(Int.self, forKey: .masteredCount)
        totalIntroduced = try c.decode(Int.self, forKey: .totalIntroduced)
        unlockedWordCount = try c.decode(Int.self, forKey: .unlockedWordCount)
        currentDayStreak = try c.decode(Int.self, forKey: .currentDayStreak)
        lastStudiedDate = try c.decodeIfPresent(Date.self, forKey: .lastStudiedDate)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        atRiskCount = try c.decodeIfPresent(Int.self, forKey: .atRiskCount) ?? 0
    }

    static let suiteName = "group.com.recuerdoapp.flash"
    static let key = "widgetStats"

    static func save(_ stats: WidgetStats) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: key)
        }
    }

    static func load() -> WidgetStats? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetStats.self, from: data)
    }

    static var placeholder: WidgetStats {
        WidgetStats(
            dueCount: 0,
            learningCount: 0,
            masteredCount: 0,
            totalIntroduced: 0,
            unlockedWordCount: 500,
            currentDayStreak: 0,
            lastStudiedDate: nil,
            lastUpdated: Date(),
            atRiskCount: 0
        )
    }
}
