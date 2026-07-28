import SwiftUI
import UserNotifications
import UIKit

/// Settings screen, reached from Profile's gear-icon toolbar button — mirrors
/// the RN app's own Profile/Settings split (SWIFT_REWRITE_INVENTORY.md):
/// Profile stays light/personal-focused, configuration rows live here.
/// Account/Sign-in lives on Profile itself, not here.
///
/// Real and functional: Dark Mode toggle (`@AppStorage`-backed, applied at
/// the app root in `AppTabView`), Archived Habits (real list + unarchive).
/// Sound Effects (`@AppStorage("soundEffectsEnabled")`, default `true`) gates
/// only the completion sound in `CompletionFeedback` — haptics are always
/// on, and sound separately always respects the device's silent switch
/// regardless of this toggle (see that type's doc comment).
///
/// The Notifications section is a single kill switch for all three of a
/// habit's sync toggles — local Notifications, Calendar sync, and
/// Reminders-app sync — not just Notifications alone. Turning the master
/// toggle on requests system permission right here (rather than
/// proactively on first launch), reschedules every habit's real
/// notifications per its own configuration, and reveals a habit list;
/// drilling into any habit opens `HabitSyncSettingsDetailView`, which is
/// the only place all three per-habit toggles live now (moved out of
/// `HabitFormView` entirely). Turning the master off cancels every habit's
/// pending notifications and hides the list — Calendar/Reminders sync
/// don't need an equivalent teardown since neither is wired to any real
/// EventKit data yet (state-only stubs, same as before this moved). If
/// permission comes back denied, the toggle snaps back off and this screen
/// shows a way to open iOS Settings, rather than silently leaving the
/// toggle "on" with nothing actually scheduled.
///
/// Vacation Mode (§8): toggle + date range are real and persisted, and now
/// genuinely pause (not break) streak/points evaluation for that window —
/// see `VacationSettings`/`StreakMath`/`MilestoneEngine`.
struct SettingsView: View {
    @Environment(\.habitRepository) private var habitRepository
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true
    @AppStorage("notificationsEnabledGlobal") private var notificationsEnabledGlobal: Bool = false
    @AppStorage("vacationModeEnabled") private var vacationModeEnabled: Bool = false
    @AppStorage("vacationStart") private var vacationStartInterval: Double = Date.now.timeIntervalSince1970
    @AppStorage("vacationEnd") private var vacationEndInterval: Double = Date.now.addingTimeInterval(7 * 86400).timeIntervalSince1970
    /// Independent of `notificationsEnabledGlobal` above — §13 asks for the
    /// mood reminder to be separately togglable, not bundled into the
    /// per-habit master switch (mood isn't a habit, and unlike that switch,
    /// this is the only notification this toggle ever manages).
    @AppStorage("moodCheckInReminderEnabled") private var moodCheckInReminderEnabled: Bool = false
    @AppStorage("moodCheckInReminderHour") private var moodCheckInReminderHour: Int = 20
    @AppStorage("moodCheckInReminderMinute") private var moodCheckInReminderMinute: Int = 0
    /// §13's weekly reflection — independent of both toggles above, same
    /// reasoning as mood's own independence: this is its own single
    /// notification, not part of the per-habit reminder budget. Default
    /// weekday 1 = Sunday (`Calendar`/`DateComponents.weekday` convention,
    /// 1...7 = Sun...Sat) at 18:00 — "Sunday evening" per §13's shipped
    /// default, still fully user-configurable.
    @AppStorage("weeklyReflectionEnabled") private var weeklyReflectionEnabled: Bool = false
    @AppStorage("weeklyReflectionWeekday") private var weeklyReflectionWeekday: Int = 1
    @AppStorage("weeklyReflectionHour") private var weeklyReflectionHour: Int = 18
    @AppStorage("weeklyReflectionMinute") private var weeklyReflectionMinute: Int = 0
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var habits: [Habit] = []

    private static let weekdaySymbols = Calendar.current.weekdaySymbols

