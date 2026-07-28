import EventKit
import Foundation

/// The real `CalendarSyncService` — see that protocol's doc comment for the
/// Calendar-vs-Reminders architectural split this implementation follows.
/// Constructed once in `ForgeApp` (same pattern as `HealthKitService`) and
/// reached via `@Environment(\.calendarSyncService)`. An `actor`, not
/// `@MainActor` — every entry point here is called from a detached/plain
/// `Task` dispatch, never awaited inline on a tap/save handler (see
/// `HomeView.dispatchCalendarSync(for:)`), so `EKEventStore`'s synchronous
/// `save`/`remove` calls (EventKit has no async variant of either) never
/// block the main thread.
actor EventKitCalendarSyncService: CalendarSyncService {
    private let eventStore = EKEventStore()
    private let habitRepository: HabitRepository

    init(habitRepository: HabitRepository) {
        self.habitRepository = habitRepository
    }

    // MARK: - Authorization

    nonisolated func calendarAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    nonisolated func remindersAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    @discardableResult
    func requestCalendarAccessIfNeeded() async -> Bool {
        switch calendarAuthorizationStatus() {
        case .fullAccess: return true
        case .notDetermined: return (try? await eventStore.requestFullAccessToEvents()) ?? false
        default: return false
        }
    }

    @discardableResult
    func requestRemindersAccessIfNeeded() async -> Bool {
        switch remindersAuthorizationStatus() {
        case .fullAccess: return true
        case .notDetermined: return (try? await eventStore.requestFullAccessToReminders()) ?? false
        default: return false
        }
    }

    // MARK: - Sync

    func sync(habit: Habit) async {
        var updated = habit
        var changed = false

        if habit.calendarSyncEnabled, habit.isCalendarSyncSupported, calendarAuthorizationStatus() == .fullAccess {
            if let newIdentifier = syncCalendarEvent(for: habit), newIdentifier != updated.calendarEventIdentifier {
                updated.calendarEventIdentifier = newIdentifier
                changed = true
            }
        } else if let existingID = updated.calendarEventIdentifier {
            removeCalendarEvent(identifier: existingID)
            updated.calendarEventIdentifier = nil
            changed = true
        }

        if habit.remindersAppSyncEnabled, remindersAuthorizationStatus() == .fullAccess {
            let newIdentifiers = syncReminders(for: habit, existingIdentifiers: habit.reminderIdentifiers ?? [])
            if newIdentifiers != (updated.reminderIdentifiers ?? []) {
                updated.reminderIdentifiers = newIdentifiers.isEmpty ? nil : newIdentifiers
                changed = true
            }
        } else if let existingIDs = updated.reminderIdentifiers, !existingIDs.isEmpty {
            removeReminders(identifiers: existingIDs)
            updated.reminderIdentifiers = nil
            changed = true
        }

        guard changed else { return }
        try? await habitRepository.save(updated)
    }

    func removeSync(for habit: Habit) async {
        if let eventID = habit.calendarEventIdentifier {
            removeCalendarEvent(identifier: eventID)
        }
        if let reminderIDs = habit.reminderIdentifiers, !reminderIDs.isEmpty {
            removeReminders(identifiers: reminderIDs)
        }
    }

    // MARK: - Completion mirroring (Reminders only)

    func mirrorCompletion(habit: Habit, completion: Completion) async {
        guard habit.remindersAppSyncEnabled, remindersAuthorizationStatus() == .fullAccess else { return }
        guard let identifiers = habit.reminderIdentifiers, !identifiers.isEmpty else { return }

        let day = Calendar.current.dateComponents([.year, .month, .day], from: completion.date)
        let todaysReminders = fetchReminders(identifiers: identifiers).filter { sameDay($0.dueDateComponents, day) }
        guard !todaysReminders.isEmpty else { return }

        for reminder in todaysReminders {
            reminder.isCompleted = completion.isComplete
            reminder.completionDate = completion.isComplete ? .now : nil
            try? eventStore.save(reminder, commit: false)
        }
        try? eventStore.commit()
    }

    // MARK: - Calendar event sync

    /// Creates the habit's one recurring `EKEvent` if it doesn't have one
    /// yet, or updates the existing one in place otherwise — `span:
    /// .futureEvents` on save means an edit to an already-recurring event
    /// applies from now forward without disturbing any already-passed
    /// occurrence, matching how Calendar.app's own "edit this and future
    /// events" works.
    private func syncCalendarEvent(for habit: Habit) -> String? {
        let event: EKEvent
        if let existingID = habit.calendarEventIdentifier, let existing = eventStore.event(withIdentifier: existingID) {
            event = existing
        } else {
            event = EKEvent(eventStore: eventStore)
            event.calendar = eventStore.defaultCalendarForNewEvents
        }
        event.title = habit.title
        applySchedule(to: event, habit: habit)
        do {
            try eventStore.save(event, span: .futureEvents, commit: true)
            return event.eventIdentifier
        } catch {
            return habit.calendarEventIdentifier
        }
    }

    private func removeCalendarEvent(identifier: String) {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        try? eventStore.remove(event, span: .futureEvents, commit: true)
    }

    /// Decision logic cases 2-5 from the sync spec: no time → all-day;
    /// timed + time-based unit (a duration/timer habit) → a real block the
    /// length of the goal duration; timed + non-time-based unit → a
    /// 15-minute default block (see the doc comment below for why this
    /// exact number is a flagged judgment call, not derived); an end date
    /// → `EKRecurrenceEnd`, letting Calendar's own engine stop generating
    /// occurrences rather than Forge deleting anything manually.
    private func applySchedule(to event: EKEvent, habit: Habit) {
        switch habit.timeMode {
        case .none:
            event.isAllDay = true
            let day = Calendar.current.startOfDay(for: habit.startDate)
            event.startDate = day
            event.endDate = day
        case .fixedTime(let time):
            event.isAllDay = false
            let start = Self.combine(day: habit.startDate, timeOfDay: time)
            event.startDate = start
            if habit.unit.isTimeBased {
                event.endDate = start.addingTimeInterval(habit.goal * habit.unit.secondsPerUnit)
            } else {
                // No natural duration exists for e.g. "drink a glass of
                // water" or "make your bed" — `EKEvent` still requires
                // `endDate > startDate` for a non-all-day event, so this
                // picks *a* number rather than leaving the event invalid.
                // Flagged per this project's autonomous-decision
                // convention: if product direction wants a different
                // default, this is the one constant to change.
                event.endDate = start.addingTimeInterval(Self.defaultTimedEventDuration)
            }
        case .everyXHours, .timesADay:
            // Unreachable in practice — `sync(habit:)` only calls this
            // after confirming `habit.isCalendarSyncSupported`, which is
            // false for both these `TimeMode` cases. No fallback branch
            // needed beyond satisfying exhaustiveness.
            break
        }
        event.recurrenceRules = [Self.recurrenceRule(for: habit)].compactMap { $0 }
    }

    private static let defaultTimedEventDuration: TimeInterval = 15 * 60

    private static func combine(day: Date, timeOfDay: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeOfDay)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 9,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    /// `RepeatMode` → `EKRecurrenceRule` — see `RepeatMode.swift`'s own doc
    /// comment, which already flagged this exact day-index mismatch before
    /// this integration existed: Forge's `specificDays` is 0 = Sunday...
    /// 6 = Saturday, while `EKWeekday`'s raw values are 1 = Sunday...
    /// 7 = Saturday (matching `HabitNotificationScheduler`'s identical
    /// `+ 1` conversion for `UNCalendarNotificationTrigger`). `.timesPerWeek`
    /// returns `nil` — no clean `EKRecurrenceRule` equivalent for a
    /// flexible "N times, any days" count (see `Habit
    /// .calendarSyncUnsupportedReason`); unreachable here in practice since
    /// `sync(habit:)` gates on `isCalendarSyncSupported` first, same as the
    /// `.everyXHours`/`.timesADay` case above.
    private static func recurrenceRule(for habit: Habit) -> EKRecurrenceRule? {
        let end = habit.endDate.map { EKRecurrenceEnd(end: $0) }
        switch habit.repeatMode {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: end)
        case .everyXDays(let interval):
            return EKRecurrenceRule(recurrenceWith: .daily, interval: max(1, interval), end: end)
        case .specificDays(let days):
            guard !days.isEmpty else { return nil }
            let weekdays = days.compactMap { EKRecurrenceDayOfWeek(EKWeekday(rawValue: $0 + 1) ?? .sunday) }
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        case .timesPerWeek:
            return nil
        }
    }

    // MARK: - Reminders sync

    /// Ensures *today's* occurrence(s) for this habit each have a live,
    /// non-recurring `EKReminder` — reusing any that already match (so
    /// re-running sync repeatedly is idempotent, not duplicate-creating),
    /// creating whatever's missing, and removing anything that no longer
    /// matches a wanted occurrence (the habit's schedule changed since the
    /// last sync, or this is a stale reminder from a previous day) — see
    /// this file's top doc comment for why Reminders uses fresh per-day
    /// objects instead of `recurrenceRules` the way Calendar does.
    private func syncReminders(for habit: Habit, existingIdentifiers: [String]) -> [String] {
        let today = Calendar.current.startOfDay(for: .now)
        let wantedOccurrences = Self.occurrenceComponents(for: habit, on: today)
        let existingReminders = fetchReminders(identifiers: existingIdentifiers)

        var usedExistingIDs = Set<String>()
        var resultIdentifiers: [String] = []

        for components in wantedOccurrences {
            if let match = existingReminders.first(where: {
                !usedExistingIDs.contains($0.calendarItemIdentifier) && sameDueDate($0.dueDateComponents, components)
            }) {
                usedExistingIDs.insert(match.calendarItemIdentifier)
                resultIdentifiers.append(match.calendarItemIdentifier)
                continue
            }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = habit.title
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
            reminder.dueDateComponents = components
            do {
                try eventStore.save(reminder, commit: false)
                resultIdentifiers.append(reminder.calendarItemIdentifier)
            } catch {
                continue
            }
        }

        for reminder in existingReminders where !usedExistingIDs.contains(reminder.calendarItemIdentifier) {
            try? eventStore.remove(reminder, commit: false)
        }
        try? eventStore.commit()

        return resultIdentifiers
    }

    private func removeReminders(identifiers: [String]) {
        for reminder in fetchReminders(identifiers: identifiers) {
            try? eventStore.remove(reminder, commit: false)
        }
        try? eventStore.commit()
    }

    private func fetchReminders(identifiers: [String]) -> [EKReminder] {
        guard !identifiers.isEmpty else { return [] }
        return identifiers.compactMap { eventStore.calendarItem(withIdentifier: $0) as? EKReminder }
    }

    /// One `DateComponents` per occurrence *time* on `day` — the same
    /// 8:00–22:00 active-window spread `HabitNotificationScheduler` already
    /// uses for local notifications, reused here rather than invented fresh
    /// (keeps a "3 times a day" habit's Reminders lining up with when its
    /// notifications actually fire).
    private static func occurrenceComponents(for habit: Habit, on day: Date) -> [DateComponents] {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)

        func components(hour: Int, minute: Int) -> DateComponents {
            var result = dayComponents
            result.hour = hour
            result.minute = minute
            return result
        }

        switch habit.timeMode {
        case .none:
            return [dayComponents]
        case .fixedTime(let time):
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            return [components(hour: timeComponents.hour ?? 9, minute: timeComponents.minute ?? 0)]
        case .everyXHours(let interval):
            guard interval > 0 else { return [] }
            var results: [DateComponents] = []
            var hour = HabitNotificationScheduler.activeWindowStartHour
            while hour <= HabitNotificationScheduler.activeWindowEndHour, results.count < HabitNotificationScheduler.maxRequestsPerHabit {
                results.append(components(hour: hour, minute: 0))
                hour += interval
            }
            return results
        case .timesADay(let count):
            guard count > 0 else { return [] }
            let cappedCount = min(count, HabitNotificationScheduler.maxRequestsPerHabit)
            let startMinutes = HabitNotificationScheduler.activeWindowStartHour * 60
            let windowMinutes = (HabitNotificationScheduler.activeWindowEndHour - HabitNotificationScheduler.activeWindowStartHour) * 60
            return (0..<cappedCount).map { i in
                let totalMinutes = startMinutes + Int(Double(windowMinutes) * Double(i) / Double(cappedCount))
                return components(hour: totalMinutes / 60, minute: totalMinutes % 60)
            }
        }
    }

    private func sameDueDate(_ a: DateComponents?, _ b: DateComponents) -> Bool {
        guard let a else { return false }
        return a.year == b.year && a.month == b.month && a.day == b.day && a.hour == b.hour && a.minute == b.minute
    }

    private func sameDay(_ a: DateComponents?, _ b: DateComponents) -> Bool {
        guard let a else { return false }
        return a.year == b.year && a.month == b.month && a.day == b.day
    }
}
