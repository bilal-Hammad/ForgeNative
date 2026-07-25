import SwiftUI
import Charts

/// Progress screen (APP_REDESIGN_SPEC.md §6), redesigned this pass to drop
/// the ring metaphor entirely — see `ConsistencyHeatmapCard`'s doc comment
/// for why "Today's Rings" became a heatmap instead of staying a bigger
/// `RingsView`. Card order, top to bottom:
/// - Consistency Heatmap (replaces Today's Rings)
/// - Streak chart
/// - Category Breakdown
/// - Best Day/Time & Streak Distribution (**premium**, new this pass)
/// - Recent Activity
/// - Milestones (§11 — see `MilestoneEngine`/`Badge3DView`)
/// - Habit Trends
///
/// Also keeps the grouped, tappable habits list below the cards (not one of
/// the spec's named cards, but a pre-existing, independently useful section
/// — left in place rather than removed as part of this redesign), each row
/// opening `HabitDetailView` for that single habit's own history/streak/
/// rate stats.
///
/// **Streak card now shows a real number.** The previous version's doc
/// comment flagged this as a known placeholder ("today-only signal (0 or
/// 1)... depends on §8's points/streak system, not built in this pass") —
/// §8 (`StreakMath`/`MilestoneEngine`) exists now, so this redesign wires
/// the card up to it: the largest of the three categories' *current*
/// streaks (a day only counts for a category if every one of that
/// category's active habits was completed — the same definition
/// `MilestoneEngine.checkCategoryStreak` already uses for category-streak
/// Milestone badges), so this card's number always agrees with what
/// Milestones would actually award.
///
/// The Streak chart's 7-day bars still come from a real
/// `fetchCompletions(from:to:)` range query against persisted history (see
/// `SwiftDataHabitRepository`) — so as the app actually gets used day over
/// day, past days fill in with real rates instead of staying hardcoded at 0.
///
/// **Category Breakdown** is now a real weekly proportional chart (a single
/// stacked bar, not a donut/pie — deliberately, to stay unambiguously
/// non-circular) instead of the old plain today-only count list.
///
/// **Habit Trends** (§6) compares completion rate per category (Good/Bad/
/// To-Do — the same grouping used everywhere else on this screen, rather
/// than a per-habit breakdown that'd need its own habit picker UI) over two
/// adjacent, equal-length windows: "current" vs. "previous". The window
/// length adapts to how much history actually exists instead of assuming a
/// full month is available — it's `min(30, totalDaysOfHistory / 2)`, so a
/// brand-new install with e.g. 6 days of logging gets an honest 3-vs-3-day
/// comparison rather than a 30-vs-30 chart that's mostly empty bars. Below 4
/// total days of history (not enough to form two non-degenerate windows) the
/// card shows a plain "not enough data yet" state instead of a misleading
/// chart. Reuses the exact same `fetchCompletions(from:to:)` query the
/// Streak chart uses — one fixed 60-day-bounded range fetch (bounded, not
/// "fetch everything," per the CLAUDE.md Production Scaling Standards; 60
/// days is enough to cover the capped 30-vs-30 case) — with the two windows'
/// rates computed client-side over that single already-fetched, already-
/// indexed result set rather than issuing a second query.
///
/// Named `ProgressScreenView`, not `ProgressView` — SwiftUI already has a
/// built-in `ProgressView` (the spinner/progress-bar control), and shadowing
/// it with our own type would be a confusing, error-prone collision anywhere
/// this module wants the real one.
struct ProgressScreenView: View {
    @Environment(\.habitRepository) private var habitRepository
    @Environment(\.milestoneRepository) private var milestoneRepository
    @Environment(\.milestoneEngine) private var milestoneEngine
    @Environment(\.entitlementService) private var entitlementService
    @State private var habits: [Habit] = []
    @State private var last7DaysCompletions: [Completion] = []
    @State private var trendsCompletions: [Completion] = []
    @State private var recentCompletions: [Completion] = []
    @State private var recentMilestones: [Milestone] = []
    @State private var earliestHabitStart: Date?
    @State private var heatmapRatesByDay: [Date: (good: Double, bad: Double, todo: Double)] = [:]
    @State private var streakLookbackCompletions: [Completion] = []
    @State private var analyticsCompletions: [Completion] = []
    @State private var isPremiumUnlocked = false

