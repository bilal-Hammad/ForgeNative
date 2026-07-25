#if DEBUG
import SwiftUI

/// Debug-only tool to backfill realistic historical completions for one
/// habit, so streak/points/milestone logic (7-day, 30-day, etc. thresholds)
/// can be exercised without waiting real days. The whole file is wrapped in
/// `#if DEBUG` — this type doesn't exist at all in a release binary, not
/// just hidden behind a UI toggle, so it's unreachable in a shipped app by
/// construction, not by convention.
///
/// Writes through the exact same `HabitRepository.upsertCompletion(_:)`
/// path `HomeView` uses for a real tap — same `Completion` shape, just
/// backdated — so streak/points/milestone logic can't tell the difference
/// from genuine history. See `seed()` for two real assumptions this
/// surfaced that backdated data can violate, and how this tool works around
/// both rather than silently producing wrong or empty-looking results.
struct DebugSeedHistoryView: View {
    @Environment(\.habitRepository) private var habitRepository
    @Environment(\.milestoneRepository) private var milestoneRepository
    @Environment(\.milestoneEngine) private var milestoneEngine
    @Environment(\.dismiss) private var dismiss

    @State private var habits: [Habit] = []
    @State private var selectedHabitID: Habit.ID?
    @State private var dayCount = 30
    @State private var isSeeding = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    Picker("Habit", selection: $selectedHabitID) {
                        Text("Choose a habit").tag(Habit.ID?.none)
                        ForEach(habits) { habit in
                            Text(habit.title).tag(Habit.ID?.some(habit.id))
                        }
                    }
                }

                Section {
                    Stepper("Past \(dayCount) days", value: $dayCount, in: 1...400)
                } header: {
                    Text("Backfill Window")
                } footer: {
                    Text("Marks the habit complete for each of the past \(dayCount) days, including today. If the habit is younger than that, its start date is moved back to cover the seeded range — otherwise streak/rate queries (which never look earlier than a habit's own start date) wouldn't see the seeded days at all.")
                }

                Section {
                    Button {
                        Task { await seed() }
                    } label: {
                        if isSeeding {
                            HStack {
                                ProgressView()
                                Text("Seeding…")
                            }
                        } else {
                            Text("Seed Completions")
                        }
                    }
                    .disabled(selectedHabitID == nil || isSeeding)
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Seed Test History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                habits = (try? await habitRepository.fetchAll()) ?? []
            }
        }
    }

    /// Backfills `dayCount` consecutive complete days ending today for the
    /// selected habit, through the normal repository path.
    ///
    /// Two real assumptions this surfaced, both worked around here rather
    /// than left to silently misbehave:
    ///
    /// 1. Every habit-scoped streak/rate query (`HabitDetailView`,
    ///    `MilestoneEngine.checkHabitStreak`) bounds its range at the
    ///    habit's own `startDate` — correct for real usage (nothing can be
    ///    completed before a habit existed), but it means seeding history
    ///    for a habit younger than the seeded window would silently produce
    ///    *no* detected streak at all, since the query itself would never
    ///    look back far enough to see the seeded days. Worked around by
    ///    moving `habit.startDate` back to cover the seeded range whenever
    ///    it's younger than that — saved through the normal
    ///    `habitRepository.save(_:)` path, same as `HabitFormView` would.
    /// 2. The points ledger (`PointsLedgerModel`) advances a forward-only
    ///    `lastEvaluatedDay` watermark and never re-visits a day once
    ///    swept — safe for real usage (there's no way to log a genuine
    ///    completion for a day after it's already been evaluated, since
    ///    `HomeView` only ever logs completions dated `.now`), but
    ///    backdating breaks it: seeded days will almost always land before
    ///    the current watermark, and left alone their point deltas would
    ///    just never get counted. Worked around by resetting the ledger to
    ///    empty after seeding, so the next catch-up recomputes points from
    ///    scratch across every habit's full history — correct, and fine
    ///    for a small debug/test dataset, but notably the one place in this
    ///    codebase that deliberately does the full recompute the rest of
    ///    the app avoids, and only because it's debug-gated and manually
    ///    triggered, never a hot path.
    private func seed() async {
        guard let habitID = selectedHabitID, var habit = habits.first(where: { $0.id == habitID }) else { return }
        isSeeding = true
        defer { isSeeding = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let earliestSeededDay = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else { return }

        var didExtendStartDate = false
        if earliestSeededDay < calendar.startOfDay(for: habit.startDate) {
            habit.startDate = earliestSeededDay
            try? await habitRepository.save(habit)
            didExtendStartDate = true
        }

        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            var completion = Completion(habitID: habit.id, date: day)
            completion.isComplete = true
            if habit.timeMode != .none {
                completion.startedAt = day
            } else if habit.goal > 1 {
                completion.count = habit.goal
            }
            completion.loggedAt = day
            try? await habitRepository.upsertCompletion(completion)
        }

        try? await milestoneRepository.savePointsLedger(.empty)
        await milestoneEngine.afterCompletionLogged(habit: habit)

        resultMessage = didExtendStartDate
            ? "Seeded \(dayCount) days of history for \(habit.title) (also moved its start date back to cover the range). Points ledger recomputed from scratch."
            : "Seeded \(dayCount) days of history for \(habit.title). Points ledger recomputed from scratch."
    }
}

#Preview {
    DebugSeedHistoryView()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
#endif
