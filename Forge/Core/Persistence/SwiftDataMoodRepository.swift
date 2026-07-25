import Foundation
import SwiftData

/// The app's real, persistent `MoodRepository` implementation.
@ModelActor
actor SwiftDataMoodRepository: MoodRepository {
    func fetchEntry(for date: Date) async throws -> MoodEntry? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<MoodEntryModel>(predicate: #Predicate { $0.date == day })
        return try modelContext.fetch(descriptor).first?.toMoodEntry()
    }

    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [MoodEntry] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let descriptor = FetchDescriptor<MoodEntryModel>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor).map { $0.toMoodEntry() }
    }

    func upsertEntry(_ entry: MoodEntry) async throws {
        let day = entry.date
        let descriptor = FetchDescriptor<MoodEntryModel>(predicate: #Predicate { $0.date == day })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.update(from: entry)
        } else {
            modelContext.insert(MoodEntryModel(entry: entry))
        }
        try modelContext.save()
    }
}
