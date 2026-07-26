import Foundation

/// Orchestrates §11 Milestone detection against §8's streak/points rules —
/// the only place that decides "has a new badge been earned," reading
/// through `HabitRepository`/`MilestoneRepository` like everything else in
/// this app talks to storage.
///
/// Two triggers call into this, per the "check after logging, or a
/// reasonable trigger" latitude:
/// - `afterCompletionLogged(habit:)` — called right after `HomeView` upserts
///   a completion. Checks that one habit's streak, its category's streak,
///   and (piggybacked, since it's cheap when there's nothing new) runs the
///   points/category-challenge catch-up.
/// - `runCatchUp()` — called when Progress/Milestones screens appear, so
///   points and challenge state stay current even on a day the user opens
///   the app without logging anything new.
///
/// Every check here is scoped to what actually changed (one habit's own
/// history, one category's habits, or a bounded day-range since the last
/// catch-up) rather than rescanning the whole app's data — see each
/// function's comment for its specific bound.
struct MilestoneEngine: Sendable {
    let habitRepository: HabitRepository
    let milestoneRepository: MilestoneRepository

    static let streakThresholds = [7, 30, 100, 365]
    static let pointsThresholds = [50, 100, 250, 500, 1000]
    /// Category-streak detection scans day-by-day since the category's
    /// oldest habit started, capped at this many days back — long enough to
    /// clear the largest streak threshold above with room to spare, without
    /// letting the scan grow unbounded for a category used for years.
    static let categoryStreakLookbackDays = 400

    func afterCompletionLogged(habit: Habit) async {
        await checkHabitStreak(habit)
        await checkCategoryStreak(habit.category)
        await catchUpPointsAndChallenges()
    }

    func runCatchUp() async {
        await catchUpPointsAndChallenges()
    }

    // MARK: - Habit streak

    /// Scoped to one habit's own history — `fetchCompletions(habitID:from:to:)`
    /// bounded to `[habit.startDate, now]`, the same query the habit detail
    /// page uses.
    private func checkHabitStreak(_ habit: Habit) async {
        guard let completions = try? await habitRepository.fetchCompletions(
            habitID: habit.id, from: habit.startDate, to: .now
        ) else { return }

        let completedDates = Set(completions.filter(\.isComplete).map(\.date))
        let scan = StreakMath.scan(
            completedDates: completedDates,
            from: Calendar.current.startOfDay(for: habit.startDate),
            to: .now,
            vacationRange: VacationSettings.currentRange(),
            thresholds: Self.streakThresholds
        )

        for threshold in Self.streakThresholds {
            guard let earnedDate = scan.firstDateReachingLength[threshold] else { continue }
            let milestone = Milestone(
                kind: .habitStreak,
                scopeID: habit.id.uuidString,
                value: threshold,
                title: "\(threshold)-Day Streak",
                subtitle: "\(habit.title) completed \(threshold) days in a row.",
                earnedDate: earnedDate,
                colorToken: habit.color.rawValue
            )
            try? await milestoneRepository.award(milestone)
        }

        await revokeInvalidStreakMilestones(kind: .habitStreak, scopeID: habit.id.uuidString, currentLongest: scan.longest)
    }

    // MARK: - Category streak

