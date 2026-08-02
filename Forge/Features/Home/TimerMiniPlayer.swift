import SwiftUI

/// A persistent, screen-level "now-playing"-style bar for a running/paused
/// time-unit habit timer (the Apple-Music mini-player pattern, adapted to
/// Forge). Pinned at the bottom of Home via `.safeAreaInset`, so it stays put
/// regardless of habit-list scroll and isn't scoped to any one row. Visible
/// whenever *any* timer-type habit is active (running or paused).
///
/// Collapsed it mirrors the Live Activity pill (icon circle · countdown ·
/// pause/resume). **A tap** expands it — via the caller's `onExpand`, which
/// presents `TimerExpandedPanel` as a bottom sheet. Replaced the earlier
/// `.confirmationDialog` (2026-07-31); tap replaced an initial touch-and-hold
/// (2026-08-02) — a plain tap is the more discoverable, lower-friction
/// gesture for a bar that's persistently visible and has no other tap
/// target competing for a single tap (the pause/resume button is a
/// separate, sibling tap target, unaffected by this change).
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
            // A plain tap expands the panel. The pause button (sibling)
            // keeps its own separate tap target.
            .onTapGesture { onExpand() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("timerMiniPlayer")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens timer options")

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

/// The tap-to-expand panel for `TimerMiniPlayerBar` (redesigned 2026-08-02) —
/// a native-feeling Liquid Glass control screen modeled on Apple's own
/// Workout app control screen: a large countdown ring at top, icon-only
/// circular glass buttons below (no text labels in the button row — each
/// button carries a real `accessibilityLabel` instead, since a screen reader
/// user needs the same information a sighted user gets from a printed
/// label).
///
/// Reads the habit's **live** `Completion` — the caller passes
/// `HomeView.selectedDayCompletions[habit.id]` directly, not a snapshot
/// captured when the sheet was presented — so this view reactively swaps
/// between the running and paused button sets, including if the timer is
/// paused/resumed from the **Lock Screen** while this sheet happens to be
/// open (the existing scene-phase-foreground drain already keeps
/// `selectedDayCompletions` in sync on return to the app; this view just
/// needs to read that live value, which passing the dictionary lookup in
/// directly — rather than a value captured once — accomplishes).
///
/// **Stop no longer cancels the timer.** It now *pauses* it (banking
/// elapsed time, mirroring the Live Activity — the exact same
/// `HomeView.pauseTimer` the mini-player's own pause button already calls),
/// which is why tapping it transitions this same sheet to the paused button
/// set (Resume / Cancel) instead of dismissing it. Only Cancel (paused
/// state) fully discards progress.
///
/// **Liquid Glass API verified against the current SDK before use** (not
/// assumed) — `.buttonStyle(.glass)` / `.glassProminent` +
/// `.buttonBorderShape(.circle)` is the exact pattern this codebase already
/// uses for its one other circular glass button (`HomeView`'s "+" Add Habit
/// button); `GlassEffectContainer` wraps the row of 3 adjacent glass buttons
/// per Apple's own documented guidance (glass can't correctly sample
/// adjacent glass without a shared container); `.clipShape(Circle())` is
/// Apple's documented workaround for a `.glassProminent` +
/// `.buttonBorderShape(.circle)` rendering-artifact issue. This project's
/// deployment target is iOS 26.0 (`project.yml`) — every device this app
/// runs on has this API, so there's no `#available`/material-fallback
/// branch here; one would be dead code that could never execute (see
/// `glassButton`'s own doc comment).
///
/// **Reuse note, for later — do not build yet**: this glass-panel / big-ring
/// / icon-only-button shape is intended to be reused for the future dhikr/
/// adhkar counter UI (a separate, later feature per TASKS.md's Islamic
/// template pack) — no counter-specific code exists here, this is only a
/// flag for whoever picks that work up.
struct TimerExpandedPanel: View {
    let habit: Habit
    /// Live — see the type's doc comment on why this must be a passed-in
    /// dictionary lookup, not a value captured once.
    let completion: Completion?
    let goalDuration: TimeInterval
    /// Both states.
    let onCompleteNow: () -> Void
    /// Running state only.
    let onRestart: () -> Void
    /// Running state only — pauses (see the type's doc comment), never cancels.
    let onPause: () -> Void
    /// Paused state only — resumes from banked time, not a fresh restart.
    let onResume: () -> Void
    /// Paused state only — full discard.
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// The ring's frame (width = height) — Apple's own Workout control
    /// screen uses a large, immediately-readable ring; 140pt is roughly 3x
    /// the row glyph's original 44pt.
    private let ringSize: CGFloat = 140

    private var isPaused: Bool { completion?.isTimerPaused == true }

    /// Same "shift start back by banked elapsed" formula
    /// `TimerMiniPlayerBar` already uses, so the two stay in lockstep.
    private var effectiveStart: Date? {
        completion?.startedAt.map { $0.addingTimeInterval(-(completion?.accumulatedElapsed ?? 0)) }
    }
    private var end: Date? { effectiveStart.map { $0.addingTimeInterval(goalDuration) } }
    private var pausedRemaining: TimeInterval {
        max(0, goalDuration - (completion?.accumulatedElapsed ?? 0))
    }

    var body: some View {
        VStack(spacing: 28) {
            Text(habit.title)
                .font(.headline)
                .padding(.top, 22)

            ringDisplay

            GlassEffectContainer {
                HStack(spacing: 20) {
                    if isPaused {
                        pausedButtons
                    } else {
                        runningButtons
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }

    /// Running: the live, ticking `HabitTimerRingView` (generalized with a
    /// `size` parameter for this exact use — see that type's doc comment).
    /// Paused: a **static** frozen ring — a paused timer's remaining time
    /// doesn't change until resumed, so a live `TimelineView`/
    /// `Text(timerInterval:)` would be actively wrong here, not just
    /// unnecessary. Reuses `HabitTimerRingView`'s Gauge/`.accessoryCircular
    /// Capacity`/fraction math (the same `remaining / total` formula, same
    /// gauge style) without forcing a live-vs-frozen dual mode onto that
    /// shared, doc-commented component — and reuses `TimerMiniPlayerBar
    /// .countdownString` for the static digits rather than a second string
    /// formatter.
    @ViewBuilder
    private var ringDisplay: some View {
        if !isPaused, let effectiveStart, let end {
            HabitTimerRingView(start: effectiveStart, end: end, tint: habit.color.color, size: ringSize)
        } else {
            VStack(spacing: 6) {
                ZStack {
                    Gauge(value: goalDuration > 0 ? pausedRemaining / goalDuration : 0, in: 0...1) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(habit.color.color)

                    Text(TimerMiniPlayerBar.countdownString(pausedRemaining))
                        .font(.system(size: ringSize * (12.0 / 44.0), weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: ringSize * (38.0 / 44.0))
                }
                .frame(width: ringSize, height: ringSize)

                Text("Paused")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var runningButtons: some View {
        glassButton(systemImage: "checkmark", label: "Complete now", tint: .primary, prominent: false) {
            onCompleteNow()
            dismiss()
        }
        .accessibilityIdentifier("timerOptions.complete")

        // Unchanged from before this redesign: Restart dismisses after
        // acting (a fresh run has started; nothing more to show here).
        glassButton(systemImage: "arrow.counterclockwise", label: "Restart timer", tint: .primary, prominent: false) {
            onRestart()
            dismiss()
        }
        .accessibilityIdentifier("timerOptions.restart")

        // Deliberately no `dismiss()` — this pauses, transitioning this same
        // sheet to `pausedButtons` in place (see the type's doc comment).
        glassButton(systemImage: "stop.fill", label: "Stop timer", tint: .red, prominent: true) {
            onPause()
        }
        .accessibilityIdentifier("timerOptions.stop")
    }

    @ViewBuilder
    private var pausedButtons: some View {
        glassButton(systemImage: "checkmark", label: "Complete now", tint: .primary, prominent: false) {
            onCompleteNow()
            dismiss()
        }
        .accessibilityIdentifier("timerOptions.complete")

        // The most emphasized action while paused — this project's "one
        // accent action per view" convention — tinted with the habit's own
        // color, matching the mini-player's own pause/resume button.
        glassButton(systemImage: "play.fill", label: "Resume timer", tint: habit.color.color, prominent: true) {
            onResume()
            dismiss()
        }
        .accessibilityIdentifier("timerOptions.resume")

        glassButton(systemImage: "xmark", label: "Cancel timer", tint: .red, prominent: false) {
            onCancel()
            dismiss()
        }
        .accessibilityIdentifier("timerOptions.cancel")
    }

    /// One icon-only circular glass button. `@ViewBuilder` branches on
    /// `prominent` (rather than trying to type-erase `.glass` vs.
    /// `.glassProminent` into one call) since they're distinct concrete
    /// `ButtonStyle` types — the same shape this codebase already uses
    /// elsewhere for per-bucket conditional view construction.
    @ViewBuilder
    private func glassButton(systemImage: String, label: String, tint: Color, prominent: Bool, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glassProminent)
            .tint(tint)
            .buttonBorderShape(.circle)
            .clipShape(Circle())
            .accessibilityLabel(label)
        } else {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.glass)
            .tint(tint)
            .buttonBorderShape(.circle)
            .clipShape(Circle())
            .accessibilityLabel(label)
        }
    }
}
