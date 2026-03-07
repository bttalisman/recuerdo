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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("Recuerdo")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            if stats.dueCount > 0 {
                Text("\(stats.dueCount)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(stats.dueCount == 1 ? "card due" : "cards due")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("0")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text(hasStudiedToday ? "All caught up!" : "Study today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            if stats.currentDayStreak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("\(stats.currentDayStreak)d streak")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "recuerdo://quickreview"))
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

    private var dueColor: Color { stats.dueCount > 0 ? .orange : .green }
    private var dueLabel: String {
        stats.dueCount > 0
            ? "\(stats.dueCount) due"
            : (hasStudiedToday ? "All caught up" : "Study today")
    }

    private var quickReviewLabel: String {
        stats.atRiskCount > 0
            ? "Review \(min(stats.atRiskCount, 10)) At Risk"
            : "Quick Review"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: header + stats
            VStack(spacing: 8) {
                // Header row
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text("Recuerdo")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if stats.currentDayStreak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(stats.currentDayStreak)d")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Stats row
                HStack(spacing: 0) {
                    // Due count
                    VStack(spacing: 1) {
                        Text("\(stats.dueCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(dueColor)
                        Text("due")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Divider
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.quaternary)
                        .frame(width: 1, height: 28)

                    // Learning
                    VStack(spacing: 1) {
                        Text("\(stats.learningCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("learning")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    // Divider
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.quaternary)
                        .frame(width: 1, height: 28)

                    // Mastered
                    VStack(spacing: 1) {
                        Text("\(stats.masteredCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("mastered")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Progress bar
                VStack(spacing: 2) {
                    ProgressView(value: progress)
                        .tint(progress >= 0.8 ? .green : .blue)
                    Text("\(stats.totalIntroduced) of \(stats.unlockedWordCount) words introduced")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 6)

            // Bottom: action buttons
            HStack(spacing: 6) {
                Link(destination: URL(string: "recuerdo://study")!) {
                    HStack(spacing: 3) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 10))
                        Text("Study")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.blue))
                }

                Link(destination: URL(string: "recuerdo://quickreview")!) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("Review")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.orange))
                }

                Link(destination: URL(string: "recuerdo://audioreview")!) {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 10))
                        Text("Audio")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.green))
                }
            }
        }
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
        lastUpdated: Date(),
        atRiskCount: 7
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
