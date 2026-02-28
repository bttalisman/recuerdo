import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Query(filter: #Predicate<FlashCard> { $0.isTrashed != true })
    private var allCards: [FlashCard]
    @Query private var decks: [DeckMetadata]
    @Environment(\.modelContext) private var modelContext
    @State private var todayReviewCount: Int = 0
    @State private var todayCorrectCount: Int = 0
    @State private var weekReviewCount: Int = 0

    private var newCount: Int {
        allCards.filter { $0.status == "new" }.count
    }

    private var learningCount: Int {
        allCards.filter { $0.status == "learning" }.count
    }

    private var masteredCount: Int {
        allCards.filter { $0.status == "mastered" }.count
    }

    private var todayAccuracy: Double {
        guard todayReviewCount > 0 else { return 0 }
        return Double(todayCorrectCount) / Double(todayReviewCount)
    }

    private var dueNowCount: Int {
        let now = Date()
        return allCards.filter {
            $0.nextReviewDate != nil && $0.nextReviewDate! <= now && $0.status != "new"
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section { overviewChart.subtleSectionGlow() }
                Section { todayStatsSection.subtleSectionGlow() }
                Section { workloadSection.subtleSectionGlow() }
                Section { pipelineSection.subtleSectionGlow() }
                Section { upcomingSection.subtleSectionGlow() }

                Section {
                    NavigationLink {
                        DataAnalysisView()
                    } label: {
                        HStack {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.title3)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Detailed Analysis")
                                    .font(.headline)
                                Text("Trends, patterns, and activity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .subtleSectionGlow()
                }
            }
            .navigationTitle("")
            .enhancedDarkContrast()
            .onAppear { loadReviewCounts() }
        }
    }

    private func loadReviewCounts() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        let container = modelContext.container
        Task.detached {
            let context = ModelContext(container)

            // Today's stats
            var todayDescriptor = FetchDescriptor<ReviewRecord>(
                predicate: #Predicate { $0.reviewDate >= startOfToday }
            )
            todayDescriptor.propertiesToFetch = [\.wasCorrect]
            let todayRecords = (try? context.fetch(todayDescriptor)) ?? []
            let todayTotal = todayRecords.count
            let todayCorrect = todayRecords.filter(\.wasCorrect).count

            // Week count
            var weekDescriptor = FetchDescriptor<ReviewRecord>(
                predicate: #Predicate { $0.reviewDate >= weekAgo }
            )
            weekDescriptor.propertiesToFetch = [\.reviewDate]
            let weekTotal = (try? context.fetchCount(weekDescriptor)) ?? 0

            await MainActor.run {
                todayReviewCount = todayTotal
                todayCorrectCount = todayCorrect
                weekReviewCount = weekTotal
            }
        }
    }

    private var overviewChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            Chart {
                SectorMark(angle: .value("New", newCount), innerRadius: .ratio(0.6))
                    .foregroundStyle(.blue)
                SectorMark(angle: .value("Learning", learningCount), innerRadius: .ratio(0.6))
                    .foregroundStyle(.orange)
                SectorMark(angle: .value("Mastered", masteredCount), innerRadius: .ratio(0.6))
                    .foregroundStyle(.green)
            }
            .frame(height: 200)
            .chartBackground { _ in
                VStack {
                    Text("\(allCards.count)")
                        .font(.title.bold())
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Overview chart. \(allCards.count) total words: \(newCount) new, \(learningCount) learning, \(masteredCount) mastered")

            HStack(spacing: 0) {
                legendItem(color: .blue, label: "New", count: newCount)
                legendItem(color: .orange, label: "Learning", count: learningCount)
                legendItem(color: .green, label: "Mastered", count: masteredCount)
            }
        }
    }

    private func legendItem(color: Color, label: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.headline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var todayStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            HStack(spacing: 16) {
                statCard(title: "Reviewed", value: "\(todayReviewCount)", icon: "bolt.fill")
                statCard(title: "Accuracy", value: todayReviewCount == 0 ? "-" : "\(Int(todayAccuracy * 100))%", icon: "target")
                statCard(title: "Due Now", value: "\(dueNowCount)", icon: "clock")
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workload Health

    private struct WorkloadData {
        let overdueCount: Int
        let avgDailyReviews: Double
        let newWordsPerDay: Int
        let projectedDailyLoad: Int
        let status: WorkloadStatus
    }

    private enum WorkloadStatus {
        case onTrack, slipping, overloaded

        var label: String {
            switch self {
            case .onTrack: return "On Track"
            case .slipping: return "Falling Behind"
            case .overloaded: return "Overloaded"
            }
        }

        var icon: String {
            switch self {
            case .onTrack: return "checkmark.circle.fill"
            case .slipping: return "exclamationmark.triangle.fill"
            case .overloaded: return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .onTrack: return .green
            case .slipping: return .orange
            case .overloaded: return .red
            }
        }
    }

    private var workload: WorkloadData {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // Overdue: reviews that were due before today and haven't been done
        let overdueCount = allCards.filter {
            guard let next = $0.nextReviewDate, $0.status != "new" else { return false }
            return next < today
        }.count

        // Average daily reviews over the last 7 days
        let avgDaily = Double(weekReviewCount) / 7.0

        // New words per day setting
        let newPerDay = decks.first?.newWordsAccumulationRate ?? 10

        // Project daily review load: each active card comes back roughly every
        // (average interval) days. As a simpler proxy, count reviews scheduled
        // for the next 7 days and average.
        let weekOut = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let upcomingWeek = allCards.filter {
            guard let next = $0.nextReviewDate, $0.status != "new" else { return false }
            return next >= today && next < weekOut
        }.count
        let projectedDaily = (upcomingWeek + overdueCount + 7) / 7 // +7 to round up

        // Determine status
        let status: WorkloadStatus
        if overdueCount > Int(avgDaily) * 3 || overdueCount > 100 {
            status = .overloaded
        } else if overdueCount > Int(max(avgDaily, 1)) {
            status = .slipping
        } else {
            status = .onTrack
        }

        return WorkloadData(
            overdueCount: overdueCount,
            avgDailyReviews: avgDaily,
            newWordsPerDay: newPerDay,
            projectedDailyLoad: projectedDaily,
            status: status
        )
    }

    private var workloadSection: some View {
        let w = workload
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workload")
                    .font(.headline)
                Spacer()
                Label(w.status.label, systemImage: w.status.icon)
                    .font(.subheadline.bold())
                    .foregroundStyle(w.status.color)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(w.overdueCount)")
                        .font(.title2.bold())
                        .foregroundStyle(w.overdueCount > 0 ? .red : .green)
                    Text("Overdue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text(String(format: "%.0f", w.avgDailyReviews))
                        .font(.title2.bold())
                    Text("Avg/Day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("~\(w.projectedDailyLoad)")
                        .font(.title2.bold())
                    Text("Coming/Day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            if w.status == .overloaded {
                Text("You have a large backlog. Consider pausing new words until you catch up.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if w.status == .slipping {
                Text("Reviews are starting to pile up. Try to clear your overdue cards today.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if w.projectedDailyLoad > 0 {
                Text("At \(w.newWordsPerDay) new words/day, expect around \(w.projectedDailyLoad) reviews daily.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Learning Pipeline

    private struct PipelineData {
        let introducedPerWeek: Double
        let masteredPerWeek: Double
        let learningPileSize: Int
        let weeksOfData: Int
    }

    private var pipeline: PipelineData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Find the earliest introduced date to know how many weeks of data we have
        let introducedCards = allCards.filter { $0.introducedDate != nil }
        let sortedIntro = introducedCards.compactMap(\.introducedDate).sorted()
        let firstIntro = sortedIntro.first.map { calendar.startOfDay(for: $0) }

        let totalDays: Int
        if let first = firstIntro {
            totalDays = max(calendar.dateComponents([.day], from: first, to: today).day ?? 1, 1)
        } else {
            totalDays = 1
        }
        let weeks = max(Double(totalDays) / 7.0, 1.0)

        // Words introduced total
        let totalIntroduced = introducedCards.count

        // Words mastered total
        let totalMastered = allCards.filter { $0.status == "mastered" }.count

        // Currently in "learning" status
        let learningPile = allCards.filter { $0.status == "learning" }.count

        return PipelineData(
            introducedPerWeek: Double(totalIntroduced) / weeks,
            masteredPerWeek: Double(totalMastered) / weeks,
            learningPileSize: learningPile,
            weeksOfData: Int(weeks)
        )
    }

    private var pipelineSection: some View {
        let p = pipeline
        return VStack(alignment: .leading, spacing: 12) {
            Text("Learning Pipeline")
                .font(.headline)
            pipelineContent(p: p)
        }
    }

    private func pipelineContent(p: PipelineData) -> some View {
        let ratio = p.introducedPerWeek > 0 ? p.masteredPerWeek / p.introducedPerWeek : 0
        let isEarlyDays = p.weeksOfData < 4

        // Don't assign alarming health labels during the warm-up period
        let healthLabel: String
        let healthColor: Color
        if isEarlyDays {
            healthLabel = "Gathering data"
            healthColor = .blue
        } else if p.masteredPerWeek < 1 {
            healthLabel = "Slow mastery"
            healthColor = .orange
        } else if ratio >= 0.6 {
            healthLabel = "Healthy flow"
            healthColor = .green
        } else if ratio >= 0.3 {
            healthLabel = "Building up"
            healthColor = .yellow
        } else {
            healthLabel = "Bottleneck"
            healthColor = .orange
        }

        return VStack(spacing: 14) {
            // Flow diagram: introduced → learning → mastered
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", p.introducedPerWeek))
                        .font(.title3.bold())
                    Text("new/wk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 2) {
                    Text("\(p.learningPileSize)")
                        .font(.title3.bold())
                        .foregroundStyle(!isEarlyDays && p.learningPileSize > 100 ? .orange : .primary)
                    Text("learning")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", p.masteredPerWeek))
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                    Text("mastered/wk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack {
                Circle()
                    .fill(healthColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(healthLabel)
                    .font(.caption.bold())
                    .foregroundStyle(healthColor)
            }

            if isEarlyDays {
                Text("It takes a few weeks for words to reach mastery. Keep your current pace and check back after week 4 — that's when this data becomes meaningful.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if ratio < 0.3 {
                Text("Words are entering faster than they're mastered. Consider reducing new words/day to let your learning pile shrink.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var upcomingDays: [(label: String, count: Int)] {
        let calendar = Calendar.current
        return (0..<7).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

            let count: Int
            if dayOffset == 0 {
                count = allCards.filter {
                    $0.nextReviewDate != nil &&
                    $0.nextReviewDate! < dayEnd &&
                    $0.status != "new"
                }.count
            } else {
                count = allCards.filter {
                    $0.nextReviewDate != nil &&
                    $0.nextReviewDate! >= dayStart &&
                    $0.nextReviewDate! < dayEnd
                }.count
            }

            let label: String
            if dayOffset == 0 {
                label = "Today"
            } else if dayOffset == 1 {
                label = "Tomorrow"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                label = formatter.string(from: date)
            }

            return (label, count)
        }
    }

    @State private var showSchedulingInfo = false

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scheduled Reviews")
                    .font(.headline)
                Spacer()
                Button {
                    showSchedulingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Info")
            }
            .alert("About Scheduled Reviews", isPresented: $showSchedulingInfo) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("Recuerdo uses spaced repetition to schedule your reviews. Words you get right are shown less often; words you struggle with come back sooner. Over time, the intervals grow and words move to mastered status. This is based on the SM-2 algorithm, the same approach used by Anki.")
            }

            ForEach(Array(upcomingDays.enumerated()), id: \.offset) { index, day in
                HStack {
                    Text(day.label)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                        .fontWeight(index == 0 ? .medium : .regular)
                    Spacer()
                    Text("\(day.count)")
                        .fontWeight(.medium)
                        .foregroundStyle(day.count > 0 ? .primary : .tertiary)
                }
            }
        }
    }
}
