import Foundation

/// In-memory stub — no longer the app's real storage (see
/// `SwiftDataHabitRepository` for that), kept intentionally for SwiftUI
/// `#Preview`s, which want a fast, isolated, disposable store rather than
/// sharing the app's actual persistent SwiftData container.
actor InMemoryHabitRepository: HabitRepository {
    private var habits: [Habit] = []
    private var completions: [Completion] = []

    func fetchAll() async throws -> [Habit] {
        habits
    }

    func fetch(category: HabitCategory) async throws -> [Habit] {
        habits.filter { $0.category == category }
    }

    func fetch(id: Habit.ID) async throws -> Habit? {
        habits.first { $0.id == id }
    }

    func save(_ habit: Habit) async throws {
        if let index = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[index] = habit
        } else {
            habits.append(habit)
        }
    }

    func delete(id: Habit.ID) async throws {
        habits.removeAll { $0.id == id }
    }

    func fetchCompletions(for date: Date) async throws -> [Completion] {
        let day = Calendar.current.startOfDay(for: date)
        return completions.filter { $0.date == day }
    }

    func fetchCompletions(from startDate: Date, to endDate: Date) async throws -> [Completion] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        return completions.filter { $0.date >= start && $0.date <= end }
    }

    func fetchCompletions(habitID: Habit.ID, from startDate: Date, to endDate: Date) async throws -> [Completion] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        return completions.filter { $0.habitID == habitID && $0.date >= start && $0.date <= end }
    }

    func upsertCompletion(_ completion: Completion) async throws {
        if let index = completions.firstIndex(where: { $0.habitID == completion.habitID && $0.date == completion.date }) {
            completions[index] = completion
        } else {
            completions.append(completion)
        }
    }

    func fetchRecentCompletions(limit: Int) async throws -> [Completion] {
        completions
            .filter(\.isComplete)
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(limit)
            .map { $0 }
    }

    func fetchCategoryCompletionRates(
        habits: [Habit], from startDate: Date, to endDate: Date
    ) async throws -> [Date: (good: Double, bad: Double, todo: Double)] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let completedIDsByDate = Dictionary(grouping: completions.filter { $0.isComplete && $0.date >= start && $0.date <= end }, by: \.date)
            .mapValues { Set($0.map(\.habitID)) }
        let habitsByCategory = Dictionary(grouping: habits, by: \.category)

        func rate(_ category: HabitCategory, completedIDs: Set<UUID>) -> Double {
            guard let categoryHabits = habitsByCategory[category], !categoryHabits.isEmpty else { return 0 }
            let doneCount = categoryHabits.filter { completedIDs.contains($0.id) }.count
            return Double(doneCount) / Double(categoryHabits.count)
        }

        var result: [Date: (good: Double, bad: Double, todo: Double)] = [:]
        var day = start
        while day <= end {
            let completedIDs = completedIDsByDate[day] ?? []
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
