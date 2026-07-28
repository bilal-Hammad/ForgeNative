import SwiftUI
import UserNotifications
import UIKit

/// Per-habit Notifications / Calendar / Reminders toggles — reached only
/// from Settings' Notifications section, and only when its master toggle is
/// on (see `SettingsView`). This is the single place these three change
/// after a habit is created; `HabitFormView` no longer has any UI for them.
///
/// All three are real now: `Notifications` via `HabitNotificationScheduler`,
/// `Sync to Calendar`/`Sync to Reminders App` via `CalendarSyncService`
/// (`EventKitCalendarSyncService` in production). Turning either sync
/// toggle on requests the relevant EventKit permission lazily, right here
/// — never proactively on launch — and, once granted, dispatches a real
/// sync (creates/updates the habit's `EKEvent`/`EKReminder`(s)); turning
/// either off removes whatever was created. A denied permission snaps the
/// toggle back off and shows an inline message rather than silently
/// leaving it "on" with nothing actually synced — same failure-visibility
/// principle `SettingsView`'s own master-notifications toggle already
/// established.
struct HabitSyncSettingsDetailView: View {
    let habit: Habit

    @Environment(\.habitRepository) private var habitRepository
    @Environment(\.calendarSyncService) private var calendarSyncService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("notificationsEnabledGlobal") private var globalNotificationsEnabled: Bool = false
    @AppStorage("weeklyReflectionEnabled") private var weeklyReflectionEnabledGlobal: Bool = false
    @AppStorage("weeklyReflectionWeekday") private var weeklyReflectionWeekday: Int = 1
    @AppStorage("weeklyReflectionHour") private var weeklyReflectionHour: Int = 18
    @AppStorage("weeklyReflectionMinute") private var weeklyReflectionMinute: Int = 0
    @State private var notificationsEnabled: Bool
    @State private var calendarSyncEnabled: Bool
    @State private var remindersAppSyncEnabled: Bool
    @State private var weeklyReflectionEnabled: Bool
    @State private var notificationPermissionDenied = false
    @State private var calendarAccessDenied = false
    @State private var remindersAccessDenied = false

    init(habit: Habit) {
        self.habit = habit
        _notificationsEnabled = State(initialValue: habit.notificationsEnabled)
        _calendarSyncEnabled = State(initialValue: habit.calendarSyncEnabled)
        _remindersAppSyncEnabled = State(initialValue: habit.remindersAppSyncEnabled)
        _weeklyReflectionEnabled = State(initialValue: habit.weeklyReflectionEnabled)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Notifications", isOn: $notificationsEnabled)
                Toggle("Sync to Calendar", isOn: $calendarSyncEnabled)
                    .disabled(!habit.isCalendarSyncSupported)
                Toggle("Sync to Reminders App", isOn: $remindersAppSyncEnabled)
                if notificationPermissionDenied || calendarAccessDenied || remindersAccessDenied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } footer: {
                syncFooter
            }

