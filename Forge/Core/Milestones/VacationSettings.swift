import Foundation

/// Reads the vacation-mode window `SettingsView` already writes via
/// `@AppStorage` (`vacationModeEnabled` / `vacationStart` / `vacationEnd`).
/// Not a View, so it goes straight to `UserDefaults.standard` with the same
/// keys rather than duplicating a settings store.
///
/// Known limitation, not introduced here: this only ever stores the single
/// *current* vacation window — turning vacation mode on for a new range
/// overwrites the old one, so a past vacation window that's since been
/// replaced can't be reconstructed for historical streak/points math. If
/// that turns out to matter in practice, storing a history of past windows
/// would be the fix — not attempted in this pass.
enum VacationSettings {
    static func currentRange() -> ClosedRange<Date>? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "vacationModeEnabled") != nil,
              defaults.bool(forKey: "vacationModeEnabled") else {
            return nil
        }
        let calendar = Calendar.current
        let startInterval = defaults.double(forKey: "vacationStart")
        let endInterval = defaults.double(forKey: "vacationEnd")
        guard startInterval > 0, endInterval > 0 else { return nil }
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: startInterval))
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: endInterval))
        guard start <= end else { return nil }
        return start...end
    }

    static func isVacationDay(_ day: Date) -> Bool {
        guard let range = currentRange() else { return false }
        let start = Calendar.current.startOfDay(for: day)
        return range.contains(start)
    }
}
