import SwiftUI
import SwiftData
import Charts

struct WordDetailView: View {
    let card: FlashCard
    let showTargetFirst: Bool

    private var sortedHistory: [ReviewRecord] {
        (card.reviewHistory).sorted { $0.reviewDate < $1.reviewDate }
    }

    private var missesBeforeFirstCorrect: Int {
        var count = 0
        for record in sortedHistory {
            if record.wasCorrect { break }
            count += 1
        }
        return count
    }

    private var lapsesAfterFirstCorrect: Int {
        guard let firstCorrectIndex = sortedHistory.firstIndex(where: { $0.wasCorrect }) else {
            return 0
        }
        return sortedHistory[firstCorrectIndex...].filter { !$0.wasCorrect }.count
    }

    private var averageResponseTime: Double? {
        let times = sortedHistory.map(\.responseTimeSeconds).filter { $0 > 0 }
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    private var recentAccuracy: String {
        let recent = sortedHistory.suffix(10)
        guard !recent.isEmpty else { return "—" }
        let correct = recent.filter(\.wasCorrect).count
        return "\(Int(Double(correct) / Double(recent.count) * 100))%"
    }

    private var overallAccuracy: String {
        guard card.totalReviews > 0 else { return "—" }
        return "\(Int(Double(card.totalCorrect) / Double(card.totalReviews) * 100))%"
    }

    var body: some View {
        List {
            wordHeaderSection
            if !card.examples.isEmpty {
                examplesSection
            }
            statsSection
            if !sortedHistory.isEmpty {
                streakChartSection
                historySection
            }
        }
        .navigationTitle(showTargetFirst ? card.targetText : card.displaySourceText)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Word Header

    private var wordHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let article = card.article, !article.isEmpty {
                        Text(article)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    Text(card.targetText)
                        .font(.largeTitle.bold())

                    Button {
                        let text = [card.article, card.targetText]
                            .compactMap { $0 }
                            .joined(separator: " ")
                        PronunciationManager.shared.speak(text, languageCode: "es")
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }

                Text(card.displaySourceText)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    if let pos = card.partOfSpeech {
                        Text(pos)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    if let category = card.category {
                        Text(category)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    Text(card.status.capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.15))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Examples

    private var examplesSection: some View {
        Section("Examples") {
            ForEach(card.examples, id: \.self) { example in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(example.es)
                            .font(.subheadline)
                            .italic()
                        Spacer()
                        Button {
                            PronunciationManager.shared.speak(example.es, languageCode: "es")
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(example.en)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section("Stats") {
            HStack {
                Text("Total reviews")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(card.totalReviews)")
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Overall accuracy")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(overallAccuracy)
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Last 10 accuracy")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(recentAccuracy)
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Current streak")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(card.currentStreak)")
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Longest streak")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(card.longestStreak)")
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Misses before first correct")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(missesBeforeFirstCorrect)")
                    .fontWeight(.semibold)
            }
            HStack {
                Text("Lapses after learning")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lapsesAfterFirstCorrect)")
                    .fontWeight(.semibold)
            }
            if let avg = averageResponseTime {
                HStack {
                    Text("Avg response time")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", avg))
                        .fontWeight(.semibold)
                }
            }
            if let introduced = card.introducedDate {
                HStack {
                    Text("Learned on")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(introduced, style: .date)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Streak Chart

    private var streakChartSection: some View {
        Section("Review History") {
            Chart {
                ForEach(Array(sortedHistory.enumerated()), id: \.offset) { index, record in
                    PointMark(
                        x: .value("Review", index + 1),
                        y: .value("Result", record.wasCorrect ? 1 : 0)
                    )
                    .foregroundStyle(record.wasCorrect ? .green : .red)
                    .symbolSize(sortedHistory.count > 30 ? 30 : 60)
                }
            }
            .chartYScale(domain: -0.2...1.2)
            .chartYAxis {
                AxisMarks(values: [0, 1]) { value in
                    AxisValueLabel {
                        if value.as(Int.self) == 1 {
                            Text("Got it")
                        } else {
                            Text("Missed")
                        }
                    }
                }
            }
            .chartXAxisLabel("Review #")
            .frame(height: 120)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Full History

    private var historySection: some View {
        Section("All Reviews (\(sortedHistory.count))") {
            ForEach(Array(sortedHistory.reversed().enumerated()), id: \.offset) { _, record in
                HStack {
                    Image(systemName: record.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(record.wasCorrect ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.reviewDate, style: .date)
                            .font(.subheadline)
                        Text(record.reviewDate, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if record.responseTimeSeconds > 0 {
                            Text(String(format: "%.1fs", record.responseTimeSeconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(record.studyMode.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var statusColor: Color {
        switch card.status {
        case "learning": return .orange
        case "mastered": return .green
        default: return .gray
        }
    }
}
