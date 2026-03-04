import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct RecuerdoEntry: TimelineEntry {
    let date: Date
    let stats: WidgetStats
}

// MARK: - Timeline Provider

struct RecuerdoTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> RecuerdoEntry {
        RecuerdoEntry(date: Date(), stats: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecuerdoEntry) -> Void) {
        if context.isPreview {
            let sample = WidgetStats(
                dueCount: 12,
                learningCount: 87,
                masteredCount: 34,
                totalIntroduced: 121,
                unlockedWordCount: 500,
                currentDayStreak: 5,
                lastStudiedDate: Date(),
                lastUpdated: Date()
            )
            completion(RecuerdoEntry(date: Date(), stats: sample))
        } else {
            let stats = WidgetStats.load() ?? .placeholder
            completion(RecuerdoEntry(date: Date(), stats: stats))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecuerdoEntry>) -> Void) {
        let stats = WidgetStats.load() ?? .placeholder
        let entry = RecuerdoEntry(date: Date(), stats: stats)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Widget Configuration

struct RecuerdoWidget: Widget {
    let kind: String = "RecuerdoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecuerdoTimelineProvider()) { entry in
            RecuerdoWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Recuerdo")
        .description("See your cards due and study streak at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry View Router

struct RecuerdoWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: RecuerdoEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(stats: entry.stats)
        case .systemMedium:
            MediumWidgetView(stats: entry.stats)
        default:
            SmallWidgetView(stats: entry.stats)
        }
    }
}
