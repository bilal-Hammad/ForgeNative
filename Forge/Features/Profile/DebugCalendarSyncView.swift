#if DEBUG
import SwiftUI
import EventKit

/// Debug-only tool for verifying the real Calendar/Reminders sync
/// integration on Simulator, matching `DebugSeedHealthKitView`'s
/// established shape for exactly the same reason: driving the real Add
/// Habit flow's template picker via XCUITest doesn't register taps
/// reliably in this Simulator environment (see that file's own doc
/// comment) — creating test habits directly via `HabitRepository.save(_:)`
/// bypasses that flaky UI step while still exercising every part of the
/// integration actually in question (real EventKit authorization, real
/// `EKEvent`/`EKReminder` creation, the recurrence-rule mapping, the
/// completion-mirror push).
///
/// "Read EventKit State" queries `EKEventStore` directly and reports exact
/// details (title, `isAllDay`, start/end, recurrence rule, due-date
/// components) as text — a much more precise and reliable verification of
/// the actual data written than reading it back off a Calendar.app/
/// Reminders.app screenshot, though those real apps are still checked
/// separately for the user-facing visual confirmation.
///
/// The whole file is `#if DEBUG` — unreachable in a release binary by
/// construction, matching `DebugSeedHealthKitView`/`DebugSeedHistoryView`.
struct DebugCalendarSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.habitRepository) private var habitRepository
    @Environment(\.calendarSyncService) private var calendarSyncService
    @State private var resultMessage: String?

    private static let noTimeHabitID = UUID()
    private static let timerHabitID = UUID()
    private static let quantityHabitID = UUID()
    private static let endDatedHabitID = UUID()
    private static let hourlyHabitID = UUID()

    private static var testHabits: [Habit] {
        let now = Date.now
        let nineAM = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: now)
        return [
            Habit(id: noTimeHabitID, title: "No Time Habit", category: .good, iconSystemName: "checkmark.circle", goal: 1, unit: .count, step: 1, repeatMode: .daily, timeMode: .none, remindersAppSyncEnabled: true, calendarSyncEnabled: true),
            Habit(id: timerHabitID, title: "Meditate Timer Habit", category: .good, iconSystemName: "timer", goal: 20, unit: .minutes, step: 1, repeatMode: .daily, timeMode: .fixedTime(nineAM), remindersAppSyncEnabled: true, calendarSyncEnabled: true),
            Habit(id: quantityHabitID, title: "Quantity Time Habit", category: .good, iconSystemName: "number", goal: 5, unit: .count, step: 1, repeatMode: .daily, timeMode: .fixedTime(nineAM), remindersAppSyncEnabled: true, calendarSyncEnabled: true),
            Habit(id: endDatedHabitID, title: "End Dated Habit", category: .good, iconSystemName: "calendar.badge.clock", goal: 1, unit: .count, step: 1, repeatMode: .daily, timeMode: .none, endDate: threeDaysFromNow, remindersAppSyncEnabled: true, calendarSyncEnabled: true),
            Habit(id: hourlyHabitID, title: "Hourly Habit", category: .good, iconSystemName: "drop.fill", goal: 1, unit: .count, step: 1, repeatMode: .daily, timeMode: .everyXHours(4), remindersAppSyncEnabled: true, calendarSyncEnabled: true)
        ]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. Create the 5 test habits below (covers every decision-logic case), 2. request Calendar + Reminders authorization, 3. sync them, 4. read back the real EventKit state to verify.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("1. Test habits") {
                    actionButton("Create 5 Test Habits", action: createTestHabits)
                }

                Section("2. Authorization") {
                    actionButton("Request Calendar + Reminders Access", action: requestAccess)
                    actionButton("Check Authorization Status", action: checkAuthorizationStatus)
                }

                Section("3. Sync") {
                    actionButton("Sync All Test Habits", action: syncAllTestHabits)
                }

                Section("4. Verification") {
                    actionButton("Read EventKit State", action: readEventKitState)
                    actionButton("Complete 'Meditate Timer Habit' Today", action: completeTimerHabit)
                    actionButton("Un-complete 'Meditate Timer Habit'", action: uncompleteTimerHabit)
                    actionButton("Delete 'No Time Habit'", action: deleteNoTimeHabit)
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("debugCalendarSync.resultMessage")
                    }
                }
            }
            .navigationTitle("Debug Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func actionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) {
            Task { await action() }
        }
    }

    private func createTestHabits() async {
        for habit in Self.testHabits {
            try? await habitRepository.save(habit)
        }
        resultMessage = "Created \(Self.testHabits.count) test habits (or updated them if already present)."
    }

    private func requestAccess() async {
        let calendarGranted = await calendarSyncService.requestCalendarAccessIfNeeded()
        let remindersGranted = await calendarSyncService.requestRemindersAccessIfNeeded()
        resultMessage = "Calendar access granted: \(calendarGranted). Reminders access granted: \(remindersGranted)."
    }

    private func checkAuthorizationStatus() async {
        resultMessage = "Calendar: \(statusText(calendarSyncService.calendarAuthorizationStatus())). Reminders: \(statusText(calendarSyncService.remindersAuthorizationStatus()))."
    }

    private func statusText(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .fullAccess: "fullAccess"
        case .writeOnly: "writeOnly"
        case .authorized: "authorized (legacy)"
        @unknown default: "unknown"
        }
    }

    private func syncAllTestHabits() async {
        let allHabits = (try? await habitRepository.fetchAll()) ?? []
        let testIDs: Set<UUID> = [Self.noTimeHabitID, Self.timerHabitID, Self.quantityHabitID, Self.endDatedHabitID, Self.hourlyHabitID]
        let toSync = allHabits.filter { testIDs.contains($0.id) }
        for habit in toSync {
            await calendarSyncService.sync(habit: habit)
        }
        resultMessage = "Synced \(toSync.count) test habits."
    }

    /// Two layers deliberately: the per-habit section resolves via the
    /// habit's *stored* identifiers (what the app itself tracks), while the
    /// "ALL matching" sections below run store-wide predicate queries —
    /// the only way to see events/reminders the app has *lost track of*
    /// (orphaned duplicates). Added while diagnosing the duplicate-event
    /// bug: the identifier-only readback was structurally blind to the
    /// orphan an identifier-clobbering save leaves behind.
    private func readEventKitState() async {
        let allHabits = (try? await habitRepository.fetchAll()) ?? []
        let testIDs: Set<UUID> = [Self.noTimeHabitID, Self.timerHabitID, Self.quantityHabitID, Self.endDatedHabitID, Self.hourlyHabitID]
        let testHabits = allHabits.filter { testIDs.contains($0.id) }
        let testTitles = Set(Self.testHabits.map(\.title))
        let store = EKEventStore()
        var lines: [String] = []
        for habit in testHabits {
            lines.append("— \(habit.title) —")
            lines.append("  storedEventID=\(habit.calendarEventIdentifier.map { String($0.suffix(8)) } ?? "nil") storedReminderIDs=\(habit.reminderIdentifiers?.count ?? 0)")
            if let eventID = habit.calendarEventIdentifier, let event = store.event(withIdentifier: eventID) {
                lines.append("  Event: allDay=\(event.isAllDay) start=\(event.startDate!) end=\(event.endDate!)")
                if let rule = event.recurrenceRules?.first {
                    lines.append("  Recurrence: freq=\(rule.frequency.rawValue) interval=\(rule.interval) end=\(String(describing: rule.recurrenceEnd?.endDate))")
                } else {
                    lines.append("  Recurrence: none")
                }
            } else {
                lines.append("  Event: none resolvable from stored identifier")
            }
            if let reminderIDs = habit.reminderIdentifiers, !reminderIDs.isEmpty {
                let reminders = reminderIDs.compactMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
                for reminder in reminders {
                    lines.append("  Reminder: due=\(String(describing: reminder.dueDateComponents)) completed=\(reminder.isCompleted)")
                }
                if reminders.isEmpty {
                    lines.append("  Reminders: \(reminderIDs.count) stored IDs, none resolvable")
                }
            } else {
                lines.append("  Reminders: none")
            }
        }

        lines.append("=== ALL events matching test titles (store-wide, ±3 days) ===")
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: .now))!
        let windowEnd = calendar.date(byAdding: .day, value: 3, to: calendar.startOfDay(for: .now))!
        let eventPredicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
        let matchingEvents = store.events(matching: eventPredicate).filter { testTitles.contains($0.title ?? "") }
        // `events(matching:)` returns one entry per *occurrence* — collapse
        // to distinct EKEvent identifiers so a healthy recurring event (one
        // identifier, several occurrences in the window) is distinguishable
        // from a genuine duplicate (two identifiers, same title).
        var byTitle: [String: Set<String>] = [:]
        for event in matchingEvents {
            byTitle[event.title ?? "?", default: []].insert(event.eventIdentifier ?? "?")
        }
        for (title, ids) in byTitle.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(title): \(ids.count) distinct event(s) [\(ids.map { String($0.suffix(8)) }.sorted().joined(separator: ", "))]")
        }
        if byTitle.isEmpty { lines.append("  (none)") }

        lines.append("=== ALL reminders matching test titles (store-wide) ===")
        let reminderLines = await Self.fetchAllReminderLines(matchingTitles: testTitles)
        lines.append(contentsOf: reminderLines)
        if reminderLines.isEmpty { lines.append("  (none)") }
        resultMessage = lines.joined(separator: "\n")
    }

    /// Returns pre-formatted description lines rather than the `EKReminder`
    /// objects themselves (`EKReminder` is non-Sendable and can't cross the
    /// continuation boundary under Swift 6), and is `nonisolated static`
    /// with its own store because `fetchReminders`'s completion fires on a
    /// background queue — a MainActor-inherited closure there trips a
    /// dispatch isolation assertion at runtime (found the hard way: real
    /// SIGTRAP in this exact spot).
    private nonisolated static func fetchAllReminderLines(matchingTitles: Set<String>) async -> [String] {
        let store = EKEventStore()
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForReminders(in: nil)) { reminders in
                let lines = (reminders ?? [])
                    .filter { matchingTitles.contains($0.title ?? "") }
                    .map { reminder in
                        let due = reminder.dueDateComponents.map { "\($0.year ?? 0)-\($0.month ?? 0)-\($0.day ?? 0) \($0.hour.map(String.init) ?? "allday"):\($0.minute ?? 0)" } ?? "nil"
                        return "  \(reminder.title ?? "?") id=\(String(reminder.calendarItemIdentifier.suffix(8))) due=\(due) completed=\(reminder.isCompleted)"
                    }
                continuation.resume(returning: lines)
            }
        }
    }

    private func completeTimerHabit() async {
        await setTimerHabitCompletion(isComplete: true)
    }

    private func uncompleteTimerHabit() async {
        await setTimerHabitCompletion(isComplete: false)
    }

    private func setTimerHabitCompletion(isComplete: Bool) async {
        guard let habit = (try? await habitRepository.fetchAll())?.first(where: { $0.id == Self.timerHabitID }) else {
            resultMessage = "Meditate Timer Habit not found — create test habits first."
            return
        }
        let todaysCompletions = (try? await habitRepository.fetchCompletions(for: .now)) ?? []
        var completion = todaysCompletions.first(where: { $0.habitID == habit.id }) ?? Completion(habitID: habit.id, date: .now)
        completion.isComplete = isComplete
        completion.count = isComplete ? habit.goal : 0
        completion.loggedAt = .now
        try? await habitRepository.upsertCompletion(completion)
        await calendarSyncService.mirrorCompletion(habit: habit, completion: completion)
        resultMessage = "Set Meditate Timer Habit isComplete=\(isComplete) and mirrored to Reminders."
    }

    private func deleteNoTimeHabit() async {
        guard let habit = (try? await habitRepository.fetchAll())?.first(where: { $0.id == Self.noTimeHabitID }) else {
            resultMessage = "No Time Habit not found — create test habits first."
            return
        }
        await calendarSyncService.removeSync(for: habit)
        try? await habitRepository.delete(id: habit.id)
        resultMessage = "Deleted No Time Habit and removed its EventKit sync."
    }
}

#Preview {
    DebugCalendarSyncView()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
#endif
