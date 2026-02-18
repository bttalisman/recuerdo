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

struct DataAnalysisView: View {
    @Query(sort: \ReviewRecord.reviewDate)
    private var allReviews: [ReviewRecord]
    @Query private var allCards: [FlashCard]
    @State private var trendRange: TrendRange = .month

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                accuracyTrendSection
                forgettingCurvesLink
                responseTimeTrendSection
                accuracyByPOSSection
                directionComparisonSection
                timeOfDaySection
                wordsAtRiskSection
                difficultyInsightsLink
                activityHeatmapSection
                learningVelocitySection
                wordConnectionsLink
            }
            .padding()
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.large)
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

        let window = trendRange.rollingWindow
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

    private var accuracyTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accuracy Trend")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $trendRange) {
                    ForEach(TrendRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
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
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v * 100))%")
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - 2. Accuracy by Part of Speech

    private var accuracyByPOS: [(pos: String, accuracy: Double, total: Int)] {
        var byPOS: [String: (correct: Int, total: Int)] = [:]

        for review in allReviews {
            let pos = review.card?.partOfSpeech ?? "unknown"
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
                    .annotation(position: .trailing, spacing: 4) {
                        Text("\(Int(item.accuracy * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
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
                    Text("Day Streak")
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
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    private func calculateStudyStreak(activity: [Date: Int], today: Date, calendar: Calendar) -> Int {
        var streak = 0
        var date = today

        // Check if studied today; if not, start from yesterday
        if activity[date] == nil {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }

        while activity[date] != nil {
            streak += 1
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
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
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
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
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
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
                        x: .value("Hour", formatHour(item.hour)),
                        y: .value("Accuracy", item.accuracy)
                    )
                    .foregroundStyle(barColor(for: item.accuracy))
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
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }

    // MARK: - 7. Words at Risk

    private var wordsAtRisk: [(card: FlashCard, reason: String)] {
        allCards
            .filter { $0.status != "new" }
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
            Text("Words at Risk")
                .font(.headline)
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
                            Text(item.card.sourceText)
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
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    // MARK: - 8. Learning Velocity

    private var cumulativeWordsLearned: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let learned = allCards
            .filter { $0.introducedDate != nil }
            .sorted { $0.introducedDate! < $1.introducedDate! }

        guard !learned.isEmpty else { return [] }

        var byDay: [(date: Date, count: Int)] = []
        var cumulative = 0
        var currentDay: Date?

        for card in learned {
            let day = calendar.startOfDay(for: card.introducedDate!)
            cumulative += 1
            if day != currentDay {
                if currentDay != nil && byDay.last?.date != currentDay {
                    byDay.append((date: currentDay!, count: cumulative - 1))
                }
                currentDay = day
            }
            byDay = byDay.filter { $0.date != day }
            byDay.append((date: day, count: cumulative))
        }

        return byDay
    }

    // MARK: - Navigation Links

    private var forgettingCurvesLink: some View {
        NavigationLink {
            ForgettingCurveView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Forgetting Curves")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("See how your memory strength changes over time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
        }
        .buttonStyle(.plain)
    }

    private var difficultyInsightsLink: some View {
        NavigationLink {
            DifficultyInsightsView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Difficulty Insights")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Discover patterns in what trips you up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
        }
        .buttonStyle(.plain)
    }

    private var wordConnectionsLink: some View {
        NavigationLink {
            WordGraphView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Word Connections")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Explore how your words relate to each other")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 8. Learning Velocity

    private var learningVelocitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learning Velocity")
                .font(.headline)
            Text("Cumulative words learned over time")
                .font(.caption)
                .foregroundStyle(.secondary)

            if cumulativeWordsLearned.count < 2 {
                Text("Not enough data yet. Keep learning!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(Array(cumulativeWordsLearned.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Words", point.count)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.stepEnd)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Words", point.count)
                        )
                        .foregroundStyle(.purple.opacity(0.1))
                        .interpolationMethod(.stepEnd)
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }
}
