import SwiftUI

/// APP_REDESIGN_SPEC.md §13's daily mood check-in — a small, always-optional
/// card near the top of Home, adjacent to the weekly strip. Placed as the
/// first row of Home's scrollable list content, immediately below the
/// pinned `WeeklyRingsPagerView` (a judgment call: putting it *inside* that
/// view's own `.safeAreaInset` would mean two unrelated things sharing one
/// pinned bar, and that inset's height is deliberately tight-fit to just the
/// strip's own content — see `WeeklyRingsPagerView.body`'s `.frame(height:
/// 58)` comment) — this still reads as "near the top, adjacent to the
/// strip" without disturbing that tuning.
///
/// Single tap logs immediately — no confirmation step, no follow-up screen,
/// matching §13's "faster to log, more consistent" intent and staying
/// clearly distinct from Apple Health's slider-then-adjective-chip flow.
/// Tapping a different option after already logging today just overwrites
/// it (`MoodRepository.upsertEntry` is a real upsert) — never locked.
///
/// **Never guilt-trips**: there is no visual distinction for "a day went by
/// without logging" — no red dot, no streak, no missed-day count anywhere
/// on this card, by design (§13: "no guilt-tripping if skipped for a day or
/// several"). The only two states are "today logged, showing which" and
/// "today not logged yet, showing all 5 as plain equal options."
///
/// Deliberately does **not** touch `HabitRepository`, `MilestoneRepository`,
/// or `PointsLedger` — the only repository this card ever calls is
/// `MoodRepository`, kept that way specifically so mood logging can never
/// accidentally affect points/streaks.
struct MoodCheckInCard: View {
    @Environment(\.moodRepository) private var moodRepository
    @State private var todayEntry: MoodEntry?

    private var today: Date { Calendar.current.startOfDay(for: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How are you feeling today?")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(MoodLevel.allCases) { level in
                    moodButton(level)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await reload() }
    }

    private func moodButton(_ level: MoodLevel) -> some View {
        let isSelected = todayEntry?.mood == level
        return Button {
            Task { await log(level) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: level.systemImage)
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(isSelected ? level.color.opacity(0.22) : Color.clear)
                    )
                    .foregroundStyle(isSelected ? level.color : .secondary)
                Text(level.displayName)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("moodCheckIn.\(level.rawValue)")
        .accessibilityLabel(level.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func reload() async {
        todayEntry = try? await moodRepository.fetchEntry(for: today)
    }

    private func log(_ level: MoodLevel) async {
        let entry = MoodEntry(date: today, mood: level)
        todayEntry = entry
        try? await moodRepository.upsertEntry(entry)
    }
}

#Preview {
    MoodCheckInCard()
        .padding()
        .environment(\.moodRepository, InMemoryMoodRepository())
}