    /// Scoped to one category's habits over a bounded lookback window (see
    /// `categoryStreakLookbackDays`) — fetches the shared, all-habits range
    /// query once and filters to this category's habit IDs client-side,
    /// the same pattern the Habit Trends card uses.
    private func checkCategoryStreak(_ category: HabitCategory) async {
        guard let allHabits = try? await habitRepository.fetchAll() else { return }
        let categoryHabits = allHabits.filter { $0.category == category && !$0.isArchived }
        guard !categoryHabits.isEmpty else { return }

        let calendar = Calendar.current
        let earliestStart = calendar.startOfDay(for: categoryHabits.map(\.startDate).min() ?? .now)
        let boundedStart = calendar.date(byAdding: .day, value: -Self.categoryStreakLookbackDays, to: .now) ?? earliestStart
        let lookbackStart = max(earliestStart, boundedStart)

        guard let completions = try? await habitRepository.fetchCompletions(from: lookbackStart, to: .now) else { return }
        let habitIDs = Set(categoryHabits.map(\.id))
        let byHabitAndDate = Dictionary(grouping: completions.filter { habitIDs.contains($0.habitID) }, by: \.habitID)
            .mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.date, $0.isComplete) }) }

        var categoryCompletedDates: Set<Date> = []
        var day = lookbackStart
        while day <= .now {
            let activeToday = categoryHabits.filter { $0.startDate <= day && ($0.endDate.map { day <= $0 } ?? true) }
            if !activeToday.isEmpty, activeToday.allSatisfy({ byHabitAndDate[$0.id]?[day] == true }) {
                categoryCompletedDates.insert(day)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let scan = StreakMath.scan(
            completedDates: categoryCompletedDates,
            from: lookbackStart,
            to: .now,
            vacationRange: VacationSettings.currentRange(),
            thresholds: Self.streakThresholds
        )

        for threshold in Self.streakThresholds {
            guard let earnedDate = scan.firstDateReachingLength[threshold] else { continue }
            let milestone = Milestone(
                kind: .categoryStreak,
                scopeID: category.rawValue,
                value: threshold,
                title: "\(category.displayName) \(threshold)-Day Streak",
                subtitle: "Every \(category.displayName) habit completed \(threshold) days in a row.",
                earnedDate: earnedDate,
                colorToken: category.rawValue
            )
            try? await milestoneRepository.award(milestone)
        }

        await revokeInvalidStreakMilestones(kind: .categoryStreak, scopeID: category.rawValue, currentLongest: scan.longest)
    }

    /// Self-healing counterpart to the award loops above: if a previously-
    /// awarded streak badge's length now exceeds the longest streak the
    /// current data actually supports — most commonly because a completion
    /// that helped reach it was reset (see `HomeView.resetHabit`) — the
    /// badge is no longer earned and is revoked. Runs as part of every
    /// normal `checkHabitStreak`/`checkCategoryStreak` pass (not just after
    /// a reset specifically), matching this engine's existing "self-heal on
    /// every check, not just the triggering path" approach elsewhere.
    ///
    /// `fetchAll()` here is a full scan of every awarded milestone, not a
    /// bounded query — deliberately: unlike completions (one row per habit
    /// per day, genuinely unbounded over years of use), milestones only
    /// grow one row per *achievement*, a naturally small, slow-growing set
    /// even for a long-term user, so this doesn't carry the same scaling
    /// risk this app's other bounded-query standard is guarding against.
    private func revokeInvalidStreakMilestones(kind: MilestoneKind, scopeID: String, currentLongest: Int) async {
        guard let existing = try? await milestoneRepository.fetchAll() else { return }
        let invalid = existing.filter { $0.kind == kind && $0.scopeID == scopeID && $0.value > currentLongest }
        for milestone in invalid {
            try? await milestoneRepository.revoke(dedupeKey: milestone.dedupeKey)
        }
    }

    // MARK: - Points + category challenges

    private func catchUpPointsAndChallenges() async {
        await catchUpPoints()
        await checkCategoryChallenges()
    }

    /// Advances the points ledger from wherever it last left off through
    /// yesterday (today is never evaluated — its day hasn't finished yet).
    /// Normally a no-op (already caught up); the only large pass is the
    /// one-time backfill from a fresh install's earliest habit start date.
    private func catchUpPoints() async {
        guard let allHabits = try? await habitRepository.fetchAll() else { return }
        var ledger = (try? await milestoneRepository.fetchPointsLedger()) ?? .empty
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }

        let startDay: Date
        if let last = ledger.lastEvaluatedDay {
            guard let next = calendar.date(byAdding: .day, value: 1, to: last) else { return }
            startDay = next
        } else {
            guard let earliest = allHabits.map(\.startDate).min() else { return }
            startDay = calendar.startOfDay(for: earliest)
        }
        guard startDay <= yesterday else { return }

        guard let completions = try? await habitRepository.fetchCompletions(from: startDay, to: yesterday) else { return }
        let byHabitAndDate = Dictionary(grouping: completions, by: \.habitID)
            .mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.date, $0.isComplete) }) }

        var newlyCrossed: [(threshold: Int, date: Date)] = []
        var day = startDay
        while day <= yesterday {
            if !VacationSettings.isVacationDay(day) {
                let activeHabits = allHabits.filter {
                    !$0.isArchived && $0.startDate <= day && ($0.endDate.map { day <= $0 } ?? true)
                }
                for habit in activeHabits {
                    let done = byHabitAndDate[habit.id]?[day] == true
                    ledger.cumulativePoints += done ? 1 : -1
                }
            }
            ledger.lastEvaluatedDay = day
            for threshold in Self.pointsThresholds
            where ledger.cumulativePoints >= threshold && !newlyCrossed.contains(where: { $0.threshold == threshold }) {
                newlyCrossed.append((threshold, day))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        try? await milestoneRepository.savePointsLedger(ledger)

        for crossed in newlyCrossed {
            let milestone = Milestone(
                kind: .points,
                scopeID: "",
                value: crossed.threshold,
                title: "\(crossed.threshold) Points",
                subtitle: "Reached \(crossed.threshold) total points.",
                earnedDate: crossed.date,
                colorToken: "points"
            )
            try? await milestoneRepository.award(milestone)
        }
    }

    /// Only ever checks the single most-recently-fully-elapsed calendar
    /// month, not every unclaimed past month — a deliberate scope cut: a
    /// user who hasn't opened the app in several months would only get
    /// credit for the latest one. Reasonable for how this app is actually
    /// used; walking every past month would cost a query per month per
    /// category for what should be a rare gap.
    private func checkCategoryChallenges() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)),
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart),
              let lastMonthEnd = calendar.date(byAdding: .day, value: -1, to: currentMonthStart)
        else { return }

        let periodKeyFormatter = DateFormatter()
        periodKeyFormatter.dateFormat = "yyyy-MM"
        let periodKey = periodKeyFormatter.string(from: lastMonthStart)

        let monthTitleFormatter = DateFormatter()
        monthTitleFormatter.dateFormat = "MMMM yyyy"
        let monthTitle = monthTitleFormatter.string(from: lastMonthStart)

        guard let allHabits = try? await habitRepository.fetchAll(),
              let existingMilestones = try? await milestoneRepository.fetchAll()
        else { return }
        let existingKeys = Set(existingMilestones.map(\.dedupeKey))

        for category in HabitCategory.allCases {
            let key = Milestone.dedupeKey(kind: .categoryChallenge, scopeID: category.rawValue, value: 0, periodKey: periodKey)
            guard !existingKeys.contains(key) else { continue }

            let activeDuringMonth = allHabits.filter {
                $0.category == category && $0.startDate <= lastMonthEnd && ($0.endDate.map { lastMonthStart <= $0 } ?? true)
            }
            guard !activeDuringMonth.isEmpty else { continue }

            guard let completions = try? await habitRepository.fetchCompletions(from: lastMonthStart, to: lastMonthEnd) else { continue }
            let habitIDs = Set(activeDuringMonth.map(\.id))
            let byHabitAndDate = Dictionary(grouping: completions.filter { habitIDs.contains($0.habitID) }, by: \.habitID)
                .mapValues { Dictionary(uniqueKeysWithValues: $0.map { ($0.date, $0.isComplete) }) }

            var allDaysSucceeded = true
            var day = lastMonthStart
            while day <= lastMonthEnd {
                if !VacationSettings.isVacationDay(day) {
                    let activeToday = activeDuringMonth.filter { $0.startDate <= day && ($0.endDate.map { day <= $0 } ?? true) }
                    if !activeToday.allSatisfy({ byHabitAndDate[$0.id]?[day] == true }) {
                        allDaysSucceeded = false
                        break
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }

            guard allDaysSucceeded else { continue }
            let milestone = Milestone(
                kind: .categoryChallenge,
                scopeID: category.rawValue,
                value: 0,
                periodKey: periodKey,
                title: "\(category.displayName) Challenge",
                subtitle: "Every \(category.displayName) habit, every day, in \(monthTitle).",
                earnedDate: lastMonthEnd,
                colorToken: category.rawValue
            )
            try? await milestoneRepository.award(milestone)
        }
    }
}
