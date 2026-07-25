import SwiftUI

/// Archived habits list — ported from the RN app's `settings-archived.tsx`
/// per SWIFT_REWRITE_INVENTORY.md. Archived habits are hidden from Home's
/// active list but not deleted; unarchiving here restores them, including
/// resuming any notifications the habit was configured to send (paused
/// immediately on archive — see `HomeView.archive`).
struct ArchivedHabitsView: View {
    @Environment(\.habitRepository) private var habitRepository
    @AppStorage("notificationsEnabledGlobal") private var globalNotificationsEnabled: Bool = false
    @State private var archivedHabits: [Habit] = []

    var body: some View {
        List {
            if archivedHabits.isEmpty {
                Text("No archived habits.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(archivedHabits) { habit in
                    HStack {
                        Image(systemName: habit.iconSystemName)
                            .foregroundStyle(habit.color.color)
                        Text(habit.title)
                        Spacer()
                        Button("Unarchive") {
                            Task { await unarchive(habit) }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Archived Habits")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        let all = (try? await habitRepository.fetchAll()) ?? []
        archivedHabits = all.filter(\.isArchived)
    }

    private func unarchive(_ habit: Habit) async {
        var updated = habit
        updated.isArchived = false
        try? await habitRepository.save(updated)
        await HabitNotificationScheduler.reschedule(for: updated, globalNotificationsEnabled: globalNotificationsEnabled)
        await reload()
    }
}

#Preview {
    NavigationStack {
        ArchivedHabitsView()
    }
    .environment(\.habitRepository, InMemoryHabitRepository())
}