    /// Past 7 days ending today, from a real range query (see type doc).
    private var last7Days: [(label: String, rate: Double)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            let day = calendar.startOfDay(for: date)
            let label = calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            guard !habits.isEmpty else { return (label, 0) }
            let doneCount = last7DaysCompletions.filter { $0.date == day && $0.isComplete }.count
            return (label, Double(doneCount) / Double(habits.count))
        }
    }

    /// This week's completed-habit count per category, from the same
    /// `last7DaysCompletions` the Streak chart already fetched.
    private var weeklyCategoryTotals: [(category: HabitCategory, count: Int)] {
        let categoryByHabitID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.category) })
        let completedThisWeek = last7DaysCompletions.filter(\.isComplete)
        return HabitCategory.allCases.map { category in
            let count = completedThisWeek.filter { categoryByHabitID[$0.habitID] == category }.count
            return (category, count)
        }
    }

    /// A day only counts toward a category's streak if *every* active habit
    /// in that category was completed that day — the same rule
    /// `MilestoneEngine.checkCategoryStreak` uses, duplicated here (rather
    /// than exposed from that private method) since it's a small, bounded,
    /// already-in-memory computation over `streakLookbackCompletions`, not
    /// a new query.
    private func categoryCurrentStreak(_ category: HabitCategory) -> Int {
        let categoryHabits = habits.filter { $0.category == category && !$0.isArchived }
        guard !categoryHabits.isEmpty else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let earliestStart = calendar.startOfDay(for: categoryHabits.map(\.startDate).min() ?? today)
        let habitIDs = Set(categoryHabits.map(\.id))
        let byHabitAndDate = Dictionary(grouping: streakLookbackCompletions.filter { habitIDs.contains($0.habitID) }, by: \.habitID)
            .mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.date, $0.isComplete) }) }

        var categoryCompletedDates: Set<Date> = []
        var day = earliestStart
        while day <= today {
            let activeToday = categoryHabits.filter { $0.startDate <= day && ($0.endDate.map { day <= $0 } ?? true) }
            if !activeToday.isEmpty, activeToday.allSatisfy({ byHabitAndDate[$0.id]?[day] == true }) {
                categoryCompletedDates.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return StreakMath.currentStreak(completedDates: categoryCompletedDates, referenceDate: today, vacationRange: VacationSettings.currentRange())
    }

    private var bestCategoryStreak: (category: HabitCategory, days: Int)? {
        HabitCategory.allCases
            .map { (category: $0, days: categoryCurrentStreak($0)) }
            .max { $0.days < $1.days }
            .flatMap { $0.days > 0 ? $0 : nil }
    }

    /// Two adjacent, equal-length comparison windows derived from however
    /// much history is actually in `trendsCompletions` — see the type doc
    /// for why the window length adapts instead of assuming 30 days exist.
    private var trendsState: TrendsState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let earliestDate = trendsCompletions.map(\.date).min() else {
            return .notEnoughData
        }
        let totalDays = (calendar.dateComponents([.day], from: earliestDate, to: today).day ?? 0) + 1
        let periodDays = min(30, totalDays / 2)
        guard periodDays >= 2,
              let currentStart = calendar.date(byAdding: .day, value: -(periodDays - 1), to: today),
              let previousEnd = calendar.date(byAdding: .day, value: -periodDays, to: today),
              let previousStart = calendar.date(byAdding: .day, value: -(periodDays * 2 - 1), to: today)
        else {
            return .notEnoughData
        }

        func rate(for category: HabitCategory, from start: Date, to end: Date) -> Double {
            let categoryHabits = habits.filter { $0.category == category }
            guard !categoryHabits.isEmpty else { return 0 }
            let habitIDs = Set(categoryHabits.map(\.id))
            let doneCount = trendsCompletions.filter {
                habitIDs.contains($0.habitID) && $0.isComplete && $0.date >= start && $0.date <= end
            }.count
            return Double(doneCount) / Double(categoryHabits.count * periodDays)
        }

        let trends = HabitCategory.allCases.map { category in
            CategoryTrend(
                category: category,
                currentRate: rate(for: category, from: currentStart, to: today),
                previousRate: rate(for: category, from: previousStart, to: previousEnd)
            )
        }
        return .available(periodDays: periodDays, trends: trends)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ConsistencyHeatmapCard(ratesByDay: heatmapRatesByDay, earliestDataDate: earliestHabitStart)
                    streakCard
                    categoryBreakdownCard
                    BestDayTimeStreakDistributionCard(
                        habits: habits,
                        completions: analyticsCompletions,
                        isPremiumUnlocked: isPremiumUnlocked
                    )
                    recentActivityCard
                    milestonesCard
                    habitTrendsCard
                    habitsListSection
                }
                .padding()
            }
            .navigationTitle("Progress")
            .task { await reload() }
        }
    }

    private var streakCard: some View {
        ProgressCard(title: "Streak") {
            VStack(alignment: .leading, spacing: 12) {
                if let bestCategoryStreak {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(bestCategoryStreak.days)")
                            .font(.title2.weight(.semibold))
                        Text(bestCategoryStreak.days == 1 ? "day streak" : "days")
                            .foregroundStyle(.secondary)
                        Text("· \(bestCategoryStreak.category.displayName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(bestCategoryStreak.category.accentColor)
                    }
                } else {
                    Text("0 day streak")
                        .font(.title2.weight(.semibold))
                }

                Chart(last7Days, id: \.label) { entry in
                    BarMark(
                        x: .value("Day", entry.label),
                        y: .value("Completion", entry.rate)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYScale(domain: 0...1)
                .frame(height: 120)
            }
        }
    }

    /// A single proportional stacked bar over this week's completions, not
    /// a donut/pie — a donut is visually still a ring, which this redesign
    /// avoids everywhere, even though the spec text allowed either.
    private var categoryBreakdownCard: some View {
        ProgressCard(title: "Category Breakdown") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Share of this week's completions, by category")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let total = max(1, weeklyCategoryTotals.reduce(0) { $0 + $1.count })
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(weeklyCategoryTotals, id: \.category) { entry in
                            if entry.count > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(entry.category.accentColor)
                                    .frame(width: geometry.size.width * CGFloat(entry.count) / CGFloat(total))
                            }
                        }
                    }
                }
                .frame(height: 22)

                VStack(spacing: 8) {
                    ForEach(weeklyCategoryTotals, id: \.category) { entry in
                        HStack {
                            Circle()
                                .fill(entry.category.accentColor)
                                .frame(width: 8, height: 8)
                            Text(entry.category.displayName)
                            Spacer()
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                            Text("(\(Int((Double(entry.count) / Double(total) * 100).rounded()))%)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var recentActivityCard: some View {
        ProgressCard(title: "Recent Activity") {
            if recentCompletions.isEmpty {
                Text("Nothing logged yet today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(recentCompletions) { completion in
                        HStack {
                            Text(habits.first(where: { $0.id == completion.habitID })?.title ?? "Habit")
                            Spacer()
                            Text(completion.loggedAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var habitTrendsCard: some View {
        ProgressCard(title: "Habit Trends") {
            switch trendsState {
            case .notEnoughData:
                Text("Not enough data yet — keep logging and trends will show up here after a few more days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .available(let periodDays, let trends):
                VStack(alignment: .leading, spacing: 12) {
                    Text("Last \(periodDays) days vs. the \(periodDays) days before that")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Chart {
                        ForEach(trends) { trend in
                            BarMark(
                                x: .value("Category", trend.category.displayName),
                                y: .value("Rate", trend.previousRate)
                            )
                            .foregroundStyle(by: .value("Period", "Previous"))
                            .position(by: .value("Period", "Previous"))

                            BarMark(
                                x: .value("Category", trend.category.displayName),
                                y: .value("Rate", trend.currentRate)
                            )
                            .foregroundStyle(by: .value("Period", "Current"))
                            .position(by: .value("Period", "Current"))
                        }
                    }
                    .chartYScale(domain: 0...1)
                    .chartLegend(position: .bottom)
                    .frame(height: 140)

                    VStack(spacing: 8) {
                        ForEach(trends) { trend in
                            HStack {
                                Text(trend.category.displayName)
                                Spacer()
                                trendDeltaLabel(trend.delta)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Horizontal preview strip (APP_REDESIGN_SPEC.md §11) — flat
    /// `MilestoneBadgePreview` tiles, not live `Badge3DView`s; see that
    /// type's doc comment for why the real interactive 3D badge is reserved
    /// for the single-badge detail page. Tapping a tile jumps straight to
    /// its detail page; "See All" opens the full grouped list.
    private var milestonesCard: some View {
        ProgressCard(title: "Milestones") {
            if recentMilestones.isEmpty {
                Text("No milestones yet — keep building streaks to earn your first badge.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(recentMilestones) { milestone in
                                NavigationLink {
                                    MilestoneDetailView(milestone: milestone)
                                } label: {
                                    VStack(spacing: 6) {
                                        MilestoneBadgePreview(color: milestone.color, size: 56)
                                        Text(milestone.title)
                                            .font(.caption2)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(width: 76)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    NavigationLink {
                        MilestonesListView()
                    } label: {
                        HStack {
                            Text("See All")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
    }

    private func trendDeltaLabel(_ delta: Double) -> some View {
        let points = Int((delta * 100).rounded())
        return HStack(spacing: 4) {
            Image(systemName: points > 0 ? "arrow.up.right" : (points < 0 ? "arrow.down.right" : "minus"))
            Text("\(abs(points)) pt")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(points > 0 ? .green : (points < 0 ? .red : .secondary))
    }

    /// Grouped, active-only habit list (archived habits already have their
    /// own dedicated screen off Profile) — tapping a row opens
    /// `HabitDetailView` for that single habit's history/streak/rate stats.
    private var habitsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Habits")
                .font(.title2.weight(.bold))
                .padding(.horizontal, 4)

            ForEach(HabitCategory.allCases) { category in
                let categoryHabits = habits.filter { $0.category == category && !$0.isArchived }
                if !categoryHabits.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.displayName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(categoryHabits) { habit in
                                NavigationLink {
                                    HabitDetailView(habit: habit)
                                } label: {
                                    HabitListRow(habit: habit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reload() async {
        habits = (try? await habitRepository.fetchAll()) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        earliestHabitStart = habits.map(\.startDate).min()

        let weekAgo = calendar.date(byAdding: .day, value: -6, to: .now) ?? .now
        last7DaysCompletions = (try? await habitRepository.fetchCompletions(from: weekAgo, to: .now)) ?? []

        let sixtyDaysAgo = calendar.date(byAdding: .day, value: -59, to: .now) ?? .now
        trendsCompletions = (try? await habitRepository.fetchCompletions(from: sixtyDaysAgo, to: .now)) ?? []

        recentCompletions = (try? await habitRepository.fetchRecentCompletions(limit: 10)) ?? []

        await milestoneEngine.runCatchUp()
        recentMilestones = (try? await milestoneRepository.fetchRecent(limit: 8)) ?? []

        // Consistency Heatmap: one bounded 140-day query, aggregated inside
        // the repository — see `ConsistencyHeatmapCard`'s doc comment.
        let heatmapStart = calendar.date(byAdding: .day, value: -139, to: today) ?? today
        heatmapRatesByDay = (try? await habitRepository.fetchCategoryCompletionRates(habits: habits, from: heatmapStart, to: today)) ?? [:]

        // Streak card: bounded wide enough to match
        // `MilestoneEngine.categoryStreakLookbackDays`, so this screen's
        // current-streak number always agrees with what Milestones awards.
        let streakLookbackStart: Date = {
            let bounded = calendar.date(byAdding: .day, value: -MilestoneEngine.categoryStreakLookbackDays, to: today) ?? today
            if let earliestHabitStart { return max(bounded, calendar.startOfDay(for: earliestHabitStart)) }
            return bounded
        }()
        streakLookbackCompletions = (try? await habitRepository.fetchCompletions(from: streakLookbackStart, to: today)) ?? []

        // Best Day/Time & Streak Distribution: its own, shorter bounded
        // window — see that card's doc comment for the deliberate tradeoff.
        let analyticsStart = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        analyticsCompletions = (try? await habitRepository.fetchCompletions(from: analyticsStart, to: today)) ?? []

        isPremiumUnlocked = await entitlementService.isPremiumUnlocked()
    }
}

private struct CategoryTrend: Identifiable {
    let category: HabitCategory
    let currentRate: Double
    let previousRate: Double
    var id: HabitCategory { category }
    var delta: Double { currentRate - previousRate }
}

private enum TrendsState {
    case notEnoughData
    case available(periodDays: Int, trends: [CategoryTrend])
}

private struct HabitListRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.iconSystemName)
                .font(.title3)
                .foregroundStyle(habit.color.color)
                .frame(width: 28)

            Text(habit.title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            if habit.isHealthKitTracked {
                HealthKitBadgeView()
                    .font(.caption)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Internal (not file-private) so `HabitDetailView` can reuse the same card
/// chrome instead of duplicating it.
struct ProgressCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ProgressScreenView()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
