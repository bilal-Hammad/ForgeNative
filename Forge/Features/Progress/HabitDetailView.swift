import SwiftUI
import Charts

/// Per-habit detail page, reachable from Progress's grouped habits list.
///
/// All stats here derive from one bounded, habit-scoped fetch —
/// `fetchCompletions(habitID:from:to:)` for the range [habit.startDate, now]
/// — rather than an unbounded "all completions ever" query. Bounding by the
/// habit's own start date is the honest maximum range (nothing can exist
/// before it existed), and filtering by habitID at the query level (via
/// `CompletionModel`'s existing `(habitID, date)` index) keeps this scoped
/// to one habit's rows rather than pulling every habit's history for the
/// same range — the same scoping discipline as the Streak and Habit Trends
/// cards, just with one more dimension (habit) applied at the DB layer
/// instead of filtered client-side.
///
/// Streak/all-time-rate/running-total are recomputed from that one fetch on
/// each visit rather than read from a cached field — acceptable at this
/// scale since a single habit's lifetime history is at most one row per day
/// (a few thousand rows even after a decade), a small, cheap in-memory
/// scan. Flagged per the CLAUDE.md Production Scaling Standards: if this
/// page becomes a hot/frequently-refreshed path (e.g. backing a widget)
/// rather than an occasional user-initiated detail view, a maintained
/// `currentStreak`/`longestStreak` field on `HabitModel`, updated
/// incrementally in `upsertCompletion` instead of recomputed here, would be
/// the correct next step — not needed yet at this scale.
///
/// The heatmap's *display* grid is capped at 20 weeks (140 days) regardless
/// of how long the habit's real history is — a fixed, readable size, not a
/// rendering cost that grows unbounded with habit age. The underlying fetch
/// itself isn't capped to those 140 days, since the streak/all-time cards
/// below the heatmap need the full since-start-date range.
///
/// Completion/streak stats reflect `Completion.isComplete` exactly as Home
/// sets it — for time-based habits (`timeMode != .none`), that's only ever
/// set via long-press force-complete, not by the ordinary tap (which just
/// records `startedAt`), so a time-based habit that's only ever been
/// "started" and never force-completed will show a real, honest 0% rate
/// here rather than a fabricated one. That mirrors Home's existing
/// treatment of time-based habits, not a gap introduced by this page.
struct HabitDetailView: View {
    let habit: Habit

    @Environment(\.habitRepository) private var habitRepository
    @State private var completions: [Completion] = []

    private var completionsByDate: [Date: Completion] {
        Dictionary(uniqueKeysWithValues: completions.map { ($0.date, $0) })
    }

    private var completedDates: Set<Date> {
        Set(completions.filter(\.isComplete).map(\.date))
    }

    private var habitStartDay: Date {
        Calendar.current.startOfDay(for: habit.startDate)
    }

    /// Both streak stats — and every Milestone streak-threshold check —
    /// share `StreakMath`, so this page and the badges you can earn always
    /// agree on what "streak" means, vacation-pause included.
    private var currentStreak: Int {
        StreakMath.currentStreak(completedDates: completedDates, vacationRange: VacationSettings.currentRange())
    }

    private var longestStreak: Int {
        StreakMath.scan(
            completedDates: completedDates,
            from: habitStartDay,
            to: .now,
            vacationRange: VacationSettings.currentRange()
        ).longest
    }

