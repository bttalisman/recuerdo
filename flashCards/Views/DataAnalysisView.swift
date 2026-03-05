import SwiftUI
import SwiftData
import Charts

enum TrendRange: String, CaseIterable {
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case all = "All"

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .all: return nil
        }
    }

    var rollingWindow: Int {
        switch self {
        case .week: return 3
        case .month: return 7
        case .threeMonths: return 14
        case .all: return 21
        }
    }
}

private enum EngagementZone: String, CaseIterable {
    case effortZone
    case lockedIn
    case guessing
    case struggling

    var label: String {
        switch self {
        case .effortZone: return "Effort"
        case .lockedIn: return "Locked In"
        case .guessing: return "Guessing"
        case .struggling: return "Struggling"
        }
    }

    var color: Color {
        switch self {
        case .effortZone: return .blue
        case .lockedIn: return .green
        case .guessing: return .red
        case .struggling: return .orange
        }
    }
}

struct DataAnalysisView: View {
    @Query(sort: \ReviewRecord.reviewDate)
    private var allReviews: [ReviewRecord]
    @Query(filter: #Predicate<FlashCard> { $0.isTrashed != true })
    private var allCards: [FlashCard]
    @State private var trendRange: TrendRange = .month
    @State private var showWordsAtRiskInfo = false
    @State private var showAccuracyInfo = false
    @State private var selectedZone: EngagementZone = .effortZone
    @State private var showEngagementInfo = false

    var body: some View {
        List {
            Section { vocabularyGrowthSection.subtleSectionGlow() }
            Section { learningVelocitySection.subtleSectionGlow() }
            Section { accuracyTrendSection.subtleSectionGlow() }
            Section { accuracyByPOSSection.subtleSectionGlow() }
            Section { responseTimeTrendSection.subtleSectionGlow() }
            Section { responseTimeByWordSection.subtleSectionGlow() }
            Section { directionComparisonSection.subtleSectionGlow() }
            Section { timeOfDaySection.subtleSectionGlow() }
            Section { activityHeatmapSection.subtleSectionGlow() }
            Section { difficultyInsightsLink.subtleSectionGlow() }
            Section { wordConnectionsLink.subtleSectionGlow() }
            Section { estimatedCompletionSection.subtleSectionGlow() }
            Section { forgettingCurvesLink.subtleSectionGlow() }
            Section { wordsAtRiskSection.subtleSectionGlow() }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.large)
        .enhancedDarkContrast()
    }

    // MARK: - 1. Accuracy Trend

    private var dailyAccuracy: [(date: Date, accuracy: Double, count: Int)] {
        let calendar = Calendar.current
        var byDay: [Date: (correct: Int, total: Int)] = [:]

        for review in allReviews {
            let day = calendar.startOfDay(for: review.reviewDate)
            var entry = byDay[day, default: (correct: 0, total: 0)]
            entry.total += 1
            if review.wasCorrect { entry.correct += 1 }
            byDay[day] = entry
        }

        return byDay.map { day, counts in
            (date: day, accuracy: Double(counts.correct) / Double(counts.total), count: counts.total)
        }.sorted { $0.date < $1.date }
    }

    private var filteredDailyAccuracy: [(date: Date, accuracy: Double, count: Int)] {
        guard let rangeDays = trendRange.days else { return dailyAccuracy }
        let cutoff = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -rangeDays, to: Date()) ?? Date())
        return dailyAccuracy.filter { $0.date >= cutoff }
    }

    private var rollingAverage: [(date: Date, accuracy: Double)] {
        let daily = filteredDailyAccuracy
        guard daily.count >= 2 else { return daily.map { ($0.date, $0.accuracy) } }

        // Clamp rolling window to at most half the data points so short histories still show variation
        let window = min(trendRange.rollingWindow, max(1, daily.count / 2))
        var result: [(date: Date, accuracy: Double)] = []
        for i in 0..<daily.count {
            let windowStart = max(0, i - (window - 1))
            let slice = daily[windowStart...i]
            let totalCorrect = slice.reduce(0) { $0 + Int(Double($1.count) * $1.accuracy) }
            let totalReviews = slice.reduce(0) { $0 + $1.count }
            let avg = totalReviews > 0 ? Double(totalCorrect) / Double(totalReviews) : 0
            result.append((date: daily[i].date, accuracy: avg))
        }
        return result
    }

    /// Dynamic Y-axis range that zooms into the actual data, with some padding
    private var accuracyYDomain: ClosedRange<Double> {
        let values = rollingAverage.map(\.accuracy)
        guard let minVal = values.min(), let maxVal = values.max() else { return 0...1 }
        let spread = maxVal - minVal
        if spread < 0.15 {
            // Data is very tight — show a wider window centered on the data
            let mid = (minVal + maxVal) / 2
            let lo = max(0, mid - 0.15)
            let hi = min(1, lo + 0.30)
            return lo...hi
        }
        // Normal case: pad 10% above and below
        let padding = spread * 0.1
        return max(0, minVal - padding)...min(1, maxVal + padding)
    }

    private var accuracyTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Accuracy Trend")
                        .font(.headline)
                    Button {
                        showAccuracyInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Info")
                }
                Picker("Range", selection: $trendRange) {
                    ForEach(TrendRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }
            .alert("About Accuracy Trend", isPresented: $showAccuracyInfo) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("This measures your accuracy on due review cards — the words the system thinks you're most likely to forget.\n\nAs you master easy words, they stop appearing in reviews. The remaining cards are increasingly the ones you find hardest, so a steady accuracy around 70-80% means the system is working well.\n\nCheck Vocabulary Growth for a metric that shows your cumulative progress.")
            }

            if rollingAverage.count < 2 {
                Text("Not enough data yet. Keep reviewing!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(Array(rollingAverage.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Accuracy", point.accuracy)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Accuracy", point.accuracy)
                        )
                        .foregroundStyle(.blue.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: accuracyYDomain)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accuracyTrendAccessibilityLabel)
            }
        }
    }

    private var accuracyTrendAccessibilityLabel: String {
        guard let latest = rollingAverage.last else { return "Accuracy trend chart" }
        return "Accuracy trend chart. Latest rolling average: \(Int(latest.accuracy * 100)) percent"
    }

    // MARK: - Vocabulary Growth

    private var vocabularyMilestones: [(date: Date, learned: Int, mastered: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build cumulative learned count from introducedDate
        let introduced = allCards
            .filter { $0.status != "new" && $0.introducedDate != nil }
            .sorted { $0.introducedDate! < $1.introducedDate! }

        guard !introduced.isEmpty else { return [] }

        // Build daily mastered count from masteredDate (fall back to lastReviewDate)
        var masteredByDay: [Date: Int] = [:]
        for card in allCards where card.status == "mastered" {
            guard let date = card.masteredDate ?? card.lastReviewDate else { continue }
            let day = calendar.startOfDay(for: date)
            masteredByDay[day, default: 0] += 1
        }

        // Count words introduced per day
        var byDay: [Date: Int] = [:]
        for card in introduced {
            let day = calendar.startOfDay(for: card.introducedDate!)
            byDay[day, default: 0] += 1
        }

        // Fill every day from first event to today so steps stay flat between events
        var eventDays = Set(byDay.keys).union(masteredByDay.keys)
        eventDays.insert(today)
        let sortedDays = eventDays.sorted()
        guard let firstDay = sortedDays.first else { return [] }

        var result: [(date: Date, learned: Int, mastered: Int)] = []
        var cumulativeLearned = 0
        var cumulativeMastered = 0
        var day = firstDay
        while day <= today {
            cumulativeLearned += byDay[day, default: 0]
            cumulativeMastered += masteredByDay[day, default: 0]
            result.append((date: day, learned: cumulativeLearned, mastered: cumulativeMastered))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        return result
    }

    private var vocabularyGrowthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vocabulary Growth")
                .font(.headline)

            if vocabularyMilestones.count < 2 {
                Text("Not enough data yet. Keep learning!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                let latest = vocabularyMilestones.last!
                HStack(spacing: 16) {
                    VStack {
                        Text("\(latest.learned)")
                            .font(.title2.bold())
                            .foregroundStyle(.purple)
                        Text("Learned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    VStack {
                        Text("\(latest.mastered)")
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                        Text("Mastered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Chart {
                    ForEach(Array(vocabularyMilestones.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Words", point.learned),
                            series: .value("Series", "Learned")
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.stepEnd)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Words", point.learned),
                            series: .value("Series", "Learned")
                        )
                        .foregroundStyle(.purple.opacity(0.1))
                        .interpolationMethod(.stepEnd)
                    }
                    ForEach(Array(vocabularyMilestones.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Words", point.mastered),
                            series: .value("Series", "Mastered")
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.stepEnd)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Words", point.mastered),
                            series: .value("Series", "Mastered")
                        )
                        .foregroundStyle(.green.opacity(0.1))
                        .interpolationMethod(.stepEnd)
                    }
                }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Vocabulary growth chart. \(latest.learned) words learned, \(latest.mastered) mastered")

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(.purple).frame(width: 8, height: 8)
                        Text("Learned").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("Mastered").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 2. Accuracy by Part of Speech

    private var accuracyByPOS: [(pos: String, accuracy: Double, total: Int)] {
        var byPOS: [String: (correct: Int, total: Int)] = [:]

        for review in allReviews {
            guard let rawPOS = review.card?.partOfSpeech, !rawPOS.isEmpty else { continue }
            // Normalize: "noun (f)", "noun (m)" → "noun"
            let pos = rawPOS.split(separator: " ").first.map(String.init) ?? rawPOS
            var entry = byPOS[pos, default: (correct: 0, total: 0)]
            entry.total += 1
            if review.wasCorrect { entry.correct += 1 }
            byPOS[pos] = entry
        }

        return byPOS.map { pos, counts in
            (pos: pos, accuracy: Double(counts.correct) / Double(counts.total), total: counts.total)
        }
        .filter { $0.total >= 3 }
        .sorted { $0.accuracy < $1.accuracy }
    }

    private var accuracyByPOSSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accuracy by Word Type")
                .font(.headline)
            Text("Which types give you trouble?")
                .font(.caption)
                .foregroundStyle(.secondary)

            if accuracyByPOS.isEmpty {
                Text("Not enough data yet. Keep reviewing!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(accuracyByPOS, id: \.pos) { item in
                    BarMark(
                        x: .value("Accuracy", item.accuracy),
                        y: .value("Type", item.pos)
                    )
                    .foregroundStyle(barColor(for: item.accuracy))
                    .annotation(position: item.accuracy > 0.25 ? .overlay : .trailing, spacing: 4) {
                        Text("\(Int(item.accuracy * 100))%")
                            .font(.caption2.bold())
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 2)
                            .background(
                                item.accuracy > 0.25 ?
                                AnyShapeStyle(
                                    .linearGradient(
                                        colors: [.clear, Color(uiColor: .systemBackground), Color(uiColor: .systemBackground), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                ) : AnyShapeStyle(.clear)
                            )
                    }
                }
                .chartXScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(accuracyByPOS.count * 36, 100)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(posChartAccessibilityLabel)
            }
        }
    }

    private var posChartAccessibilityLabel: String {
        let items = accuracyByPOS.prefix(3).map { "\($0.pos) \(Int($0.accuracy * 100))%" }
        return "Accuracy by word type chart. \(items.joined(separator: ", "))"
    }

    private func barColor(for accuracy: Double) -> Color {
        if accuracy >= 0.8 { return .green }
        if accuracy >= 0.6 { return .orange }
        return .red
    }

    // MARK: - 3. Study Activity Heatmap

    private var activityByDay: [Date: Int] {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for review in allReviews {
            let day = calendar.startOfDay(for: review.reviewDate)
            counts[day, default: 0] += 1
        }
        return counts
    }

    private var heatmapWeeks: [[Date]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Go back 12 weeks (84 days)
        guard let startDate = calendar.date(byAdding: .day, value: -83, to: today) else {
            return []
        }

        // Align to start of week (Sunday)
        let weekday = calendar.component(.weekday, from: startDate)
        let alignedStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: startDate) ?? startDate

        var weeks: [[Date]] = []
        var currentDate = alignedStart

        while currentDate <= today {
            var week: [Date] = []
            for _ in 0..<7 {
                week.append(currentDate)
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }
            weeks.append(week)
        }

        return weeks
    }

    private var maxDailyCount: Int {
        activityByDay.values.max() ?? 1
    }

    private func heatmapColor(for count: Int) -> Color {
        guard count > 0 else { return Color(.systemGray5) }
        let intensity = min(Double(count) / Double(max(maxDailyCount, 1)), 1.0)
        if intensity > 0.75 { return .green }
        if intensity > 0.5 { return .green.opacity(0.75) }
        if intensity > 0.25 { return .green.opacity(0.5) }
        return .green.opacity(0.3)
    }

    private var activityHeatmapSection: some View {
        let activity = activityByDay
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalDays = activity.keys.count
        let totalReviews = activity.values.reduce(0, +)
        let currentStreak = calculateStudyStreak(activity: activity, today: today, calendar: calendar)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Study Activity")
                .font(.headline)

            HStack(spacing: 16) {
                VStack {
                    Text("\(totalDays)")
                        .font(.title3.bold())
                    Text("Days Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Text("\(totalReviews)")
                        .font(.title3.bold())
                    Text("Total Reviews")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Text("\(currentStreak)")
                        .font(.title3.bold())
                    Text("Current Streak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Heatmap grid
            HStack(alignment: .top, spacing: 3) {
                // Day labels
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(height: 12)
                    }
                }
                .padding(.trailing, 2)

                // Weeks
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(Array(heatmapWeeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                ForEach(week, id: \.self) { date in
                                    let count = activity[date] ?? 0
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(date > today ? Color.clear : heatmapColor(for: count))
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }

            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Study activity heatmap. \(totalDays) days active, \(totalReviews) total reviews, \(currentStreak) day streak")

            // Legend
            HStack(spacing: 4) {
                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                ForEach([0.0, 0.3, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intensity == 0 ? Color(.systemGray5) : .green.opacity(max(intensity, 0.3)))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
    }

    private func calculateStudyStreak(activity: [Date: Int], today: Date, calendar: Calendar) -> Int {
        var streak = 0
        var dayOffset = 0

        if activity[today] == nil {
            dayOffset = -1
        }

        while true {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { break }
            let normalized = calendar.startOfDay(for: date)
            guard activity[normalized] != nil else { break }
            streak += 1
            dayOffset -= 1
        }
        return streak
    }

    // MARK: - 4. Response Time Trend

    private var dailyResponseTime: [(date: Date, avgTime: Double)] {
        let calendar = Calendar.current
        var byDay: [Date: (total: Double, count: Int)] = [:]

        for review in allReviews where review.responseTimeSeconds > 0 && review.responseTimeSeconds < 60 {
            let day = calendar.startOfDay(for: review.reviewDate)
            var entry = byDay[day, default: (total: 0, count: 0)]
            entry.total += review.responseTimeSeconds
            entry.count += 1
            byDay[day] = entry
        }

        return byDay.map { day, data in
            (date: day, avgTime: data.total / Double(data.count))
        }.sorted { $0.date < $1.date }
    }

    private var responseTimeTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Response Time")
                .font(.headline)
            Text("Average seconds per card")
                .font(.caption)
                .foregroundStyle(.secondary)

            if dailyResponseTime.count < 2 {
                Text("Not enough data yet. Keep reviewing!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(Array(dailyResponseTime.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Seconds", point.avgTime)
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Seconds", point.avgTime)
                        )
                        .foregroundStyle(.orange.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYAxisLabel("seconds")
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(responseTimeAccessibilityLabel)
            }
        }
    }

    private var responseTimeAccessibilityLabel: String {
        guard let latest = dailyResponseTime.last else { return "Response time chart" }
        return "Response time chart. Latest average: \(String(format: "%.1f", latest.avgTime)) seconds per card"
    }

    // MARK: - Word Engagement

    private struct WordEngagement {
        let card: FlashCard
        let avgTime: Double
        let accuracy: Double
        let reviewCount: Int
        let zone: EngagementZone
    }

    private var engagementAnalysis: (medianTime: Double, words: [WordEngagement]) {
        var byCard: [String: (card: FlashCard, totalTime: Double, correct: Int, total: Int)] = [:]

        for review in allReviews where review.responseTimeSeconds > 0 && review.responseTimeSeconds < 60 {
            guard let card = review.card else { continue }
            var entry = byCard[card.wordId, default: (card: card, totalTime: 0, correct: 0, total: 0)]
            entry.totalTime += review.responseTimeSeconds
            entry.total += 1
            if review.wasCorrect { entry.correct += 1 }
            byCard[card.wordId] = entry
        }

        let qualified = byCard.values.filter { $0.total >= 3 }
        let avgTimes = qualified.map { $0.totalTime / Double($0.total) }.sorted()
        let median = avgTimes.isEmpty ? 5.0 : avgTimes[avgTimes.count / 2]

        let words = qualified.map { entry in
            let avgTime = entry.totalTime / Double(entry.total)
            let accuracy = Double(entry.correct) / Double(entry.total)
            let isSlow = avgTime >= median
            let isCorrect = accuracy >= 0.6

            let zone: EngagementZone
            switch (isSlow, isCorrect) {
            case (true, true): zone = .effortZone
            case (false, true): zone = .lockedIn
            case (false, false): zone = .guessing
            case (true, false): zone = .struggling
            }

            return WordEngagement(card: entry.card, avgTime: avgTime, accuracy: accuracy, reviewCount: entry.total, zone: zone)
        }

        return (medianTime: median, words: words)
    }

    private func sortedEngagementWords(_ words: [WordEngagement], for zone: EngagementZone) -> [WordEngagement] {
        switch zone {
        case .effortZone, .struggling:
            return words.sorted { $0.avgTime > $1.avgTime }
        case .lockedIn:
            return words.sorted { $0.avgTime < $1.avgTime }
        case .guessing:
            return words.sorted { $0.accuracy < $1.accuracy }
        }
    }

    private var responseTimeByWordSection: some View {
        let analysis = engagementAnalysis
        let grouped = Dictionary(grouping: analysis.words, by: \.zone)
        let selectedWords = sortedEngagementWords(grouped[selectedZone] ?? [], for: selectedZone)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Word Engagement")
                    .font(.headline)
                Button {
                    showEngagementInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info")
            }
            .alert("About Word Engagement", isPresented: $showEngagementInfo) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("This groups your words by how you engage with them.\n\nEffort Zone — You take your time and get it right. Effortful recall builds the strongest memories. These words are actively deepening.\n\nLocked In — Fast and correct. These words are solid in your memory.\n\nGuessing — Quick but wrong. You may be jumping to an answer rather than truly recalling.\n\nStruggling — Slow and wrong. These words need more exposure.\n\nSlow vs fast is based on your personal median response time. Correct vs wrong uses a 60% accuracy threshold.")
            }

            // Summary counts
            HStack(spacing: 0) {
                ForEach(EngagementZone.allCases, id: \.self) { zone in
                    let count = grouped[zone]?.count ?? 0
                    VStack(spacing: 4) {
                        Text("\(count)")
                            .font(.title3.bold())
                            .foregroundStyle(zone.color)
                        Text(zone.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Zone picker
            Picker("Zone", selection: $selectedZone) {
                ForEach(EngagementZone.allCases, id: \.self) { zone in
                    Text(zone.label).tag(zone)
                }
            }
            .pickerStyle(.segmented)

            if analysis.words.isEmpty {
                Text("Not enough data yet. Need at least 3 reviews per word.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if selectedWords.isEmpty {
                Text("No words in this zone yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(selectedWords.prefix(10), id: \.card.wordId) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if let article = item.card.article, !article.isEmpty {
                                    Text(article)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.card.targetText)
                                    .fontWeight(.semibold)
                            }
                            Text(item.card.displaySourceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1fs", item.avgTime))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(item.zone.color)
                            Text("\(Int(item.accuracy * 100))% · \(item.reviewCount) reviews")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Direction Comparison

    private var directionComparison: [(direction: String, accuracy: Double, total: Int)] {
        var byDirection: [String: (correct: Int, total: Int)] = [
            "source_to_target": (correct: 0, total: 0),
            "target_to_source": (correct: 0, total: 0)
        ]

        for review in allReviews {
            let dir = review.cardDirection
            guard !dir.isEmpty else { continue }
            var entry = byDirection[dir, default: (correct: 0, total: 0)]
            entry.total += 1
            if review.wasCorrect { entry.correct += 1 }
            byDirection[dir] = entry
        }

        return byDirection.map { dir, counts in
            let label = dir == "target_to_source" ? "Spanish → English" : "English → Spanish"
            let accuracy = counts.total > 0 ? Double(counts.correct) / Double(counts.total) : 0
            return (direction: label, accuracy: accuracy, total: counts.total)
        }.sorted { $0.direction < $1.direction }
    }

    private var directionComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Direction Comparison")
                .font(.headline)
            Text("Which direction is harder?")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(directionComparison, id: \.direction) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.direction)
                            .font(.subheadline)
                        Spacer()
                        if item.total > 0 {
                            Text("\(Int(item.accuracy * 100))%")
                                .font(.subheadline.bold())
                                .foregroundStyle(barColor(for: item.accuracy))
                            Text("(\(item.total) reviews)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No data yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: item.total > 0 ? item.accuracy : 0)
                        .tint(item.total > 0 ? barColor(for: item.accuracy) : .gray)
                }
            }
        }
    }

    // MARK: - 6. Time of Day Performance

    private var hourlyAccuracy: [(hour: Int, accuracy: Double, count: Int)] {
        var byHour: [Int: (correct: Int, total: Int)] = [:]

        for review in allReviews {
            let hour = Calendar.current.component(.hour, from: review.reviewDate)
            var entry = byHour[hour, default: (correct: 0, total: 0)]
            entry.total += 1
            if review.wasCorrect { entry.correct += 1 }
            byHour[hour] = entry
        }

        return byHour.map { hour, counts in
            (hour: hour, accuracy: Double(counts.correct) / Double(counts.total), count: counts.total)
        }
        .filter { $0.count >= 3 }
        .sorted { $0.hour < $1.hour }
    }

    private var timeOfDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time of Day")
                .font(.headline)
            Text("When do you perform best?")
                .font(.caption)
                .foregroundStyle(.secondary)

            if hourlyAccuracy.isEmpty {
                Text("Not enough data yet. Keep reviewing!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(hourlyAccuracy, id: \.hour) { item in
                    BarMark(
                        x: .value("Hour", item.hour),
                        y: .value("Accuracy", item.accuracy)
                    )
                    .foregroundStyle(barColor(for: item.accuracy))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(formatHour(h))
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(timeOfDayAccessibilityLabel)
            }
        }
    }

    private var timeOfDayAccessibilityLabel: String {
        guard let best = hourlyAccuracy.max(by: { $0.accuracy < $1.accuracy }) else {
            return "Time of day chart"
        }
        return "Time of day accuracy chart. Best performance at \(formatHour(best.hour)) with \(Int(best.accuracy * 100)) percent accuracy"
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }

    // MARK: - 7. Words at Risk

    private var wordsAtRisk: [(card: FlashCard, reason: String)] {
        // Exclude effort zone cards — slow but correct is progress, not risk
        let effortZoneIds = Set(
            engagementAnalysis.words
                .filter { $0.zone == .effortZone }
                .map { $0.card.wordId }
        )

        return allCards
            .filter { $0.status != "new" && !effortZoneIds.contains($0.wordId) }
            .compactMap { card -> (card: FlashCard, reason: String)? in
                // Low ease factor = struggling
                if card.easeFactor < 1.8 && card.totalReviews >= 3 {
                    return (card, "Ease: \(String(format: "%.1f", card.easeFactor))")
                }
                // Low accuracy with enough data
                if card.totalReviews >= 5 {
                    let acc = Double(card.totalCorrect) / Double(card.totalReviews)
                    if acc < 0.5 {
                        return (card, "\(Int(acc * 100))% accuracy")
                    }
                }
                // Lost streak (was doing well, then missed)
                if card.longestStreak >= 3 && card.currentStreak == 0 && card.totalReviews >= 3 {
                    return (card, "Streak broken (was \(card.longestStreak))")
                }
                return nil
            }
            .sorted { $0.card.easeFactor < $1.card.easeFactor }
            .prefix(10)
            .map { $0 }
    }

    private var wordsAtRiskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Words at Risk")
                    .font(.headline)
                Spacer()
                Button {
                    showWordsAtRiskInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info")
            }
            .alert("About Words at Risk", isPresented: $showWordsAtRiskInfo) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("A word lands here if any of these are true:\n\nLow Ease — The ease factor dropped below 1.8. Ease starts at 2.5 for every word and adjusts after each review: correct answers raise it, incorrect answers lower it.\n\nLow Accuracy — Less than 50% correct after 5+ reviews.\n\nStreak Broken — You had 3+ correct answers in a row, then got it wrong.")
            }
            Text("Words you're struggling with most")
                .font(.caption)
                .foregroundStyle(.secondary)

            if wordsAtRisk.isEmpty {
                Text("No struggling words detected. Nice work!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(wordsAtRisk, id: \.card.wordId) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                if let article = item.card.article, !article.isEmpty {
                                    Text(article)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.card.targetText)
                                    .fontWeight(.semibold)
                            }
                            Text(item.card.displaySourceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - 8. Learning Velocity

    private var dailyLearningVelocity: [(date: Date, wordsPerDay: Double)] {
        let calendar = Calendar.current
        let learned = allCards
            .filter { $0.introducedDate != nil }
            .sorted { $0.introducedDate! < $1.introducedDate! }

        guard !learned.isEmpty else { return [] }

        // Count words introduced per day
        var countByDay: [Date: Int] = [:]
        for card in learned {
            let day = calendar.startOfDay(for: card.introducedDate!)
            countByDay[day, default: 0] += 1
        }

        // Fill in zero-days between first and last
        let sortedDays = countByDay.keys.sorted()
        guard let firstDay = sortedDays.first, let lastDay = sortedDays.last else { return [] }

        var allDays: [(date: Date, count: Int)] = []
        var day = firstDay
        while day <= lastDay {
            allDays.append((date: day, count: countByDay[day, default: 0]))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        guard allDays.count >= 2 else { return allDays.map { ($0.date, Double($0.count)) } }

        // 7-day rolling average
        let window = min(7, max(1, allDays.count / 2))
        var result: [(date: Date, wordsPerDay: Double)] = []
        for i in 0..<allDays.count {
            let start = max(0, i - (window - 1))
            let slice = allDays[start...i]
            let avg = Double(slice.reduce(0) { $0 + $1.count }) / Double(slice.count)
            result.append((date: allDays[i].date, wordsPerDay: avg))
        }

        return result
    }

    // MARK: - 9. Estimated Completion

    private struct CompletionEstimate {
        let totalWords: Int
        let introducedCount: Int
        let remaining: Int
        let wordsPerDay: Double
        let estimatedDate: Date?
        let percentComplete: Int
    }

    private var completionEstimate: CompletionEstimate {
        let totalWords = allCards.count
        let introduced = allCards.filter { $0.introducedDate != nil }
        let introducedCount = introduced.count
        let remaining = totalWords - introducedCount

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let sortedDates = introduced.compactMap { $0.introducedDate }.sorted()
        let firstDate = sortedDates.first.map { calendar.startOfDay(for: $0) }

        var daysSinceStart = 0
        if let first = firstDate {
            daysSinceStart = max(calendar.dateComponents([.day], from: first, to: today).day ?? 0, 1)
        }

        let wordsPerDay = daysSinceStart > 0 ? Double(introducedCount) / Double(daysSinceStart) : 0
        let daysLeft = wordsPerDay > 0 ? Int(ceil(Double(remaining) / wordsPerDay)) : 0
        let estDate = wordsPerDay > 0 ? calendar.date(byAdding: .day, value: daysLeft, to: today) : nil
        let pct = totalWords > 0 ? Int(Double(introducedCount) / Double(totalWords) * 100) : 0

        return CompletionEstimate(
            totalWords: totalWords, introducedCount: introducedCount,
            remaining: remaining, wordsPerDay: wordsPerDay,
            estimatedDate: estDate, percentComplete: pct
        )
    }

    private var estimatedCompletionSection: some View {
        let est = completionEstimate
        return VStack(alignment: .leading, spacing: 12) {
            Text("Estimated Completion")
                .font(.headline)
            Text("When you'll finish the deck at your current pace")
                .font(.caption)
                .foregroundStyle(.secondary)

            if est.introducedCount < 5 {
                Text("Learn a few more words to see your estimate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if est.remaining == 0 {
                completionCelebrationView(totalWords: est.totalWords)
            } else {
                completionDetailsView(est: est)
            }
        }
    }

    private func completionCelebrationView(totalWords: Int) -> some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("All \(totalWords) words introduced!")
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func completionDetailsView(est: CompletionEstimate) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(est.introducedCount) of \(est.totalWords) words")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(est.percentComplete)%")
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                }
                ProgressView(value: Double(est.introducedCount), total: Double(est.totalWords))
                    .tint(.blue)
            }

            HStack(spacing: 0) {
                VStack {
                    Text(String(format: "%.1f", est.wordsPerDay))
                        .font(.title3.bold())
                    Text("words/day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    Text("\(est.remaining)")
                        .font(.title3.bold())
                    Text("remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    if let date = est.estimatedDate {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.title3.bold())
                            .foregroundStyle(.blue)
                    }
                    Text("est. finish")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Navigation Links

    private var forgettingCurvesLink: some View {
        NavigationLink {
            ForgettingCurveView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundStyle(.purple)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word Retention")
                        .font(.headline)
                    Text("See how your memory strength changes over time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var difficultyInsightsLink: some View {
        NavigationLink {
            DifficultyInsightsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Difficulty Insights")
                        .font(.headline)
                    Text("Discover patterns in what trips you up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var wordConnectionsLink: some View {
        NavigationLink {
            WordGraphView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word Connections")
                        .font(.headline)
                    Text("Explore how your words relate to each other")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 8. Learning Velocity

    private var learningVelocitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learning Velocity")
                .font(.headline)
            Text("New words per day (7-day average)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if dailyLearningVelocity.count < 2 {
                Text("Not enough data yet. Keep learning!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(Array(dailyLearningVelocity.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Words/Day", point.wordsPerDay)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Words/Day", point.wordsPerDay)
                        )
                        .foregroundStyle(.purple.opacity(0.1))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(velocityAccessibilityLabel)
            }
        }
    }

    private var velocityAccessibilityLabel: String {
        guard let latest = dailyLearningVelocity.last else { return "Learning velocity chart" }
        return "Learning velocity chart. Current pace: \(String(format: "%.1f", latest.wordsPerDay)) words per day"
    }
}
