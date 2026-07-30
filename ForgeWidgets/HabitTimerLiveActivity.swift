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
                }
            } compactLeading: {
                Image(systemName: context.attributes.iconSystemName)
                    .foregroundStyle(context.attributes.color.color)
            } compactTrailing: {
                timerText(context: context)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(context.attributes.color.color)
            }
        }
    }

    // MARK: - Lock Screen pill

    private func lockScreenView(context: ActivityViewContext<HabitTimerAttributes>) -> some View {
        HStack(spacing: 14) {
            iconBadge(context: context, size: 44)

            timerText(context: context)
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)

            pauseResumeButton(context: context, size: 44)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Shared pieces

    /// The habit's own icon in its own color, in a soft circular badge —
    /// never a generic system glyph.
    private func iconBadge(context: ActivityViewContext<HabitTimerAttributes>, size: CGFloat) -> some View {
        Image(systemName: context.attributes.iconSystemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(context.attributes.color.color)
            .frame(width: size, height: size)
            .background(Circle().fill(context.attributes.color.color.opacity(0.22)))
    }

    /// Ticking while running, frozen while paused — see the type doc comment.
    @ViewBuilder
    private func timerText(context: ActivityViewContext<HabitTimerAttributes>) -> some View {
        if context.state.isPaused {
            Text(Self.paused(remaining: context.state.pausedRemaining))
        } else {
            Text(timerInterval: context.state.effectiveStartDate...context.state.endDate, countsDown: true)
        }
    }

    private func pauseResumeButton(context: ActivityViewContext<HabitTimerAttributes>, size: CGFloat) -> some View {
        Button(intent: ToggleTimerPauseIntent(habitID: context.attributes.habitID)) {
            Image(systemName: context.state.isPaused ? "arrow.clockwise" : "pause.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(context.attributes.color.color)
                .frame(width: size, height: size)
                .background(Circle().fill(context.attributes.color.color.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }

    /// `mm:ss` (or `h:mm:ss`) for the frozen paused value — matches the
    /// shape `Text(timerInterval:)` renders while running.
    private static func paused(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
