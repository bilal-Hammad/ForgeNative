import Foundation

/// A suggested habit "blueprint" shown in the category-detail browser
/// (APP_REDESIGN_SPEC.md §5) — distinct from `Habit`, which is a real,
/// user-owned habit. Selecting a template creates a `Habit` seeded from it,
/// including its per-habit smart `goal`/`unit`/`step` defaults (reasoned
/// individually per habit from the real RN app's data, not one generic
/// default applied to everything — e.g. "Make Your Bed" is goal 1/count/
/// step 1, "Read a Book" is goal 20/minutes/step 5).
struct HabitTemplate: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var category: HabitCategory
    var iconSystemName: String
    /// §4: templates that map to a HealthKit auto-tracked habit — these get
    /// the small Apple Health badge on the resulting habit card.
    var isHealthKitTracked: Bool
    var goal: Double
    var unit: HabitUnit
    var step: Double

    init(
        id: String,
        title: String,
        category: HabitCategory,
        iconSystemName: String,
        isHealthKitTracked: Bool = false,
        goal: Double = 1,
        unit: HabitUnit = .count,
        step: Double = 1
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.iconSystemName = iconSystemName
        self.isHealthKitTracked = isHealthKitTracked
        self.goal = goal
        self.unit = unit
        self.step = step
    }
}
