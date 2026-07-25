import SwiftUI

/// One week's continuous-bar strip — three colored progress ribbons under
/// a day-letter header, one per category (Good/Bad/To-Do), no text labels
/// or node markers. A segment's color encodes that day's completion for
/// that category:
/// - **Complete** (100%): full saturated category color.
/// - **Incomplete** (past or today, not yet 100%): a pale tint of the same
///   color — never a completely different neutral, so it still reads as
///   "this category, not there yet" rather than just "empty."
/// - **Future**: muted neutral gray, non-interactive.
///
/// **Colors**: Good = green, To-Do = blue — both match
/// `HabitCategory.accentColor` used elsewhere (rings, milestones). Bad is a
/// deliberate exception: `HabitCategory.accentColor`'s Bad is red, but this
/// strip specifically uses a distinct coral/orange (`badBarColor` below)
/// per an explicit design call — not an oversight, and not reused elsewhere.
///
/// **Architecture — one `Button` per day, each owning its full visual
/// content.** Each day is a single `ZStack` (selection-pill background +
/// day letter + all 3 category bar segments) wrapped directly in that
/// day's own `Button`, with `.frame()` then `.contentShape(Rectangle())`
/// applied to that one view as a whole. This replaced an earlier design
/// that split the strip into a row-based visual layer (header row + 3 bar
/// rows, non-interactive) rendered as an `.overlay` on top of a *separate*
/// column-based interaction layer (7 buttons underneath, aligned only by
/// matching `columnWidth` values) — see CLAUDE.md's "Open bug —
/// tap-to-select-day" section for the multi-round history of why that
/// split kept producing real-device hit-testing bugs (an unselected,
/// near-invisible-filled cell's `Button` intermittently failed to receive
/// taps even with a correctly-ordered `.contentShape`, while the one
/// opaque/selected cell always worked). Collapsing to one owned `ZStack`
/// per day removes the split entirely: there is exactly one view tree per
/// day, so the interactive shape and the visual content can't silently
/// diverge again. Selected vs. unselected differ **only** in the fill
/// color/opacity passed into that one shared structure — never in which
/// views get built.
///
/// Bar segments round only their outer corner (first day's leading edge,
/// last day's trailing edge) via `UnevenRoundedRectangle`, computed
/// per-cell now that each day owns its own bar segments — reproducing the
/// previous row-level "whole-week `.clipShape`" look without a
/// row-spanning shape.
struct StreakLinesStripView: View {
    let weekDates: [Date]
    let progress: [Date: (good: Double, bad: Double, todo: Double)]
    var referenceToday: Date = .now
    var selectedDate: Date = .now
    var onSelectDay: (Date) -> Void = { _ in }

    private let segmentGap: CGFloat = 1
    private let barHeight: CGFloat = 8
    private let headerHeight: CGFloat = 16
    private let rowSpacing: CGFloat = 5

    private enum DotState: Equatable {
        case complete
        case incomplete
        case future
    }

    private struct Row {
        let category: HabitCategory
        let color: Color
    }

    /// Bad's coral/orange is intentionally distinct from
    /// `HabitCategory.accentColor`'s red — see the type's doc comment.
    private let badBarColor = Color(red: 1.0, green: 0.45, blue: 0.32)

    private var rows: [Row] {
        [
            Row(category: .good, color: HabitCategory.good.accentColor),
            Row(category: .bad, color: badBarColor),
            Row(category: .todo, color: HabitCategory.todo.accentColor),
        ]
    }

    /// Header + 3 bars + the `rowSpacing` gaps between all 4 — every day
    /// cell's real, compact content height.
    private var contentHeight: CGFloat {
        headerHeight + rowSpacing * CGFloat(rows.count) + barHeight * CGFloat(rows.count)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: referenceToday)
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func isFuture(_ date: Date) -> Bool {
        Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: referenceToday)
    }

    private func dayLetter(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        return symbols[weekday]
    }

    private func dotState(for date: Date, category: HabitCategory) -> DotState {
        guard !isFuture(date) else { return .future }
        let day = Calendar.current.startOfDay(for: date)
        let value: Double?
        switch category {
        case .good: value = progress[day]?.good
        case .bad: value = progress[day]?.bad
        case .todo: value = progress[day]?.todo
        }
        return (value ?? 0) >= 1.0 ? .complete : .incomplete
    }

    private func segmentColor(for state: DotState, categoryColor: Color) -> Color {
        switch state {
        case .complete: categoryColor
        case .incomplete: categoryColor.opacity(0.25)
        case .future: Color(.systemGray5)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let columnWidth = max(0, (geo.size.width - segmentGap * 6) / 7)
            HStack(spacing: segmentGap) {
                ForEach(Array(weekDates.enumerated()), id: \.element) { index, date in
                    dayCell(
                        date: date,
                        columnWidth: columnWidth,
                        isFirst: index == 0,
                        isLast: index == weekDates.count - 1
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    /// One day's entire visual content — selection background, day
    /// letter, and all 3 category bar segments — owned by a single
    /// `Button`/`ZStack`, so there is exactly one view tree per day and no
    /// separate interactive/visual layers that could diverge. See the
    /// type's doc comment for why this replaced the earlier split
    /// architecture.
    private func dayCell(date: Date, columnWidth: CGFloat, isFirst: Bool, isLast: Bool) -> some View {
        let selected = isSelected(date)
        let future = isFuture(date)
        let today = isToday(date)

        return Button {
            onSelectDay(date)
        } label: {
            ZStack {
                // Selection background. The fill color is the ONLY thing
                // that differs between a selected and unselected cell —
                // this shape, and everything else in this view, is built
                // identically regardless of `selected`, so there's no way
                // for the two states to end up with different
                // `.contentShape` coverage.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color(.systemGray5) : Color(.systemGray5).opacity(0.001))

                VStack(spacing: rowSpacing) {
                    Text(dayLetter(date))
                        .font(.caption2.weight(today ? .bold : .regular))
                        .foregroundStyle(today ? .primary : .secondary)
                        .frame(height: headerHeight)

                    ForEach(rows, id: \.category) { row in
                        barSegment(date: date, row: row, isFirst: isFirst, isLast: isLast)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: columnWidth, height: contentHeight)
        .contentShape(Rectangle())
        .disabled(future)
    }

    /// A single category's bar segment for one day. Only the first day's
    /// leading corners and the last day's trailing corners are rounded,
    /// reproducing the previous row-spanning `.clipShape`'s "rounded only
    /// at the two outer ends" look now that each day owns its own segment.
    private func barSegment(date: Date, row: Row, isFirst: Bool, isLast: Bool) -> some View {
        let radius = barHeight / 2
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0,
            bottomLeadingRadius: isFirst ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0,
            topTrailingRadius: isLast ? radius : 0,
            style: .continuous
        )
        .fill(segmentColor(for: dotState(for: date, category: row.category), categoryColor: row.color))
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }
}

#Preview {
    let calendar = Calendar.current
    let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    return StreakLinesStripView(
        weekDates: dates,
        progress: [
            calendar.startOfDay(for: dates[0]): (1.0, 1.0, 0.0),
            calendar.startOfDay(for: dates[1]): (1.0, 0.5, 1.0),
            calendar.startOfDay(for: dates[2]): (1.0, 1.0, 1.0),
            calendar.startOfDay(for: dates[3]): (0.0, 1.0, 1.0),
        ]
    )
    .frame(height: 78)
    .padding()
}
