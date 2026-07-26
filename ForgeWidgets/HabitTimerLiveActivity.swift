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

    /// **Layout bug found via a real on-device Lock Screen screenshot,
    /// fixed here**: the habit icon used to sit in the same `ZStack`/frame
    /// as the countdown ring, directly on top of it — the ring genuinely
    /// does render a legible countdown number of its own in this real Live
    /// Activity context (unlike the plain in-app `ProgressView
    /// (timerInterval:).circular`, which was separately found to render as
    /// a bare spinner glyph — see this file's other doc comment), so the
    /// overlapping icon was obscuring real, otherwise-legible text. Fixed
    /// by giving the icon its own dedicated trailing position instead of
    /// sharing the ring's bounds — ring (+ its own countdown text) on the
    /// left, title in the middle, icon on the right, nothing overlapping
    /// anything else.
    private func lockScreenView(context: ActivityViewContext<HabitTimerAttributes>) -> some View {
        HStack(spacing: 14) {
            // No separate `Text(timerInterval:)` layered in here — a real
            // on-device Lock Screen screenshot after the icon-overlap fix
            // above showed a garbled, doubled numeral, because
            // `ProgressView(timerInterval:).circular` already draws its
            // own legible countdown number inside the ring in this real
            // Live Activity context (`.labelsHidden()` only suppresses the
            // peripheral title, not this) — confirmed via that same
            // screenshot. Adding another `Text` on top of it was
            // redundant, not additive.
            ProgressView(timerInterval: context.attributes.startDate...context.state.endDate, countsDown: true)
                .progressViewStyle(.circular)
                .tint(context.attributes.color.color)
                .labelsHidden()
                .frame(width: 50, height: 50)

            Text(context.attributes.habitTitle)
                .font(.headline)
                .lineLimit(2)

            Spacer()

            Image(systemName: context.attributes.iconSystemName)
                .font(.title2)
                .foregroundStyle(context.attributes.color.color)
        }
        .padding()
    }
}