            if weeklyReflectionEnabledGlobal {
                Section {
                    Toggle("Include in Weekly Reflection", isOn: $weeklyReflectionEnabled)
                } footer: {
                    Text("Turn off to leave this habit out of the weekly summary notification, without affecting its own reminders above.")
                }
            }
        }
        .navigationTitle(habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPermissionStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Catches a permission revoked in iOS Settings while this
            // screen was already on-screen and simply backgrounded/
            // foregrounded (not pushed/popped, which `.task` above already
            // covers via NavigationStack destroying/recreating the view).
            guard newPhase == .active else { return }
            Task { await refreshPermissionStatus() }
        }
        .onChange(of: notificationsEnabled) { _, isOn in
            Task { await handleNotificationsToggleChange(isOn) }
        }
        .onChange(of: calendarSyncEnabled) { _, isOn in
            Task { await handleCalendarToggleChange(isOn) }
        }
        .onChange(of: remindersAppSyncEnabled) { _, isOn in
            Task { await handleRemindersToggleChange(isOn) }
        }
        .onChange(of: weeklyReflectionEnabled) { _, _ in
            Task { await persist() }
        }
    }

    @ViewBuilder
    private var syncFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = habit.calendarSyncUnsupportedReason {
                Text(reason)
            }
            if notificationPermissionDenied {
                Text("Notifications permission was denied — enable it in iOS Settings for this habit's reminders to actually fire.")
            }
            if calendarAccessDenied {
                Text("Calendar access is off — enable it in Settings to sync habits.")
            }
            if remindersAccessDenied {
                Text("Reminders access is off — enable it in Settings to sync habits.")
            }
            if habit.calendarSyncUnsupportedReason == nil, !notificationPermissionDenied, !calendarAccessDenied, !remindersAccessDenied {
                Text("Notifications use this habit's Time mode (set in its editor) for when they fire. Calendar sync creates one recurring event; Reminders sync creates a completable reminder and mirrors this habit's daily completion.")
            }
        }
    }

    private func refreshPermissionStatus() async {
        notificationPermissionDenied = await HabitNotificationScheduler.currentAuthorizationStatus() == .denied
        calendarAccessDenied = calendarSyncEnabled && calendarSyncService.calendarAuthorizationStatus() != .fullAccess
        remindersAccessDenied = remindersAppSyncEnabled && calendarSyncService.remindersAuthorizationStatus() != .fullAccess
    }

    private func handleNotificationsToggleChange(_ isOn: Bool) async {
        if isOn {
            let granted = await HabitNotificationScheduler.requestAuthorizationIfNeeded()
            notificationPermissionDenied = !granted
        }
        await persist()
    }

    private func handleCalendarToggleChange(_ isOn: Bool) async {
        if isOn {
            let granted = await calendarSyncService.requestCalendarAccessIfNeeded()
            calendarAccessDenied = !granted
            if !granted {
                calendarSyncEnabled = false
            }
        } else {
            calendarAccessDenied = false
        }
        await persist()
    }

    private func handleRemindersToggleChange(_ isOn: Bool) async {
        if isOn {
            let granted = await calendarSyncService.requestRemindersAccessIfNeeded()
            remindersAccessDenied = !granted
            if !granted {
                remindersAppSyncEnabled = false
            }
        } else {
            remindersAccessDenied = false
        }
        await persist()
    }

    private func persist() async {
        var updated = habit
        updated.notificationsEnabled = notificationsEnabled
        updated.calendarSyncEnabled = calendarSyncEnabled
        updated.remindersAppSyncEnabled = remindersAppSyncEnabled
        updated.weeklyReflectionEnabled = weeklyReflectionEnabled
        try? await habitRepository.save(updated)
        await HabitNotificationScheduler.reschedule(for: updated, globalNotificationsEnabled: globalNotificationsEnabled)
        // Muting/unmuting this habit changes what the next weekly
        // reflection's content should say — recompute it now rather than
        // waiting for the next app-foreground refresh.
        if weeklyReflectionEnabledGlobal {
            await WeeklyReflectionScheduler.reschedule(
                habitRepository: habitRepository,
                enabled: true,
                weekday: weeklyReflectionWeekday,
                hour: weeklyReflectionHour,
                minute: weeklyReflectionMinute
            )
        }
        // Awaited inline (not detached) — matches this function's existing
        // `HabitNotificationScheduler.reschedule` call right above, and
        // this is a deliberate, infrequent Settings-screen toggle action,
        // not the hot tap-to-complete path the "never awaited inline"
        // guidance is really about (see `HomeView
        // .dispatchReminderCompletionMirror`'s doc comment for that path).
        await calendarSyncService.sync(habit: updated)
    }
}

#Preview {
    NavigationStack {
        HabitSyncSettingsDetailView(habit: Habit(title: "Read a Book", category: .good, goal: 20, unit: .minutes, step: 5))
    }
    .environment(\.habitRepository, InMemoryHabitRepository())
}
