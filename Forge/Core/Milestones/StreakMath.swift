import Foundation

/// Pure, vacation-aware streak calculations shared by `HabitDetailView`
/// (per-habit stats) and `MilestoneEngine` (streak-threshold detection) —
/// pulled into one place specifically so both read the exact same notion of
/// "streak," including §8's vacation-pause rule, rather than two ad-hoc
/// copies quietly drifting apart.
///
/// Per APP_REDESIGN_SPEC.md §8: vacation-mode days neither count toward nor
/// break a streak — they're transparent. A habit not completed on an
/// ordinary (non-vacation) day breaks the run; a habit not completed on a
/// vacation day just pauses it.
enum StreakMath {
    /// Streak ending at `referenceDate` (normally `.now`), walking backward.
    /// If `referenceDate`'s day isn't completed yet, that's treated as "not
    /// over yet" rather than a break — so an ongoing streak doesn't read as
    /// 0 just because today hasn't been logged.
    static func currentStreak(
        completedDates: Set<Date>,
        referenceDate: Date = .now,
        vacationRange: ClosedRange<Date>? = nil
    ) -> Int {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: referenceDate)
        var streak = 0
        var isFirstDay = true
        while true {
            if isVacationDay(cursor, vacationRange) {
                // Paused: neither counts nor breaks.
            } else if completedDates.contains(cursor) {
                streak += 1
            } else if isFirstDay {
                // Today (or referenceDate) simply hasn't been logged yet.
            } else {
                break
            }
            isFirstDay = false
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    struct Scan {
        let longest: Int
        /// Threshold streak-length → the date the streak first reached
        /// exactly that length, for any requested threshold actually hit
        /// during the scan. Backdates milestone `earnedDate`s accurately
        /// even for a streak that was already long before milestone
        /// tracking existed.
        let firstDateReachingLength: [Int: Date]
    }

    /// Single forward pass over `[startDate, endDate]` computing the
    /// longest streak in that range and (for any length in `thresholds`
    /// actually reached) the exact date it was first reached.
    static func scan(
        completedDates: Set<Date>,
        from startDate: Date,
        to endDate: Date,
        vacationRange: ClosedRange<Date>? = nil,
        thresholds: [Int] = []
    ) -> Scan {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let thresholdSet = Set(thresholds)
        var current = 0
        var longest = 0
        var firstDates: [Int: Date] = [:]

        while day <= end {
            if isVacationDay(day, vacationRange) {
                // Paused: current run continues untouched.
            } else if completedDates.contains(day) {
                current += 1
                longest = max(longest, current)
                if thresholdSet.contains(current) {
                    firstDates[current] = day
                }
            } else {
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return Scan(longest: longest, firstDateReachingLength: firstDates)
    }

    private static func isVacationDay(_ day: Date, _ range: ClosedRange<Date>?) -> Bool {
        guard let range else { return false }
        return range.contains(day)
    }

    /// Every completed run's length within `[startDate, endDate]`, in the
    /// order each run finished — e.g. a 5-day run, then a break, then a
    /// 12-day run, then a break, returns `[5, 12]`. A run still in progress
    /// at `endDate` is included too (it's a real streak the user has built,
    /// just not over yet). Feeds Progress's premium streak-length
    /// distribution histogram — unlike `scan(...)`, which only reports the
    /// single *longest* run, this reports every run so a distribution across
    /// many past streaks (not just the best one) can be built.
    static func allStreakLengths(
        completedDates: Set<Date>,
        from startDate: Date,
        to endDate: Date,
        vacationRange: ClosedRange<Date>? = nil
    ) -> [Int] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        var current = 0
        var lengths: [Int] = []

        while day <= end {
            if isVacationDay(day, vacationRange) {
                // Paused: current run continues untouched.
            } else if completedDates.contains(day) {
                current += 1
            } else {
                if current > 0 { lengths.append(current) }
                current = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if current > 0 { lengths.append(current) }
        return lengths
    }
}
