import SwiftUI

/// Owns swipe-paging between weeks for Home's streak-lines strip
/// (APP_REDESIGN_SPEC.md §1), the date label above it, and the real per-day
/// completion data each week needs — `StreakLinesStripView` itself stays a
/// pure renderer (per-day connected-lines visual, one track per category;
/// see that type for why it replaced the earlier concentric-rings design).
///
/// **Paging mechanism — windowed/recentering, not a fixed range.** A real
/// `TabView(selection:)` in `.page` style (genuine native paging, UIKit
/// `UIPageViewController` under the hood, not a hand-rolled `DragGesture`)
/// over a small **constant-size window of at most 3 tags** — previous,
/// current, and next week relative to `centerWeekOffset` — never a fixed
/// range of thousands. This replaced an earlier design that rendered a
/// fixed `ForEach(minWeekOffset...0)` spanning up to 5201 pages
/// (~100 years back): SwiftUI's post-body reconciliation of that many
/// identities measurably delayed MainActor's return to pending `await`
/// continuations elsewhere in the app (confirmed via a direct before/after
/// test — see CLAUDE.md's "Home weekly strip freeze" entry). This is the
/// same windowed pattern Apple's own Health/Calendar/Fitness date pagers
/// use for effectively-unbounded history: only ever diff 3 items,
/// regardless of how far back the data goes.
///
/// Reaching either edge tag (swiping to the previous- or next-week page)
/// immediately shifts `centerWeekOffset` by one week in that direction and
/// snaps `pageSelection` back to the middle tag (`0`), wrapped in a
/// `Transaction` with animations disabled — since the middle tag's content
/// is recomputed against the new `centerWeekOffset` in that same update,
/// it already shows exactly what the user was just looking at, so the snap
/// is visually a no-op, not a jump. This is the standard "infinite
/// carousel" trick.
///
/// **Boundary behavior — real native rubber-band, not custom clamping.**
/// `visibleRelativeOffsets` shrinks the rendered tag set to 2 (or 1) right
/// at either true boundary — `centerWeekOffset == minWeekOffset` omits the
/// "previous" tag, `centerWeekOffset == 0` omits the "next" tag — so
/// `TabView(.page)` itself is a genuinely bounded page control at that
/// point and gives real rubber-band bounce for free, exactly as it did
/// under the old fixed-range design, with no gesture-blocking logic of any
/// kind. Because the out-of-bounds tag is never offered, `pageSelection`
/// can only ever become non-zero when the corresponding recenter is
/// already guaranteed in-bounds.
///
/// **Lower bound**: `minWeekOffset` is computed from the earliest
/// `habit.startDate` across all habits, not an arbitrary constant — there
/// is no real data before that point, so paging further back would only
/// ever show empty weeks. Falls back to `0` (today's week only, no paging
/// at all) until `habits` first loads, rather than allowing scroll into an
/// arbitrary past with nothing to show.
///
/// **Selection**: tapping any past or present day sets `selectedDate`,
/// which drives the date label above the strip ("21 Jul 2026") — future
/// placeholder days are disabled in `StreakLinesStripView` and can't be
/// selected at all. Swiping to a different week without tapping re-selects
/// the same weekday *position* in the new week (e.g. Wednesday stays
/// selected as you page back), matching how Calendar-style week strips
/// usually behave, rather than snapping to some fixed day. Either way —
/// an explicit tap, or the automatic weekday-carry-over on a page change —
/// fires the external `onSelectDay` callback, since `HomeView`'s habit list
/// underneath needs to track whichever day is actually selected here,
/// however it got there: tapping a day feeds it directly into that list
/// (grouped by category, read-only unless the selected day is today — see
/// `HomeView`'s own doc comment) instead of opening a separate screen.
///
/// **Data + prefetch**: each week's real per-day completion rates come from
/// `fetchCompletions(from:to:)` — the same bounded, indexed range query
/// used everywhere else in this app — cached in `progressByOffset` so a
/// week already viewed never re-fetches. The rate math is computed against
/// the `habits` array this view is handed; since `HomeView` passes that down
/// asynchronously (starts `[]`, populated once its own `reload()`
/// resolves), an `.onChange(of: habits)` clears the whole cache and
/// re-prefetches whenever it changes — including that first empty→populated
/// transition — otherwise a week could get permanently cached against zero
/// habits if this view's own initial `.task` won that race (confirmed by
/// hitting exactly that during on-device-equivalent Simulator verification:
/// a habit already complete for today rendered as an empty dot until this
/// invalidation was added).
///
/// **Why a *radius*, not just one neighbor**: an earlier version prefetched
/// only the single week on either side of the current one. That fixed the
/// original "stutter on first swipe into a new week" bug, but a user
/// flicking backward through several weeks in one quick burst (browsing
/// history) could still out-run a one-week cushion — each swipe only ever
/// extends the cached window by one, so a fast multi-week flick could
/// still land on an uncached week and visibly wait. `prefetch(around:)`
/// instead covers `prefetchRadiusWeeks` weeks on each side (bounded, not
/// unbounded — this is about this one device's own local query being fast
/// enough as *this user's* history grows over time, not a backend/
/// multi-user concern; there is no backend), and does it as a **single**
/// batched `fetchCompletions(from:to:)` call spanning only the *currently
/// missing* offsets in that window (already-cached weeks are skipped, so
/// repeated swiping only ever fetches the new uncovered edge, not
/// re-fetching the whole radius every time) rather than one query per
/// week — fewer round trips for the same bounded amount of real data.
struct WeeklyRingsPagerView: View {
    let habits: [Habit]
    var onSelectDay: (Date) -> Void = { _ in }

