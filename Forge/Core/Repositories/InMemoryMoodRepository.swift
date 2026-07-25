import Foundation

/// In-memory stub, kept for SwiftUI `#Preview`s only — see
/// `InMemoryHabitRepository`'s doc comment for why this pattern exists
/// alongside the real SwiftData-backed implementation.
actor InMemoryMoodRepository: MoodRepository {
    private var entries: [Date: MoodEntry] = [:]

    func fetchEntry(for date: Date) async throws -> MoodEntry? {
        entries[Calendar.current.startOfDay(for: date)]
    }

    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [MoodEntry] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        return entries.values.filter { $0.date >= start && $0.date <= end }
    }

    func upsertEntry(_ entry: MoodEntry) async throws {
        entries[entry.date] = entry
    }
}
