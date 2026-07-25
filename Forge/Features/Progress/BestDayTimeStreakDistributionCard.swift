import SwiftUI
import Charts

/// Progress page's premium "Best Day/Time & Streak Distribution" card —
/// new this pass, directly modeled on Habitify's day-of-week/time-of-day/
/// streak-length analytics (a real competitor's paid differentiator, per
/// explicit instruction to build a genuine reason to pay, not filler), but
/// built from this app's own data shapes rather than copying that UI.
///
/// Three sub-visualizations, all responding to one shared scope picker
/// (All Habits / a category / an individual habit) — **a judgment call**:
/// the spec's streak-length histogram wasn't explicitly asked to share the
/// day-of-week/time-of-day scope, but leaving it permanently unscoped next
/// to two scoped charts would read as inconsistent, so all three share it.
///
/// 1. **Completion rate by day of week** — for each weekday, the share of
///    applicable habit-days (a habit only counts on days on/after its own
///    `startDate`) that were completed, over a bounded lookback window.
///    This is the "when do you tend to fall off" view.
/// 2. **When you log completions** — a time-of-day histogram (Morning /
///    Afternoon / Evening / Night) built from `Completion.loggedAt` on
///    days actually completed. **A judgment call worth flagging
///    explicitly**: this can only ever show *when completions happen*, not
///    "when you tend to miss" — a miss has no timestamp at all, so a true
///    "time you fall off" view isn't derivable from this app's data model
///    as it stands. Day-of-week (above) is what actually answers the
///    "when do you fall off" half of the ask; this chart answers a
///    related but distinct question.
/// 3. **Streak length distribution** — a histogram of every completed
///    streak run's length (not just the current one), bucketed at 1–6 /
///    7–29 / 30–99 / 100+ days — boundaries deliberately aligned to this
///    app's own existing Milestone streak thresholds (7/30/100) rather
///    than arbitrary round numbers, so "a 30-day streak" means the same
///    thing here as it does on the Milestones badge it would have earned.
///
/// **Bounded lookback window, a deliberate scaling tradeoff, flagged
/// rather than silent**: all three charts share one 90-day lookback
/// (`lookbackDays`), computed from one already-fetched, already-bounded
/// `completions` array handed down by `ProgressScreenView.reload()` — the
/// same "one query, not one per view" discipline the rest of this screen
/// already follows. The cost: a streak that started before that 90-day
/// window (or a day-of-week/time-of-day pattern from further back) is
/// undercounted/invisible until enough new data accumulates inside the
/// window — a real limitation, not an oversight, traded deliberately
/// against adding a second, potentially much larger unbounded-per-habit
/// fetch for this one premium card.
///
/// **Gating**: reads `EntitlementService.isPremiumUnlocked()` — always
/// `false` today (`StubEntitlementService`, §10's real StoreKit 2 flow is
/// Phase 4+). When locked, shows the real charts blurred underneath a
/// lock/"Premium" overlay rather than a placeholder — no purchase flow
/// wired up yet, per instruction to build the gate, not the paywall.
struct BestDayTimeStreakDistributionCard: View {
    let habits: [Habit]
    /// Bounded lookback window of completions, already fetched by the
    /// caller — see the type doc comment on why this is shared/bounded
    /// rather than a fresh unbounded fetch per sub-visualization.
    let completions: [Completion]
    let isPremiumUnlocked: Bool

    private static let lookbackDays = 90

    private enum Scope: Hashable {
        case all
        case category(HabitCategory)
        case habit(Habit.ID)
    }

    @State private var scope: Scope = .all

    private enum TimeBucket: CaseIterable, Hashable {
        case morning, afternoon, evening, night

