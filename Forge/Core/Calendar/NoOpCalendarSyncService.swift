import EventKit
import Foundation

/// Previews/tests stand-in — matches `InMemoryHabitRepository`'s role for
/// `HabitRepository`. Never touches real EventKit data; every authorization
/// query reports `.notDetermined` and every sync/removal/mirror call is a
/// silent no-op, so a Preview or a `-uiTesting` run never prompts for real
/// Calendar/Reminders permission.
struct NoOpCalendarSyncService: CalendarSyncService {
    nonisolated func calendarAuthorizationStatus() -> EKAuthorizationStatus { .notDetermined }
    nonisolated func remindersAuthorizationStatus() -> EKAuthorizationStatus { .notDetermined }

    func requestCalendarAccessIfNeeded() async -> Bool { false }
    func requestRemindersAccessIfNeeded() async -> Bool { false }

    func sync(habit: Habit) async {}
    func removeSync(for habit: Habit) async {}
    func mirrorCompletion(habit: Habit, completion: Completion) async {}
}
