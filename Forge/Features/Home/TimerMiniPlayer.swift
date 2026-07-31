import SwiftUI

/// A persistent, screen-level "now-playing"-style bar for a running/paused
/// time-unit habit timer (the Apple-Music mini-player pattern, adapted to
/// Forge). Pinned at the bottom of Home via `.safeAreaInset`, so it stays put
/// regardless of habit-list scroll and isn't scoped to any one row. Visible
/// whenever *any* timer-type habit is active (running or paused).
///
/// Collapsed it mirrors the Live Activity pill (icon circle · countdown ·
/// pause/resume). **Touch-and-hold** expands it — via the caller's `onExpand`,
/// which presents `TimerExpandedPanel` as a bottom sheet — matching how
/// Apple's own Workout Live Activity touch-and-holds the pill into a fuller
/// card. Replaced the earlier `.confirmationDialog` (2026-07-31).
struct TimerMiniPlayerBar: View {
    let habit: Habit
    let completion: Completion
    /// The habit's goal in seconds (`goal * unit.secondsPerUnit`).
    let goalDuration: TimeInterval
    /// Toggles pause⇄resume for this habit (the in-app pause path — updates
    /// the `Completion` and the Live Activity together; see `HomeView`).
    let onPauseResume: () -> Void
    /// Touch-and-hold — the caller presents the expanded panel.
    let onExpand: () -> Void

    private var isPaused: Bool { completion.isTimerPaused }

    /// Real run-start shifted back by banked elapsed, so a live
    /// `Text(timerInterval:)` lines up with total elapsed (matches the Live
    /// Activity's `effectiveStartDate`). Nil while paused.
    private var effectiveStart: Date? {
        completion.startedAt.map { $0.addingTimeInterval(-completion.accumulatedElapsed) }
    }
    private var end: Date? { effectiveStart.map { $0.addingTimeInterval(goalDuration) } }
    private var pausedRemaining: TimeInterval { max(0, goalDuration - completion.accumulatedElapsed) }

    var body: some View {
        HStack(spacing: 12) {
            // Icon + countdown are the touch-and-hold target, combined into
            // ONE accessibility element with the bar's identifier. The
            // pause button is a *sibling* (outside this element) so it keeps
            // its own identifier — a container `.accessibilityIdentifier`
            // cascades onto and overwrites children's ids (a real,
            // previously-documented trap in this project), which is why the
            // id lives here on a combined sub-view, not on the whole HStack.
            HStack(spacing: 12) {
                Image(systemName: habit.iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(habit.color.color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(habit.color.color.opacity(0.22)))

                countdown
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            // Touch-and-hold to expand — a short 0.3s hold, the system's own
            // long-press feel. The pause button (sibling) keeps its own tap.
            .onLongPressGesture(minimumDuration: 0.3) { onExpand() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timerMiniPlayer")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Touch and hold for timer options")

            Button(action: onPauseResume) {
                Image(systemName: isPaused ? "arrow.clockwise" : "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(habit.color.color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(habit.color.color.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timerMiniPlayer.pauseResume")
            .accessibilityLabel(isPaused ? "Resume timer" : "Pause timer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(habit.color.color.opacity(0.15)))
    }

    @ViewBuilder
    private var countdown: some View {
        if isPaused {
            Text(Self.countdownString(pausedRemaining))
        } else if let effectiveStart, let end {
            // In-app + foregrounded, so a live `Text(timerInterval:)` ticks
            // fine here (unlike the Live Activity, where `pauseTime` is
            // unreliable — see `HabitTimerLiveActivity`). `.id` forces a
            // clean swap to/from the static paused text.
            Text(timerInterval: effectiveStart...end, countsDown: true)
        } else {
            Text("--:--")
        }
    }

    static func countdownString(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// The touch-and-hold expansion of `TimerMiniPlayerBar` — a bottom sheet of
/// full-width action rows. Deliberately a simple, **extensible** vertical
/// stack (not a hardcoded 3-option layout): a future StoreKit "Islamic
/// template" is planned to add a dhikr/tasbih counter row here, so new rows
/// drop in without restructuring. Each action dismisses the panel.
struct TimerExpandedPanel: View {
    let habitTitle: String
    let onCompleteNow: () -> Void
    let onRestart: () -> Void
    let onStop: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(habitTitle)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                actionRow("Complete Now", systemImage: "checkmark.circle.fill", tint: .primary) {
                    onCompleteNow()
                }
                .accessibilityIdentifier("timerOptions.complete")

                Divider().padding(.leading, 56)

                actionRow("Restart Timer", systemImage: "arrow.counterclockwise", tint: .primary) {
                    onRestart()
                }
                .accessibilityIdentifier("timerOptions.restart")

                Divider().padding(.leading, 56)

                actionRow("Stop Timer", systemImage: "stop.circle.fill", tint: .red) {
                    onStop()
                }
                .accessibilityIdentifier("timerOptions.stop")
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)

            Spacer(minLength: 12)
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    private func actionRow(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
