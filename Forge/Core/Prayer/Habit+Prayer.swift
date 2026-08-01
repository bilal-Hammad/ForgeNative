import Foundation

/// Convenience accessors for a prayer-relative habit's anchor (P1 Phase 3),
/// so call sites don't repeat the `if case .prayerRelative(let anchor)`
/// pattern over `timeMode`.
extension Habit {
    var isPrayerRelative: Bool {
        if case .prayerRelative = timeMode { return true }
        return false
    }

    var prayerAnchor: PrayerAnchor? {
        if case .prayerRelative(let anchor) = timeMode { return anchor }
        return nil
    }
}
