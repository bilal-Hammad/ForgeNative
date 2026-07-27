import SwiftUI

/// A live, native countdown ring for a running time-unit habit.
///
/// **Real, empirically-confirmed finding, not assumed from the API name
/// alone**: `ProgressView(timerInterval:).progressViewStyle(.circular)` —
/// the API this view originally used, and the literal one suggested when
/// this feature was scoped — does **not** render as a depleting ring on
/// this SDK. Screenshot-verified (per this project's own established
/// practice of confirming visual changes, not trusting them from code
/// alone): it renders as the plain system activity-spinner glyph (a
/// pinwheel of static spokes), completely visually unrelated to how much
/// time remains, even though the countdown *text* next to it correctly
/// ticks down. That's a real gap from "Apple's own Clock/Timer app
/// styling," not a close match — a spinner reads as "loading," not "a
/// timer is running."
///
/// **What actually produces the depleting-ring look**: `Gauge(value:in:)`
/// styled `.accessoryCircularCapacity` — the same circular-capacity ring
/// API Apple itself uses for Watch complications and Live Activity
/// circular presentations. `Gauge` has no `timerInterval` initializer of
/// its own, so its `value` is recomputed each tick inside a
/// `TimelineView(.periodic(from:by:))` — SwiftUI's own native, declarative
/// mechanism for date-driven periodic UI updates (introduced specifically
/// to replace ad-hoc `Timer`-driven view refreshing), **not** a manual
/// `Timer`/`DispatchSourceTimer` instance. Each tick's fraction is derived
/// fresh from the real `start`/`end` `Date`s (`remaining / total`), never
/// from an incrementing counter — so, like the built-in `timerInterval`
/// views, it's always correct from real dates on the next render after a
/// background/lock, not dependent on ticks that happened while suspended.
/// `Text(timerInterval:)` for the countdown *digits* is unaffected by any
/// of this — it renders correctly as-is and still needs no custom refresh
/// logic at all.
///
/// **Circular styling is a confirmed, deliberate exception to this
/// project's usual anti-Apple-copy visual rule** — every other circular/
/// ring treatment in this app was deliberately replaced with something
/// else (Home's weekly strip: rings → bars; Progress: rings removed
/// entirely, §6; Milestones: squircle tiles, not Apple's hexagon/circle/
/// banner, §11). This one view is the sole exception, confirmed directly
/// with the user when this feature was scoped: a running timer should look
/// like Apple's own Clock/Timer app (a circular depleting ring with a
/// centered countdown). See CLAUDE.md's "Timer Live Activity — confirmed
/// circular exception" note for the same exception applied to the Live
/// Activity/Dynamic Island view in `ForgeWidgets`.
struct HabitTimerRingView: View {
    let start: Date
    let end: Date
    let tint: Color

    var body: some View {
        ZStack {
            TimelineView(.periodic(from: start, by: 1)) { context in
                let total = end.timeIntervalSince(start)
                let remaining = max(0, end.timeIntervalSince(context.date))
                let fraction = total > 0 ? remaining / total : 0
                Gauge(value: fraction, in: 0...1) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(tint)
            }

            // 12pt is the primary sizing strategy, not `minimumScaleFactor`
            // — a real-device screenshot with the original 9pt base showed
            // it shrinking as far as 4.5pt (illegible) for anything past a
            // couple digits. 12pt fits a "mm:ss"-length string cleanly in
            // this frame on its own; `minimumScaleFactor` stays only as a
            // safety net for genuine edge cases (e.g. Dynamic Type), same
            // legibility class as `quantityProgressIndicator`'s text below,
            // which this view's frame/stroke width now also matches.
            Text(timerInterval: start...end, countsDown: true)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 38)
        }
        .frame(width: 44, height: 44)
    }
}

#Preview {
    HabitTimerRingView(start: .now, end: .now.addingTimeInterval(600), tint: .blue)
}