    @Environment(\.habitRepository) private var habitRepository
    /// The week the visible 3-tag window is centered on — `0` = this week,
    /// negative = past weeks. Replaces the old `weekOffset`, which used to
    /// be both the state *and* the `TabView` tag directly; now the tag is
    /// `pageSelection` (relative to this), and this is the absolute value
    /// every other function in this view still operates on.
    @State private var centerWeekOffset = 0
    /// The `TabView` selection — always relative to `centerWeekOffset`:
    /// `-1` previous, `0` current, `+1` next. Only ever settles somewhere
    /// other than `0` for the instant it takes `onChange` to recenter and
    /// snap it back; see the type's doc comment for why that snap is
    /// visually seamless.
    @State private var pageSelection = 0
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var progressByOffset: [Int: [Date: (good: Double, bad: Double, todo: Double)]] = [:]

    /// See the type's doc comment — computed from real data, not a fixed
    /// constant.
    private var minWeekOffset: Int {
        guard let earliestStart = habits.map(\.startDate).min() else { return 0 }
        let calendar = Calendar.current
        let earliestWeekStart = calendar.dateInterval(of: .weekOfYear, for: earliestStart)?.start ?? earliestStart
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weeks = calendar.dateComponents(
            [.weekOfYear],
            from: calendar.startOfDay(for: earliestWeekStart),
            to: calendar.startOfDay(for: thisWeekStart)
        ).weekOfYear ?? 0
        return -weeks
    }

    /// The 1–3 relative tags actually rendered this pass — shrinks at
    /// either true boundary so `TabView(.page)` stays a genuinely bounded
    /// page control there and gives real native rubber-band for free. See
    /// the type's doc comment.
    private var visibleRelativeOffsets: [Int] {
        var offsets = [0]
        if centerWeekOffset > minWeekOffset { offsets.insert(-1, at: 0) }
        if centerWeekOffset < 0 { offsets.append(1) }
        return offsets
    }

    /// Normalized to local midnight — see the type's doc comment on why
    /// every day-`Date` flowing through this view is built this same way.
    private let today = Calendar.current.startOfDay(for: .now)

