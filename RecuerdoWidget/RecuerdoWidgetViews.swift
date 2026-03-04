import SwiftUI
import WidgetKit

// MARK: - Small Widget

struct SmallWidgetView: View {
    let stats: WidgetStats

    private var hasStudiedToday: Bool {
        guard let last = stats.lastStudiedDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("Recuerdo")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if stats.dueCount > 0 {
                Text("\(stats.dueCount)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(stats.dueCount == 1 ? "card due" : "cards due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("0")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text(hasStudiedToday ? "All caught up!" : "Study today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if stats.currentDayStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(stats.currentDayStreak) day streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "recuerdo://study"))
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let stats: WidgetStats

    private var progress: Double {
        guard stats.unlockedWordCount > 0 else { return 0 }
        return Double(stats.totalIntroduced) / Double(stats.unlockedWordCount)
    }

    private var hasStudiedToday: Bool {
        guard let last = stats.lastStudiedDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left: due count
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("Recuerdo")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if stats.dueCount > 0 {
                    Text("\(stats.dueCount)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text(stats.dueCount == 1 ? "card due" : "cards due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("0")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text(hasStudiedToday ? "All caught up!" : "Study today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if stats.currentDayStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("\(stats.currentDayStreak)d streak")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Right: progress breakdown
            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 8, height: 8)
                    Text("Learning")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(stats.learningCount)")
                        .font(.caption.bold())
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Mastered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(stats.masteredCount)")
                        .font(.caption.bold())
                }

                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .tint(progress >= 0.8 ? .green : .blue)
                    Text("\(stats.totalIntroduced)/\(stats.unlockedWordCount) words")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
        }
        .widgetURL(URL(string: "recuerdo://study"))
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    RecuerdoWidget()
} timeline: {
    RecuerdoEntry(date: Date(), stats: WidgetStats(
        dueCount: 12,
        learningCount: 87,
        masteredCount: 34,
        totalIntroduced: 121,
        unlockedWordCount: 500,
        currentDayStreak: 5,
        lastStudiedDate: Date(),
        lastUpdated: Date()
    ))
}

#Preview("Medium", as: .systemMedium) {
    RecuerdoWidget()
} timeline: {
    RecuerdoEntry(date: Date(), stats: WidgetStats(
        dueCount: 12,
        learningCount: 87,
        masteredCount: 34,
        totalIntroduced: 121,
        unlockedWordCount: 500,
        currentDayStreak: 5,
        lastStudiedDate: Date(),
        lastUpdated: Date()
    ))
}

#Preview("Small - All Done", as: .systemSmall) {
    RecuerdoWidget()
} timeline: {
    RecuerdoEntry(date: Date(), stats: WidgetStats(
        dueCount: 0,
        learningCount: 87,
        masteredCount: 34,
        totalIntroduced: 121,
        unlockedWordCount: 500,
        currentDayStreak: 5,
        lastStudiedDate: Date(),
        lastUpdated: Date()
    ))
}
