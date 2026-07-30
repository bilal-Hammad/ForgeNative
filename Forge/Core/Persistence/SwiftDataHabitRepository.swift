import Foundation
import SwiftData

/// The app's real, persistent `HabitRepository` implementation — replaces
/// `InMemoryHabitRepository` for actual use (that type now exists only for
/// SwiftUI Previews). Built as a `@ModelActor`, SwiftData's own real API for
/// exactly this "background-safe actor wrapping a `ModelContainer`" shape —
/// `ModelContext` itself isn't safe to share across arbitrary threads, and
/// `@ModelActor` generates the isolated context/container plumbing rather
/// than hand-rolling it.
///
/// Every query here is scoped (a single day, a date range, a specific
/// habit's id, a fetch limit) — never "fetch the whole completions table and
/// filter in Swift." That table is the one in this app expected to actually
/// grow large over time (one row per habit per day, indefinitely), per the
/// CLAUDE.md Production Scaling Standards; the two `#Index` declarations on
/// `CompletionModel` back these exact access patterns.
@ModelActor
actor SwiftDataHabitRepository: HabitRepository {
    func fetchAll() async throws -> [Habit] {
        let descriptor = FetchDescriptor<HabitModel>(sortBy: [SortDescriptor(\.startDate)])
        return try modelContext.fetch(descriptor).map { $0.toHabit() }
    }

    func fetch(category: HabitCategory) async throws -> [Habit] {
        let categoryRaw = category.rawValue
        let descriptor = FetchDescriptor<HabitModel>(
            predicate: #Predicate { $0.categoryRaw == categoryRaw }
        )
        return try modelContext.fetch(descriptor).map { $0.toHabit() }
    }

    func fetch(id: Habit.ID) async throws -> Habit? {
        let descriptor = FetchDescriptor<HabitModel>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.toHabit()
    }

    func save(_ habit: Habit) async throws {
        let targetID = habit.id
        let descriptor = FetchDescriptor<HabitModel>(predicate: #Predicate { $0.id == targetID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: habit)
        } else {
            modelContext.insert(HabitModel(habit: habit))
        }
        try modelContext.save()
    }

    /// Cascade delete (declared on `HabitModel.completions`) removes every
    /// completion row for this habit in the same operation — no orphaned
    /// history left pointing at a deleted habit.
    func delete(id: Habit.ID) async throws {
        let descriptor = FetchDescriptor<HabitModel>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    func fetchCompletions(for date: Date) async throws -> [Completion] {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<CompletionModel>(predicate: #Predicate { $0.date == day })
        return try modelContext.fetch(descriptor).map { $0.toCompletion() }
    }

    func fetchCompletions(from startDate: Date, to endDate: Date) async throws -> [Completion] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let descriptor = FetchDescriptor<CompletionModel>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor).map { $0.toCompletion() }
    }

    func fetchCompletions(habitID: Habit.ID, from startDate: Date, to endDate: Date) async throws -> [Completion] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        let descriptor = FetchDescriptor<CompletionModel>(
            predicate: #Predicate { $0.habitID == habitID && $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor).map { $0.toCompletion() }
    }

    func upsertCompletion(_ completion: Completion) async throws {
        let targetHabitID = completion.habitID
        let day = completion.date
        let descriptor = FetchDescriptor<CompletionModel>(
            predicate: #Predicate { $0.habitID == targetHabitID && $0.date == day }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: completion)
        } else {
            let model = CompletionModel(completion: completion)
            let habitDescriptor = FetchDescriptor<HabitModel>(predicate: #Predicate { $0.id == targetHabitID })
            model.habit = try modelContext.fetch(habitDescriptor).first
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func fetchRecentCompletions(limit: Int) async throws -> [Completion] {
        var descriptor = FetchDescriptor<CompletionModel>(
            predicate: #Predicate { $0.isComplete == true },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { $0.toCompletion() }
    }

    /// See `HabitRepository`'s doc comment on this method for why the
    /// aggregation happens here rather than in the caller.
    func fetchCategoryCompletionRates(
        habits: [Habit], from startDate: Date, to endDate: Date
    ) async throws -> [Date: (good: Double, bad: Double, todo: Double)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        // Only complete rows matter for a rate calculation — filtering in
        // the predicate (not in Swift after the fact) means the row count
        // actually crossing the actor boundary is smaller than the raw
        // `fetchCompletions(from:to:)` this replaced, on top of not
        // returning full `Completion` values at all.
        let descriptor = FetchDescriptor<CompletionModel>(
            predicate: #Predicate { $0.date >= start && $0.date <= end && $0.isComplete == true }
        )
        let completedRows = try modelContext.fetch(descriptor)

        var completedHabitIDsByDate: [Date: Set<UUID>] = [:]
        for row in completedRows {
            let day = calendar.startOfDay(for: row.date)
            completedHabitIDsByDate[day, default: []].insert(row.habitID)
        }

        let habitsByCategory = Dictionary(grouping: habits, by: \.category)
        func rate(_ category: HabitCategory, completedIDs: Set<UUID>) -> Double {
            guard let categoryHabits = habitsByCategory[category], !categoryHabits.isEmpty else { return 0 }
            let doneCount = categoryHabits.filter { completedIDs.contains($0.id) }.count
            return Double(doneCount) / Double(categoryHabits.count)
        }

        var result: [Date: (good: Double, bad: Double, todo: Double)] = [:]
        var day = start
        while day <= end {
            let completedIDs = completedHabitIDsByDate[day] ?? []
            result[day] = (
                rate(.good, completedIDs: completedIDs),
                rate(.bad, completedIDs: completedIDs),
                rate(.todo, completedIDs: completedIDs)
            )
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
