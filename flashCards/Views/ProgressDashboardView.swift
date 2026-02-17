import SwiftUI
import SwiftData
import Charts

struct ProgressDashboardView: View {
    @Query private var allCards: [FlashCard]
    @Query(sort: \ReviewRecord.reviewDate, order: .reverse)
    private var recentReviews: [ReviewRecord]

    private var newCount: Int {
        allCards.filter { $0.status == "new" }.count
    }

    private var learningCount: Int {
        allCards.filter { $0.status == "learning" }.count
    }

    private var masteredCount: Int {
        allCards.filter { $0.status == "mastered" }.count
    }

    private var todayReviews: [ReviewRecord] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return recentReviews.filter { $0.reviewDate >= startOfToday }
    }

    private var todayAccuracy: Double {
        let today = todayReviews
        guard !today.isEmpty else { return 0 }
        let correct = today.filter(\.wasCorrect).count
        return Double(correct) / Double(today.count)
    }

    private var dueNowCount: Int {
        let now = Date()
        return allCards.filter {
            $0.nextReviewDate != nil && $0.nextReviewDate! <= now && $0.status != "new"
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    overviewChart
                    todayStatsSection
                    upcomingSection
                }
                .padding()
            }
            .navigationTitle("")
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

            HStack(spacing: 0) {
                legendItem(color: .blue, label: "New", count: newCount)
                legendItem(color: .orange, label: "Learning", count: learningCount)
                legendItem(color: .green, label: "Mastered", count: masteredCount)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    private func legendItem(color: Color, label: String, count: Int) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
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
                statCard(title: "Reviewed", value: "\(todayReviews.count)", icon: "bolt.fill")
                statCard(title: "Accuracy", value: todayReviews.isEmpty ? "-" : "\(Int(todayAccuracy * 100))%", icon: "target")
                statCard(title: "Due Now", value: "\(dueNowCount)", icon: "clock")
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scheduled Reviews")
                .font(.headline)

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
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
    }
}
