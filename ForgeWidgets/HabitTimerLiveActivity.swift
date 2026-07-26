import ActivityKit
import SwiftUI
import WidgetKit

/// Renders the running time-unit habit timer in the Dynamic Island and on
/// the Lock Screen via ActivityKit — Apple's own documented pattern for
/// exactly this scenario (their own Timer app uses the same
/// `Text(timerInterval:countsDown:)` view inside a Live Activity). No
/// custom per-second refresh anywhere in this file: the native timer views
/// update themselves from the real `Date` range, system-rendered even
/// while Forge itself is fully backgrounded or killed.
///
/// **Circular styling is a confirmed, deliberate exception to this
/// project's usual anti-Apple-copy visual rule** — see
/// `HabitTimerRingView`'s doc comment in the main app target (the in-app
/// counterpart to this view) and CLAUDE.md's "Timer Live Activity —
/// confirmed circular exception" note for the full reasoning. The user
/// explicitly confirmed wanting Apple's own Clock/Timer look here, unlike
/// everywhere else in this app.
///
/// **Deliberately still `ProgressView(timerInterval:).circular` here, not
/// the `Gauge`/`TimelineView` hybrid `HabitTimerRingView` switched to** —
/// see that view's doc comment for the empirical finding that this API
/// actually renders a spinner glyph, not a depleting ring. A `TimelineView`
/// needs its hosting process alive to re-fire its periodic closure; the
/// main app can rely on that (the view is only ever on screen while Forge
/// itself is running), but a Live Activity's entire purpose is staying
/// accurate while the app/extension process is fully suspended or killed.
/// `Text`/`ProgressView`'s `timerInterval` initializers are the specific,
/// Apple-documented views guaranteed to keep rendering correctly under
/// that constraint (the system itself repaints them, not the extension
/// process) — so correctness-under-suspension wins over the exact visual
/// here, even though it means the Live Activity's ring and the in-app
/// row's ring don't look identical. Flagged as a known, accepted
/// visual/behavior difference between the two, not an oversight.
struct HabitTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HabitTimerAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.iconSystemName)
                        .foregroundStyle(context.attributes.color.color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                        .font(.body.monospacedDigit())
                        .frame(width: 64)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.habitTitle)
                        .font(.headline)
                }
            } compactLeading: {
                Image(systemName: context.attributes.iconSystemName)
                    .foregroundStyle(context.attributes.color.color)
            } compactTrailing: {
                Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 40)
            } minimal: {
                ProgressView(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                    .progressViewStyle(.circular)
                    .tint(context.attributes.color.color)
                    .labelsHidden()
            }
        }
    }

    private func lockScreenView(context: ActivityViewContext<HabitTimerAttributes>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressView(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                    .progressViewStyle(.circular)
                    .tint(context.attributes.color.color)
                    .labelsHidden()
                Image(systemName: context.attributes.iconSystemName)
                    .foregroundStyle(context.attributes.color.color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.habitTitle)
                    .font(.headline)
                Text(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}