        var label: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .evening: "Evening"
            case .night: "Night"
            }
        }

        static func bucket(forHour hour: Int) -> TimeBucket {
            switch hour {
            case 5..<12: .morning
            case 12..<17: .afternoon
            case 17..<22: .evening
            default: .night
            }
        }
    }

    private struct WeekdayRate: Identifiable {
        let weekday: Int
        let label: String
        let rate: Double
        var id: Int { weekday }
    }

    private struct StreakBucket: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    private var lookbackWindow: (start: Date, end: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -(Self.lookbackDays - 1), to: today) ?? today
        return (start, today)
    }

    private var scopedHabits: [Habit] {
        let active = habits.filter { !$0.isArchived }
        switch scope {
        case .all: return active
        case .category(let category): return active.filter { $0.category == category }
        case .habit(let id): return active.filter { $0.id == id }
        }
    }

    private var scopedCompletedDatesByHabit: [Habit.ID: Set<Date>] {
        let ids = Set(scopedHabits.map(\.id))
        return Dictionary(grouping: completions.filter { $0.isComplete && ids.contains($0.habitID) }, by: \.habitID)
            .mapValues { Set($0.map(\.date)) }
    }

    private var scopeLabel: String {
        switch scope {
        case .all: "All Habits"
        case .category(let category): category.displayName
        case .habit(let id): habits.first(where: { $0.id == id })?.title ?? "Habit"
        }
    }

    /// Day-of-week completion rate — walks the lookback window day by day
    /// (bounded to `lookbackDays` × `scopedHabits.count`, a small, already
    /// in-memory scan, not a query) so each weekday's denominator only
    /// counts days a habit actually existed for.
    private var dayOfWeekRates: [WeekdayRate] {
        let calendar = Calendar.current
        let (start, end) = lookbackWindow
        let completedByHabit = scopedCompletedDatesByHabit
        var done = [Int: Int](), total = [Int: Int]()

        var day = start
        while day <= end {
            let weekday = calendar.component(.weekday, from: day)
            for habit in scopedHabits where habit.startDate <= day && (habit.endDate.map { day <= $0 } ?? true) {
                total[weekday, default: 0] += 1
                if completedByHabit[habit.id]?.contains(day) == true {
                    done[weekday, default: 0] += 1
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let symbols = calendar.veryShortWeekdaySymbols
        return (1...7).map { weekday in
            let totalCount = total[weekday] ?? 0
            let rate = totalCount > 0 ? Double(done[weekday] ?? 0) / Double(totalCount) : 0
            return WeekdayRate(weekday: weekday, label: symbols[weekday - 1], rate: rate)
        }
    }

    private var timeOfDayDistribution: [(bucket: TimeBucket, proportion: Double)] {
        let ids = Set(scopedHabits.map(\.id))
        let completedLogs = completions.filter { $0.isComplete && ids.contains($0.habitID) }
        guard !completedLogs.isEmpty else {
            return TimeBucket.allCases.map { ($0, 0) }
        }
        var counts: [TimeBucket: Int] = [:]
        for completion in completedLogs {
            let hour = Calendar.current.component(.hour, from: completion.loggedAt)
            counts[.bucket(forHour: hour), default: 0] += 1
        }
        let total = Double(completedLogs.count)
        return TimeBucket.allCases.map { ($0, Double(counts[$0] ?? 0) / total) }
    }

    private var streakBuckets: [StreakBucket] {
        let (start, end) = lookbackWindow
        let completedByHabit = scopedCompletedDatesByHabit
        let lengths = scopedHabits.flatMap { habit in
            StreakMath.allStreakLengths(
                completedDates: completedByHabit[habit.id] ?? [],
                from: max(start, Calendar.current.startOfDay(for: habit.startDate)),
                to: end,
                vacationRange: VacationSettings.currentRange()
            )
        }
        func count(_ range: ClosedRange<Int>) -> Int { lengths.filter { range.contains($0) }.count }
        return [
            StreakBucket(label: "1–6d", count: count(1...6)),
            StreakBucket(label: "7–29d", count: count(7...29)),
            StreakBucket(label: "30–99d", count: count(30...99)),
            StreakBucket(label: "100d+", count: lengths.filter { $0 >= 100 }.count),
        ]
    }

    var body: some View {
        ProgressCard(title: "Best Day/Time & Streak Distribution") {
            if isPremiumUnlocked {
                content
            } else {
                lockedPreview
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                scopePicker
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Completion Rate by Day of Week")
                    .font(.subheadline.weight(.medium))
                Chart(dayOfWeekRates) { entry in
                    BarMark(x: .value("Day", entry.label), y: .value("Rate", entry.rate))
                        .foregroundStyle(.blue)
                }
                .chartYScale(domain: 0...1)
                .frame(height: 100)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("When You Log Completions")
                    .font(.subheadline.weight(.medium))
                Chart(timeOfDayDistribution, id: \.bucket) { entry in
                    BarMark(x: .value("Time", entry.bucket.label), y: .value("Share", entry.proportion))
                        .foregroundStyle(.purple)
                }
                .chartYScale(domain: 0...1)
                .frame(height: 100)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Streak Length Distribution")
                    .font(.subheadline.weight(.medium))
                if streakBuckets.allSatisfy({ $0.count == 0 }) {
                    Text("Not enough completed streaks yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(streakBuckets) { bucket in
                        BarMark(x: .value("Length", bucket.label), y: .value("Count", bucket.count))
                            .foregroundStyle(.indigo)
                    }
                    .frame(height: 100)
                }
            }
        }
    }

    private var scopePicker: some View {
        Menu {
            Button("All Habits") { scope = .all }
            ForEach(HabitCategory.allCases) { category in
                Button(category.displayName) { scope = .category(category) }
            }
            let activeHabits = habits.filter { !$0.isArchived }
            if !activeHabits.isEmpty {
                Menu("Individual Habits") {
                    ForEach(activeHabits) { habit in
                        Button(habit.title) { scope = .habit(habit.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(scopeLabel)
                Image(systemName: "chevron.up.chevron.down")
            }
            .font(.caption.weight(.medium))
        }
    }

    private var lockedPreview: some View {
        ZStack {
            content
                .blur(radius: 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                Text("Premium")
                    .font(.subheadline.weight(.semibold))
                Text("See your best days, times, and streak history.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

#Preview {
    BestDayTimeStreakDistributionCard(habits: [], completions: [], isPremiumUnlocked: false)
        .padding()
}