    private func completionRate(trailingDays: Int) -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(trailingDays - 1), to: today) else { return 0 }
        let effectiveStart = max(windowStart, habitStartDay)
        let totalDays = (calendar.dateComponents([.day], from: effectiveStart, to: today).day ?? 0) + 1
        guard totalDays > 0 else { return 0 }
        let doneCount = completedDates.filter { $0 >= effectiveStart && $0 <= today }.count
        return Double(doneCount) / Double(totalDays)
    }

    private var allTimeRate: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let totalDays = max(1, (calendar.dateComponents([.day], from: habitStartDay, to: today).day ?? 0) + 1)
        return Double(completedDates.count) / Double(totalDays)
    }

    private var runningTotal: Double {
        completions.reduce(0) { $0 + $1.count }
    }

    private var averagePerDay: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let totalDays = max(1, (calendar.dateComponents([.day], from: habitStartDay, to: today).day ?? 0) + 1)
        return runningTotal / Double(totalDays)
    }

    /// Last 30 days of tracked value, clipped to not go before the habit
    /// actually started — feeds the quantity chart below.
    private var recentQuantityHistory: [(date: Date, count: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<30).reversed().compactMap { offset -> (Date, Double)? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today), day >= habitStartDay else {
                return nil
            }
            return (day, completionsByDate[day]?.count ?? 0)
        }
    }

    private var heatmapDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<140).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    private func heatmapColor(for day: Date) -> Color {
        guard day >= habitStartDay else { return Color(.systemGray6) }
        if habit.goal > 1 {
            let count = completionsByDate[day]?.count ?? 0
            guard count > 0 else { return Color(.systemGray5) }
            let ratio = min(1, count / habit.goal)
            return habit.color.color.opacity(0.25 + ratio * 0.75)
        } else {
            return completedDates.contains(day) ? habit.color.color : Color(.systemGray5)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                heatmapCard
                streakCard
                completionRateCard
                if habit.goal > 1 {
                    quantityCard
                }
            }
            .padding()
        }
        .navigationTitle(habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.iconSystemName)
                .font(.largeTitle)
                .foregroundStyle(habit.color.color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(habit.title)
                        .font(.title3.weight(.semibold))
                    if habit.isHealthKitTracked {
                        HealthKitBadgeView()
                            .font(.caption)
                    }
                }
                Text(habit.category.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heatmapCard: some View {
        ProgressCard(title: "History") {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 7), spacing: 3) {
                    ForEach(heatmapDays, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(heatmapColor(for: day))
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var streakCard: some View {
        ProgressCard(title: "Streaks") {
            HStack {
                statTile(label: "Current", value: "\(currentStreak)", unit: currentStreak == 1 ? "day" : "days")
                Spacer()
                statTile(label: "Longest", value: "\(longestStreak)", unit: longestStreak == 1 ? "day" : "days")
            }
        }
    }

    private var completionRateCard: some View {
        ProgressCard(title: "Completion Rate") {
            HStack {
                statTile(label: "This Week", value: "\(Int((completionRate(trailingDays: 7) * 100).rounded()))%", unit: nil)
                Spacer()
                statTile(label: "This Month", value: "\(Int((completionRate(trailingDays: 30) * 100).rounded()))%", unit: nil)
                Spacer()
                statTile(label: "All-Time", value: "\(Int((allTimeRate * 100).rounded()))%", unit: nil)
            }
        }
    }

    private var quantityCard: some View {
        ProgressCard(title: "Quantity") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    statTile(label: "Avg / Day", value: formatted(averagePerDay), unit: habit.unit.displayName.lowercased())
                    Spacer()
                    statTile(label: "Avg / Week", value: formatted(averagePerDay * 7), unit: habit.unit.displayName.lowercased())
                    Spacer()
                    statTile(label: "Total", value: formatted(runningTotal), unit: habit.unit.displayName.lowercased())
                }

                Chart {
                    ForEach(recentQuantityHistory, id: \.date) { entry in
                        LineMark(
                            x: .value("Date", entry.date),
                            y: .value(habit.unit.displayName, entry.count)
                        )
                        .foregroundStyle(habit.color.color)
                    }
                    RuleMark(y: .value("Goal", habit.goal))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 140)
            }
        }
    }

    private func statTile(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func reload() async {
        completions = (try? await habitRepository.fetchCompletions(habitID: habit.id, from: habit.startDate, to: .now)) ?? []
    }
}

#Preview {
    NavigationStack {
        HabitDetailView(habit: Habit(title: "Read", category: .good, goal: 20, unit: .minutes, step: 5))
            .environment(\.habitRepository, InMemoryHabitRepository())
    }
}
