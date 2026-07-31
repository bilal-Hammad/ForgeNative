import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Renders the running time-unit habit timer in the Dynamic Island and on
/// the Lock Screen via ActivityKit. Redesigned (2026-07-30) to match the
/// reference screenshot of Apple's own Workout Live Activity: a horizontal
/// pill with exactly three elements — a circular habit-icon badge on the
/// left, a large monospaced countdown in the center, and a circular
/// pause/resume button on the right. **No stop/cancel control here, by
/// explicit product decision** — cancelling a timer lives in the in-app row
/// (a second tap → `HomeView.cancelTimer`), independent of this view.
///
/// **Circular icon/button styling is a confirmed, deliberate exception to
/// this project's anti-Apple-copy visual rule** — the user explicitly wants
/// Apple's own timer/Workout look here (see CLAUDE.md's "Timer Live Activity
/// — confirmed circular exception").
///
/// **The countdown's rendering mode depends on `isPaused`:**
/// - Running: `Text(timerInterval: effectiveStartDate...endDate,
///   countsDown: true)` — the system repaints this itself, staying accurate
///   while the extension is suspended (a plain `Timer` would drift/freeze).
/// - Paused: a *static* `Text` of the frozen `pausedRemaining` — a
///   `timerInterval` view keeps ticking regardless of app pause state, so it
///   would keep counting down even while paused. This is the whole reason
///   `ContentState.isPaused` exists.
struct HabitTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HabitTimerAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    iconBadge(context: context, size: 34)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    pauseResumeButton(context: context, size: 34)
                }
                DynamicIslandExpandedRegion(.center) {
                    timerText(context: context)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .id(context.state.isPaused)
                }
            } compactLeading: {
                Image(systemName: context.attributes.iconSystemName)
                    .foregroundStyle(context.attributes.color.color)
            } compactTrailing: {
                timerText(context: context)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: isFinished(context) ? "checkmark.circle.fill" : (context.state.isPaused ? "pause.fill" : "timer"))
                    .foregroundStyle(context.attributes.color.color)
            }
        }
    }

    // MARK: - Lock Screen pill

    private func lockScreenView(context: ActivityViewContext<HabitTimerAttributes>) -> some View {
        HStack(spacing: 14) {
            iconBadge(context: context, size: 44)

            // `.multilineTextAlignment(.center)` is load-bearing, not
            // decorative: `Text(timerInterval:)` reserves width for the
            // widest format ("h:mm:ss") and left-aligns the current digits
            // within that reserved block, so a `.frame(maxWidth: .infinity)`
            // alone leaves the running text visibly left-of-center while the
            // static paused `Text` (no reserved slack) sits centered — the
            // exact mismatch Bilal's screenshots showed. Centering the text
            // within its own bounds makes both branches land on the same
            // center point (Bug B, 2026-07-30).
            timerText(context: context)
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                // Force a fresh view identity when pausing/resuming so
                // SwiftUI tears down the system-drawn ticking `Text
                // (timerInterval:)` and builds the static paused `Text` from
                // scratch — see `timerText`'s doc for why the number wouldn't
                // otherwise freeze.
                .id(context.state.isPaused)

            pauseResumeButton(context: context, size: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Shared pieces

    /// True once a *running* timer has reached its goal. Derived from the
    /// timeline, not a `ContentState` flag — the extension can't run a
    /// callback at 0:00, but the view re-renders when the content goes stale
    /// (`staleDate` is set to `endDate` while running), so this flips to
    /// "done" at the goal instant even while the app is suspended. A paused
    /// timer is never "finished" — its `endDate` may be in the past, but the
    /// frozen `endDate - pausedAt` is what's real.
    private func isFinished(_ context: ActivityViewContext<HabitTimerAttributes>) -> Bool {
        !context.state.isPaused && context.state.endDate <= Date.now
    }

    /// The habit's own icon in its own color, in a soft circular badge —
    /// never a generic system glyph.
    private func iconBadge(context: ActivityViewContext<HabitTimerAttributes>, size: CGFloat) -> some View {
        Image(systemName: context.attributes.iconSystemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(context.attributes.color.color)
            .frame(width: size, height: size)
            .background(Circle().fill(context.attributes.color.color.opacity(0.22)))
    }

    /// Running → a live ticking `Text(timerInterval:)`; paused → a **static**
    /// `Text` of the frozen remaining; goal reached → "Done".
    ///
    /// **Why static-when-paused instead of `Text(timerInterval:pauseTime:)`**:
    /// verified against current Apple guidance + community reports (Apple DTS
    /// forum thread 783557; blakecrosley "Live Activities are a state
    /// machine") — `pauseTime` does *not* reliably freeze a mid-countdown
    /// value in a Live Activity (it only reliably stops the timer at 0:00).
    /// Real-device evidence (2026-07-31) confirmed the exact symptom: the
    /// pause button icon toggled (so the `ContentState` update reached the
    /// view) but the `Text(timerInterval:pauseTime:)` number kept ticking.
    /// The correct pattern is to render two different views by state, forcing
    /// a fresh identity (`.id(isPaused)` at the call site) so the system
    /// tears the ticking view down. The frozen value is derived from the
    /// timeline (`endDate - pausedAt`), so no extra `ContentState` field.
    @ViewBuilder
    private func timerText(context: ActivityViewContext<HabitTimerAttributes>) -> some View {
        if isFinished(context) {
            Text("Done")
                .foregroundStyle(context.attributes.color.color)
        } else if let pausedAt = context.state.pausedAt {
            Text(Self.countdownString(max(0, context.state.endDate.timeIntervalSince(pausedAt))))
        } else {
            Text(timerInterval: context.state.effectiveStartDate...context.state.endDate, countsDown: true)
        }
    }

    /// `m:ss` (or `h:mm:ss`) — matches how `Text(timerInterval:)` renders the
    /// live countdown, so pausing/resuming doesn't change the format.
    private static func countdownString(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// Pause/resume while active; once finished, a non-interactive filled
    /// checkmark (nothing left to pause) — matching Apple's Workout Live
    /// Activity ending on a completion glyph rather than a live control.
    @ViewBuilder
    private func pauseResumeButton(context: ActivityViewContext<HabitTimerAttributes>, size: CGFloat) -> some View {
        if isFinished(context) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(context.attributes.color.color)
                .frame(width: size, height: size)
        } else {
            Button(intent: ToggleTimerPauseIntent(habitID: context.attributes.habitID)) {
                Image(systemName: context.state.isPaused ? "arrow.clockwise" : "pause.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(context.attributes.color.color)
                    .frame(width: size, height: size)
                    .background(Circle().fill(context.attributes.color.color.opacity(0.22)))
            }
            .buttonStyle(.plain)
        }
    }
}
