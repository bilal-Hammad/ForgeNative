import Foundation
import SwiftData

/// SwiftData persistence entity for `Completion` — the highest-volume table
/// in the app by design (one row per habit per day, accumulating for as
/// long as someone uses the app). Every query against this table in the
/// repository is scoped to a specific day or date range, never a full-table
/// fetch, specifically because of that growth profile.
///
/// `habitID` is kept as a denormalized plain field (alongside the real
/// `habit` relationship below) purely so predicates can filter on it
/// directly without needing to traverse the relationship in the predicate
/// itself — `#Predicate` support for relationship traversal has historically
/// been more fragile than filtering a plain scalar field, and this is the
/// single most common filter in the whole app (every completion query is
/// "for this habit" and/or "for this date"). The `habit` relationship is
/// still the source of truth for cascade-delete integrity; `habitID` is a
/// query-performance aid, not a competing identity.
///
/// `#Index` below declares real SwiftData indexes (iOS 18+) on `date` alone
/// and on the `(habitID, date)` pair — the two actual access patterns used
/// throughout the app (`fetchCompletions(for:)` for a single day,
/// `fetchCompletions(from:to:)` for a range, both usually also scoped to one
/// habit when computing e.g. an individual habit's streak).
@Model
final class CompletionModel {
    #Index<CompletionModel>([\.date], [\.habitID, \.date], [\.loggedAt])

    @Attribute(.unique) var id: UUID
    var habitID: UUID
    var date: Date
    var count: Double
    var isComplete: Bool
    var startedAt: Date?
    var loggedAt: Date

    var habit: HabitModel?

    init(
        id: UUID,
        habitID: UUID,
        date: Date,
        count: Double,
        isComplete: Bool,
        startedAt: Date?,
        loggedAt: Date
    ) {
        self.id = id
        self.habitID = habitID
        self.date = date
        self.count = count
        self.isComplete = isComplete
        self.startedAt = startedAt
        self.loggedAt = loggedAt
    }
}

extension CompletionModel {
    convenience init(completion: Completion) {
        self.init(
            id: completion.id,
            habitID: completion.habitID,
            date: completion.date,
            count: completion.count,
            isComplete: completion.isComplete,
            startedAt: completion.startedAt,
            loggedAt: completion.loggedAt
        )
    }

    func update(from completion: Completion) {
        count = completion.count
        isComplete = completion.isComplete
        startedAt = completion.startedAt
        loggedAt = completion.loggedAt
    }

    func toCompletion() -> Completion {
        Completion(
            id: id,
            habitID: habitID,
            date: date,
            count: count,
            isComplete: isComplete,
            startedAt: startedAt,
            loggedAt: loggedAt
        )
    }
}