    /// Every function below forces its result through
    /// `calendar.startOfDay(for:)` explicitly, even though
    /// `dateInterval(of: .weekOfYear, for:)` and `date(byAdding:to:)` are
    /// documented to already return midnight-aligned values — relying on
    /// that rather than asserting it explicitly previously let a stray
    /// time-of-day component slip through and cross the local midnight
    /// boundary once normalized to the user's timezone, causing a day-cell
    /// `Date` to silently match `selectedDate` a day off from where it
    /// should have. Forcing `startOfDay` here means nothing downstream
    /// (`isSelected`, `isToday`, `isFuture`, the `fetchCompletions` range)
    /// can receive an unnormalized day-`Date`.
    private func weekStart(for offset: Int) -> Date {
        let calendar = Calendar.current
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeekStart) ?? thisWeekStart
        return calendar.startOfDay(for: shifted)
    }

    private func weekDates(for offset: Int) -> [Date] {
        let calendar = Calendar.current
        let start = weekStart(for: offset)
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: start).map { calendar.startOfDay(for: $0) }
        }
    }

    /// How many days after its own week's start `today` falls — used to
    /// keep the same weekday position selected across a week change,
    /// independent of locale/first-weekday quirks (both sides of the
    /// comparison are computed the same way, so they stay consistent).
    private var todayIndexWithinWeek: Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return 0 }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: weekStart), to: today).day ?? 0
    }

    private func defaultSelectedDate(for offset: Int) -> Date {
        let dates = weekDates(for: offset)
        return dates.indices.contains(todayIndexWithinWeek) ? dates[todayIndexWithinWeek] : (dates.first ?? today)
    }

    /// "21 Jul 2026" — the primary label, always the exact selected day.
    private var selectedDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(selectedDateLabel)
                .font(.subheadline.weight(.semibold))
                .animation(.default, value: selectedDate)
                .accessibilityIdentifier("weeklyStrip.dateLabel")

            TabView(selection: $pageSelection) {
                ForEach(visibleRelativeOffsets, id: \.self) { relative in
                    StreakLinesStripView(
                        weekDates: weekDates(for: centerWeekOffset + relative),
                        progress: progressByOffset[centerWeekOffset + relative] ?? [:],
                        referenceToday: today,
                        selectedDate: selectedDate,
                        onSelectDay: { date in
                            selectedDate = date
                            onSelectDay(date)
                        }
                    )
                    // Do not add `.id(selectedDate)` (or any other identity
                    // keyed on `selectedDate`) to this page: it tears down
                    // and rebuilds the page mid-swipe, since
                    // `.onChange(of: pageSelection)` below also assigns
                    // `selectedDate` on every week-swipe — causing a visible
                    // stutter. Tried and reverted during the tap-to-select
                    // investigation (see git history / CLAUDE.md if this
                    // needs revisiting).
                    //
                    // Do not add an interactive `.overlay()` on top of a
                    // `StreakLinesStripView` page either — anything hosted
                    // there shares gesture space with the real day-cell
                    // buttons and can silently break their hit-testing (also
                    // found and reverted during that investigation).
                    .tag(relative)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("weeklyStrip.tabView")
            // Tight to the strip's real content height (header + 3 bars,
            // ~55pt — see `StreakLinesStripView.contentHeight`) rather than
            // the taller 78pt this inherited from the old concentric-rings
            // design: that extra height was previously invisible slack
            // inside the strip's `GeometryReader` (which top-aligns its
            // content, so unused height just became blank space below the
            // bars), reported as "a large empty gap" above the habit list.
            .frame(height: 58)
        }
        .task {
            await prefetch(around: centerWeekOffset)
        }
        .onChange(of: pageSelection) { _, newRelative in
            guard newRelative != 0 else { return }
            // `visibleRelativeOffsets` never renders an out-of-bounds edge
            // tag (see the type's doc comment), so this recenter is always
            // guaranteed in-bounds — no clamping needed here.
            let newCenter = centerWeekOffset + newRelative
            // Paging without an explicit tap still changes which day is
            // highlighted (the same weekday position, carried into the new
            // week) — `onSelectDay` fires here too, not just from a real
            // tap, since `HomeView`'s habit list needs to follow whichever
            // day the strip is actually showing as selected, however it got
            // there.
            let newSelectedDate = defaultSelectedDate(for: newCenter)
            selectedDate = newSelectedDate
            onSelectDay(newSelectedDate)
            Task { await prefetch(around: newCenter) }
            // Deferred to the next run-loop turn, deliberately NOT
            // synchronous with the `pageSelection` change we're reacting to.
            // The original version set `centerWeekOffset` and reset
            // `pageSelection` back to `0` synchronously, inside this same
            // `onChange` callback, in one `withTransaction`. That broke
            // paging in both directions: TabView(.page)'s underlying
            // UIPageViewController hadn't finished committing the real,
            // gesture-driven transition to the new page yet when the
            // 0→newRelative→0 round-trip got applied — SwiftUI appears to
            // coalesce that within a single update pass, so the interactive
            // swipe the user actually felt/saw never durably registered:
            // the page transition reverted with nothing to show for it
            // ("rubber-band, snaps back", identical in both directions,
            // since this same code path runs regardless of sign). Letting
            // the new page settle for one tick before recentering avoids
            // the coalescing.
            DispatchQueue.main.async {
                withTransaction(Transaction(animation: nil)) {
                    centerWeekOffset = newCenter
                    pageSelection = 0
                }
            }
        }
        .onChange(of: habits) { _, _ in
            // HomeView constructs this view with whatever `habits` it has
            // *right now* — on first launch that's `[]`, since HomeView's
            // own `reload()` populates it asynchronously and isn't
            // guaranteed to win the race against this view's own initial
            // `.task`. If that race is lost, `loadWeekIfNeeded` computes
            // every rate against zero habits (all zero, cached as such) and
            // then never re-runs once `habits` later arrives, since its own
            // guard only refetches a week that's *never* been cached —
            // not one cached from stale input. Any real change to `habits`
            // (including the empty→populated transition) invalidates the
            // whole cache and re-fetches around the current week.
            progressByOffset = [:]
            // `minWeekOffset` is derived from `habits`, so it can move
            // (typically further into the past as more history loads) —
            // reclamp `centerWeekOffset` defensively in case it's ever left
            // sitting before a newly-computed bound.
            let reclamped = max(minWeekOffset, min(0, centerWeekOffset))
            centerWeekOffset = reclamped
            pageSelection = 0
            Task { await prefetch(around: centerWeekOffset) }
        }
    }

    /// How many weeks on each side of the current one to keep pre-cached —
    /// see the type's doc comment for why a wider radius than one neighbor
    /// is needed. 4 weeks back covers a month of quick browsing in either
    /// direction; forward is naturally capped at offset `0` regardless.
    private static let prefetchRadiusWeeks = 4

    /// Fetches every currently-missing week within `prefetchRadiusWeeks` of
    /// `offset` in one bounded, batched query — called the moment
    /// `centerWeekOffset` settles. By the time a swipe to any week still inside
    /// that radius actually lands, its data is already cached and that page
    /// renders instantly; the fetch never happens on the gesture's critical
    /// path.
    private func prefetch(around offset: Int) async {
        let radius = Self.prefetchRadiusWeeks
        let lowerBound = max(minWeekOffset, offset - radius)
        let upperBound = min(0, offset + radius)
        guard lowerBound <= upperBound else { return }

        let neededOffsets = (lowerBound...upperBound).filter { progressByOffset[$0] == nil }
        guard !neededOffsets.isEmpty else { return }

        let neededWeekStarts = neededOffsets.map(weekStart(for:))
        guard let rangeStart = neededWeekStarts.min(),
              let latestWeekStart = neededWeekStarts.max(),
              let rangeEnd = Calendar.current.date(byAdding: .day, value: 6, to: latestWeekStart)
        else { return }

        // Aggregated inside the repository now — only one (good, bad, todo)
        // rate tuple per day crosses the actor boundary, not one full
        // `Completion` per habit per day. See `HabitRepository`'s doc
        // comment on this method, and CLAUDE.md's "Home weekly strip
        // prefetch" entry, for the investigation this came out of.
        let ratesByDay = (try? await habitRepository.fetchCategoryCompletionRates(habits: habits, from: rangeStart, to: rangeEnd)) ?? [:]
        let calendar = Calendar.current

        for weekOffsetToFill in neededOffsets {
            var result: [Date: (good: Double, bad: Double, todo: Double)] = [:]
            for date in weekDates(for: weekOffsetToFill) {
                let day = calendar.startOfDay(for: date)
                result[day] = ratesByDay[day] ?? (0, 0, 0)
            }
            progressByOffset[weekOffsetToFill] = result
        }
    }
}

#Preview {
    WeeklyRingsPagerView(habits: [])
        .padding()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
