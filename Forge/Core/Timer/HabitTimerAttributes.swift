import ActivityKit
import Foundation

/// ActivityKit attributes for a running time-unit habit's timer — this
/// exact file is compiled directly into **both** the main `Forge` target
/// (which starts/ends the Activity from `HabitTimerCoordinator`) and the
/// `ForgeWidgets` extension (which renders it in the Dynamic Island/Lock
/// Screen). No shared framework boundary — matches this project's existing
/// preference for direct multi-target file references over a framework for
/// something this small (see `HabitColor`, also referenced from both
/// targets for exactly this reason).
///
/// `startDate` is a fixed attribute (never changes once the timer starts);
/// `endDate` lives in `ContentState` since that's the value the Live
/// Activity's view actually renders against.
struct HabitTimerAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var endDate: Date
    }

    let habitID: UUID
    let habitTitle: String
    let iconSystemName: String
    let color: HabitColor
    let startDate: Date
}
