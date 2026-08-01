import Foundation

/// Self-healing catch-up for prayer-relative habits (P1 Phase 3): finds days
/// whose completion window has closed without a completion and persists them
/// as `missed`, so the miss (and its streak/points consequence, applied by the
/// existing engine that treats a missed day as a non-completion) is recorded
/// even when the app wasn't open at the moment the window closed. Same shape
/// as `MilestoneEngine.runCatchUp()` / `HomeView.checkTimerCompletions()`.
///
/// **Bounded** (Engineering standard #1): only sweeps the last `lookbackDays`
/// (default 7) up to today, never the full history — a prayer missed weeks ago
/// is already durably recorded from a previous sweep. Uses the *current*
/// coordinate for recent past days (a few km of drift is still minute-accurate
/// for prayer times), since past locations aren't stored.
struct PrayerWindowCatchUp: Sendable {
    let habitRepository: HabitRepository
    let resolver: PrayerWindowResolver
    let calendar: Calendar
    let lookbackDays: Int

    init(
        habitRepository: HabitRepository,
        resolver: PrayerWindowResolver,
        calendar: Calendar = .current,
        lookbackDays: Int = 7
    ) {
        self.habitRepository = habitRepository
        self.resolver = resolver
        self.calendar = calendar
        self.lookbackDays = lookbackDays
    }

    /// Runs the sweep at `coordinate`. No-op (returns) if there are no active
    /// prayer habits — the common case for most users, so it's cheap.
    func run(coordinate: Coordinate, asOf now: Date = .now) async {
        let habits = (try? await habitRepository.fetchAll()) ?? []
        let prayerHabits = habits.filter { !$0.isArchived && $0.isPrayerRelative }
        guard !prayerHabits.isEmpty else { return }

        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return }

        for habit in prayerHabits {
            guard let anchor = habit.prayerAnchor else { continue }
            let start = max(calendar.startOfDay(for: habit.startDate), earliest)
            let existing = (try? await habitRepository.fetchCompletions(habitID: habit.id, from: start, to: today)) ?? []
            var byDay: [Date: Completion] = [:]
            for completion in existing { byDay[calendar.startOfDay(for: completion.date)] = completion }

            var day = start
            while day <= today {
                let current = byDay[day]
                // Already resolved (completed or previously recorded miss) → skip.
                if current?.isComplete != true && current?.missed != true,
                   let window = resolver.window(for: anchor, on: day, at: coordinate),
                   window.isClosed(at: now) {
                    var completion = current ?? Completion(habitID: habit.id, date: day)
                    completion.missed = true
                    completion.loggedAt = now
                    try? await habitRepository.upsertCompletion(completion)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
    }
}
