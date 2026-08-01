import Foundation
import UserNotifications

/// Schedules the single per-prayer-habit notification (P1 Phase 4): one
/// reminder per active prayer habit, timed at that day's `adhan + iqamaDelay +
/// prayerDuration` (once the prayer has realistically been prayed) — never at
/// adhan time itself (redundant with dedicated adhan apps).
///
/// Because prayer times shift daily, this can't use a single repeating
/// trigger like `HabitNotificationScheduler` does — it schedules
/// **non-repeating** `UNCalendarNotificationTrigger`s for the next few days (a
/// rolling window, re-armed on foreground once prayer habits exist — Phase 7),
/// the same fresh-per-day approach the Reminders sync already uses for
/// interval habits.
///
/// **Independence invariant (Phase 4 clarification):** this system is fully
/// decoupled from Phase 3's completion-window lock. It only reads offsets and
/// arms notifications; nothing here touches `Completion.missed`,
/// `PrayerDayState`, or `PrayerWindowCatchUp`. A user turning this habit's
/// notification off (or changing its offsets) changes *only* whether/when a
/// reminder fires — the strict window lock is unaffected, because the lock
/// path never reads `notificationsEnabled` or any offset.
enum PrayerNotificationScheduler {
    static let daysAhead = 3
    /// A little headroom over `daysAhead` so `removeAll` clears any stale
    /// identifiers from a previously larger window.
    private static let identifierSlots = 7

    private static func identifierPrefix(for habitID: Habit.ID) -> String {
        "prayer-reminder-\(habitID.uuidString)-"
    }

    private static func identifier(habitID: Habit.ID, slot: Int) -> String {
        "\(identifierPrefix(for: habitID))\(slot)"
    }

    // MARK: - Pure fire-time computation (unit-tested)

    /// The notification fire date for a prayer habit on `day`: the **anchor
    /// prayer's adhan** plus the offsets. Deliberately keyed on the anchor
    /// prayer's adhan, not the anchor's own minute offset — the notification
    /// is the "the prayer's time has passed, complete this" nudge, tied to the
    /// prayer, not the habit's display-time. `nil` if the schedule can't be
    /// computed.
    static func fireDate(
        anchor: PrayerAnchor,
        offsets: PrayerOffsets,
        day: Date,
        coordinate: Coordinate,
        service: PrayerTimeService
    ) -> Date? {
        guard let schedule = service.schedule(for: day, at: coordinate) else { return nil }
        return schedule.time(for: anchor.prayer).addingTimeInterval(TimeInterval(offsets.totalMinutes * 60))
    }

    /// The next `daysAhead` fire dates strictly after `now`, chronological.
    static func upcomingFireDates(
        anchor: PrayerAnchor,
        offsets: PrayerOffsets,
        coordinate: Coordinate,
        service: PrayerTimeService,
        calendar: Calendar,
        now: Date,
        daysAhead: Int = daysAhead
    ) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: now)
        // Scan a couple extra days so a fire time earlier today (already
        // passed) doesn't cost us a future slot.
        var scanned = 0
        while result.count < daysAhead && scanned <= daysAhead + 2 {
            if let fire = fireDate(anchor: anchor, offsets: offsets, day: day, coordinate: coordinate, service: service),
               fire > now {
                result.append(fire)
            }
            scanned += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    // MARK: - Authorization (reuses the general habit scheduler's)

    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await HabitNotificationScheduler.currentAuthorizationStatus()
    }

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        await HabitNotificationScheduler.requestAuthorizationIfNeeded()
    }

    // MARK: - Scheduling

    /// Clears this prayer habit's pending notifications and reschedules the
    /// rolling window from its current settings. No-op (after clearing) if the
    /// habit isn't a prayer habit, notifications are off (globally or
    /// per-habit), it's archived, or permission isn't granted.
    static func reschedule(
        for habit: Habit,
        coordinate: Coordinate,
        service: PrayerTimeService,
        globalNotificationsEnabled: Bool,
        calendar: Calendar = .current,
        now: Date = .now
    ) async {
        removeAll(for: habit.id)

        guard globalNotificationsEnabled,
              habit.notificationsEnabled,
              !habit.isArchived,
              let anchor = habit.prayerAnchor else { return }

        let status = await currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let offsets = PrayerPreferences.offsets(for: anchor.prayer)
        let fireDates = upcomingFireDates(
            anchor: anchor, offsets: offsets, coordinate: coordinate,
            service: service, calendar: calendar, now: now
        )
        guard !fireDates.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        for (slot, date) in fireDates.enumerated() {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let content = UNMutableNotificationContent()
            content.title = habit.title
            content.body = "It's time for \(anchor.prayer.displayName) — mark \(habit.title) complete."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier(habitID: habit.id, slot: slot),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    /// Cancels every pending prayer notification for this habit.
    static func removeAll(for habitID: Habit.ID) {
        let identifiers = (0..<identifierSlots).map { identifier(habitID: habitID, slot: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