    private var moodCheckInReminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: moodCheckInReminderHour, minute: moodCheckInReminderMinute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                moodCheckInReminderHour = components.hour ?? 20
                moodCheckInReminderMinute = components.minute ?? 0
            }
        )
    }

    private var weeklyReflectionTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: weeklyReflectionHour, minute: weeklyReflectionMinute, second: 0, of: .now) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                weeklyReflectionHour = components.hour ?? 18
                weeklyReflectionMinute = components.minute ?? 0
            }
        )
    }

    private var vacationStart: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: vacationStartInterval) },
            set: { vacationStartInterval = $0.timeIntervalSince1970 }
        )
    }

    private var vacationEnd: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: vacationEndInterval) },
            set: { vacationEndInterval = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark Mode", isOn: $isDarkMode)
            }

            Section {
                Toggle("Sound Effects", isOn: $soundEffectsEnabled)
            } footer: {
                Text("Plays a short sound when you complete a habit. Haptic feedback isn't affected by this setting, and sound always respects your device's silent switch.")
            }

            Section {
                Toggle("Notifications", isOn: $notificationsEnabledGlobal)
                if authorizationStatus == .denied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } footer: {
                if authorizationStatus == .denied {
                    Text("Notifications are denied in iOS Settings — enable them there for reminders to work.")
                } else {
                    Text("Master switch for local notifications, Calendar sync, and Reminders sync, for every habit at once. Turn on to manage each habit individually below.")
                }
            }

            // Shown whenever either per-habit toggle a habit can carry is
            // reachable from here — per-habit reminders (gated on the
            // master switch above) or the weekly reflection per-habit mute
            // (its own independent toggle, further below) — since both
            // live inside `HabitSyncSettingsDetailView` now. Without the
            // `||`, a user with reminders off but weekly reflection on
            // would have no way to reach the mute toggle for a specific
            // habit at all.
            if notificationsEnabledGlobal || weeklyReflectionEnabled {
                ForEach(HabitCategory.allCases) { category in
                    let categoryHabits = habits.filter { $0.category == category }
                    if !categoryHabits.isEmpty {
                        Section(category.displayName) {
                            ForEach(categoryHabits) { habit in
                                NavigationLink {
                                    HabitSyncSettingsDetailView(habit: habit)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: habit.iconSystemName)
                                            .foregroundStyle(habit.color.color)
                                            .frame(width: 24)
                                        Text(habit.title)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Mood Check-In Reminder", isOn: $moodCheckInReminderEnabled)
                if moodCheckInReminderEnabled {
                    DatePicker("Time", selection: moodCheckInReminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("A once-a-day nudge to log how you're feeling — always optional, never required, and separate from habit reminders above.")
            }

            Section {
                Toggle("Weekly Reflection", isOn: $weeklyReflectionEnabled)
                if weeklyReflectionEnabled {
                    Picker("Day", selection: $weeklyReflectionWeekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Self.weekdaySymbols[weekday - 1]).tag(weekday)
                        }
                    }
                    DatePicker("Time", selection: weeklyReflectionTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("A weekly summary of how your habits went — mute it for individual habits from that habit's own Notifications screen above.")
            }

            Section("Data") {
                NavigationLink("Archived Habits") {
                    ArchivedHabitsView()
                }
            }

            Section {
                Toggle("Vacation Mode", isOn: $vacationModeEnabled)
                if vacationModeEnabled {
                    DatePicker("Start", selection: vacationStart, displayedComponents: .date)
                    DatePicker("End", selection: vacationEnd, in: vacationStart.wrappedValue..., displayedComponents: .date)
                }
            } footer: {
                Text("No point loss or streak breaks during this window.")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("0.1.0")
                        .foregroundStyle(.secondary)
                }
            }

            #if DEBUG
            Section {
                NavigationLink("Seed Test History") {
                    DebugSeedHistoryView()
                }
                NavigationLink("Seed HealthKit Data") {
                    DebugSeedHealthKitView()
                }
                NavigationLink("Debug Calendar Sync") {
                    DebugCalendarSyncView()
                }
            } header: {
                Text("Debug")
            } footer: {
                Text("Backfills fake historical completions, or writes real HealthKit sample data, for testing. Debug builds only — compiled out of release entirely.")
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authorizationStatus = await HabitNotificationScheduler.currentAuthorizationStatus()
            let allHabits = (try? await habitRepository.fetchAll()) ?? []
            habits = allHabits.filter { !$0.isArchived }
        }
        .onChange(of: notificationsEnabledGlobal) { _, isOn in
            Task { await handleGlobalToggleChange(isOn) }
        }
        .onChange(of: moodCheckInReminderEnabled) { _, isOn in
            Task { await handleMoodReminderChange(isOn) }
        }
        .onChange(of: moodCheckInReminderHour) { _, _ in
            guard moodCheckInReminderEnabled else { return }
            Task { await rescheduleMoodReminder() }
        }
        .onChange(of: moodCheckInReminderMinute) { _, _ in
            guard moodCheckInReminderEnabled else { return }
            Task { await rescheduleMoodReminder() }
        }
        .onChange(of: weeklyReflectionEnabled) { _, isOn in
            Task { await handleWeeklyReflectionToggleChange(isOn) }
        }
        .onChange(of: weeklyReflectionWeekday) { _, _ in
            guard weeklyReflectionEnabled else { return }
            Task { await rescheduleWeeklyReflection() }
        }
        .onChange(of: weeklyReflectionHour) { _, _ in
            guard weeklyReflectionEnabled else { return }
            Task { await rescheduleWeeklyReflection() }
        }
        .onChange(of: weeklyReflectionMinute) { _, _ in
            guard weeklyReflectionEnabled else { return }
            Task { await rescheduleWeeklyReflection() }
        }
    }

    /// Turning the mood reminder on requests permission right here (same
    /// pattern as the habit-notifications master switch above) — if denied,
    /// the toggle snaps back off rather than staying "on" with nothing
    /// actually scheduled.
    private func handleMoodReminderChange(_ isOn: Bool) async {
        if isOn {
            let granted = await MoodNotificationScheduler.requestAuthorizationIfNeeded()
            if !granted {
                moodCheckInReminderEnabled = false
                return
            }
        }
        await rescheduleMoodReminder()
    }

    private func rescheduleMoodReminder() async {
        await MoodNotificationScheduler.reschedule(
            enabled: moodCheckInReminderEnabled,
            hour: moodCheckInReminderHour,
            minute: moodCheckInReminderMinute
        )
    }

    /// Same permission-request-here, snap-back-off-if-denied pattern as
    /// the mood reminder and the per-habit master switch above.
    private func handleWeeklyReflectionToggleChange(_ isOn: Bool) async {
        if isOn {
            let granted = await WeeklyReflectionScheduler.requestAuthorizationIfNeeded()
            if !granted {
                weeklyReflectionEnabled = false
                return
            }
        }
        await rescheduleWeeklyReflection()
    }

    private func rescheduleWeeklyReflection() async {
        await WeeklyReflectionScheduler.reschedule(
            habitRepository: habitRepository,
            enabled: weeklyReflectionEnabled,
            weekday: weeklyReflectionWeekday,
            hour: weeklyReflectionHour,
            minute: weeklyReflectionMinute
        )
    }

    /// Turning the master switch on requests permission right here (rather
    /// than proactively on first launch) and reschedules every habit's
    /// reminders per its own configuration; turning it off cancels all of
    /// them. If permission comes back denied, the toggle snaps back off
    /// instead of silently staying "on" with nothing actually scheduled.
    private func handleGlobalToggleChange(_ isOn: Bool) async {
        if isOn {
            let granted = await HabitNotificationScheduler.requestAuthorizationIfNeeded()
            authorizationStatus = await HabitNotificationScheduler.currentAuthorizationStatus()
            if !granted {
                notificationsEnabledGlobal = false
                return
            }
        } else {
            authorizationStatus = await HabitNotificationScheduler.currentAuthorizationStatus()
        }

        let habits = (try? await habitRepository.fetchAll()) ?? []
        for habit in habits {
            await HabitNotificationScheduler.reschedule(for: habit, globalNotificationsEnabled: notificationsEnabledGlobal)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(\.habitRepository, InMemoryHabitRepository())
}
