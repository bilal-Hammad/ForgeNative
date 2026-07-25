import SwiftUI
import UserNotifications
import UIKit

/// Per-habit Notifications / Calendar / Reminders toggles — reached only
/// from Settings' Notifications section, and only when its master toggle is
/// on (see `SettingsView`). This is the single place these three change
/// after a habit is created; `HabitFormView` no longer has any UI for them.
///
/// `Notifications` is the one of the three actually wired to something real
/// (`HabitNotificationScheduler`); `Sync to Calendar`/`Sync to Reminders
/// App` remain state-only stubs — no EventKit calls exist anywhere in this
/// app yet. Moving them here didn't change that, it just relocated where
/// the (still-inert) preference is recorded.
struct HabitSyncSettingsDetailView: View {
    let habit: Habit

    @Environment(\.habitRepository) private var habitRepository
    @AppStorage("notificationsEnabledGlobal") private var globalNotificationsEnabled: Bool = false
    @State private var notificationsEnabled: Bool
    @State private var calendarSyncEnabled: Bool
    @State private var remindersAppSyncEnabled: Bool
    @State private var notificationPermissionDenied = false

    init(habit: Habit) {
        self.habit = habit
        _notificationsEnabled = State(initialValue: habit.notificationsEnabled)
        _calendarSyncEnabled = State(initialValue: habit.calendarSyncEnabled)
        _remindersAppSyncEnabled = State(initialValue: habit.remindersAppSyncEnabled)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Notifications", isOn: $notificationsEnabled)
                Toggle("Sync to Calendar", isOn: $calendarSyncEnabled)
                Toggle("Sync to Reminders App", isOn: $remindersAppSyncEnabled)
                if notificationPermissionDenied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } footer: {
                if notificationPermissionDenied {
                    Text("Notifications permission was denied — enable it in iOS Settings for this habit's reminders to actually fire.")
                } else {
                    Text("Notifications use this habit's Time mode (set in its editor) for when they fire. Calendar/Reminders sync aren't wired up to real EventKit data yet — these just record your preference for when that lands.")
                }
            }
        }
        .navigationTitle(habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notificationPermissionDenied = await HabitNotificationScheduler.currentAuthorizationStatus() == .denied
        }
        .onChange(of: notificationsEnabled) { _, isOn in
            Task { await handleNotificationsToggleChange(isOn) }
        }
        .onChange(of: calendarSyncEnabled) { _, _ in
            Task { await persist() }
        }
        .onChange(of: remindersAppSyncEnabled) { _, _ in
            Task { await persist() }
        }
    }

    private func handleNotificationsToggleChange(_ isOn: Bool) async {
        if isOn {
            let granted = await HabitNotificationScheduler.requestAuthorizationIfNeeded()
            notificationPermissionDenied = !granted
        }
        await persist()
    }

    private func persist() async {
        var updated = habit
        updated.notificationsEnabled = notificationsEnabled
        updated.calendarSyncEnabled = calendarSyncEnabled
        updated.remindersAppSyncEnabled = remindersAppSyncEnabled
        try? await habitRepository.save(updated)
        await HabitNotificationScheduler.reschedule(for: updated, globalNotificationsEnabled: globalNotificationsEnabled)
    }
}

#Preview {
    NavigationStack {
        HabitSyncSettingsDetailView(habit: Habit(title: "Read a Book", category: .good, goal: 20, unit: .minutes, step: 5))
    }
    .environment(\.habitRepository, InMemoryHabitRepository())
}
