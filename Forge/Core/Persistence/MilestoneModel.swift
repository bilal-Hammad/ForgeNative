import Foundation
import SwiftData

/// SwiftData persistence entity for `Milestone`. `dedupeKey` is the real
/// uniqueness guard (kind+scope+value+period) — `MilestoneEngine` always
/// checks-then-inserts rather than relying on the unique-attribute conflict
/// behavior alone, matching how the rest of this persistence layer
/// (`SwiftDataTemplateSectionRepository`'s lazy-create) already operates.
@Model
final class MilestoneModel {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var dedupeKey: String
    var kindRaw: String
    var scopeID: String
    var value: Int
    var periodKey: String
    var title: String
    var subtitle: String
    var earnedDate: Date
    var colorToken: String

    init(
        id: UUID,
        dedupeKey: String,
        kindRaw: String,
        scopeID: String,
        value: Int,
        periodKey: String,
        title: String,
        subtitle: String,
        earnedDate: Date,
        colorToken: String
    ) {
        self.id = id
        self.dedupeKey = dedupeKey
        self.kindRaw = kindRaw
        self.scopeID = scopeID
        self.value = value
        self.periodKey = periodKey
        self.title = title
        self.subtitle = subtitle
        self.earnedDate = earnedDate
        self.colorToken = colorToken
    }
}

extension MilestoneModel {
    convenience init(milestone: Milestone) {
        self.init(
            id: milestone.id,
            dedupeKey: milestone.dedupeKey,
            kindRaw: milestone.kind.rawValue,
            scopeID: milestone.scopeID,
            value: milestone.value,
            periodKey: milestone.periodKey,
            title: milestone.title,
            subtitle: milestone.subtitle,
            earnedDate: milestone.earnedDate,
            colorToken: milestone.colorToken
        )
    }

    func toMilestone() -> Milestone {
        Milestone(
            id: id,
            kind: MilestoneKind(rawValue: kindRaw) ?? .points,
            scopeID: scopeID,
            value: value,
            periodKey: periodKey,
            title: title,
            subtitle: subtitle,
            earnedDate: earnedDate,
            colorToken: colorToken
        )
    }
}
