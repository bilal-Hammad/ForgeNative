import Foundation
import SwiftData

/// SwiftData persistence entity for `MoodEntry`. Unlike `CompletionModel`
/// (which is only unique per `(habitID, date)` pair, enforced at the
/// repository layer, not the schema — see that type's doc comment), a mood
/// entry has no second scoping key: it really is one row per calendar day,
/// full stop. `date` is marked `.unique` here for that reason — a real
/// database-level integrity guarantee (CLAUDE.md's Production Scaling
/// Standard #6) rather than relying purely on the repository's
/// fetch-then-upsert discipline to keep it that way.
@Model
final class MoodEntryModel {
    #Index<MoodEntryModel>([\.date])

    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var date: Date
    var moodRaw: String
    var loggedAt: Date

    init(id: UUID, date: Date, moodRaw: String, loggedAt: Date) {
        self.id = id
        self.date = date
        self.moodRaw = moodRaw
        self.loggedAt = loggedAt
    }
}

extension MoodEntryModel {
    convenience init(entry: MoodEntry) {
        self.init(id: entry.id, date: entry.date, moodRaw: entry.mood.rawValue, loggedAt: entry.loggedAt)
    }

    func update(from entry: MoodEntry) {
        moodRaw = entry.mood.rawValue
        loggedAt = entry.loggedAt
    }

    func toMoodEntry() -> MoodEntry {
        MoodEntry(id: id, date: date, mood: MoodLevel(rawValue: moodRaw) ?? .okay, loggedAt: loggedAt)
    }
}
