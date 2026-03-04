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
            lastUpdated: Date()
        )
    }
}
