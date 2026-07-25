import SwiftUI

/// Progress page's "Consistency Heatmap" card — replaces the old
/// Apple-Activity-Ring-style "Today's Rings" card entirely. This app has no
/// circular ring visual left anywhere (the Home strip already made the same
/// rings→bars move — see `WeeklyRingsPagerView`'s history in CLAUDE.md), and
/// this redesign keeps that principle for Progress too, per explicit
/// instruction: a GitHub-contribution-style grid instead, day-cells shaded
/// by completion intensity.
///
/// **Layout — a judgment call the spec left open** ("either per-category...
/// or blended into one grid"): three small stacked grids, one per category
/// (Good/Bad/To-Do), each shaded in that category's own established color
/// (`HabitCategory.accentColor` — the same green/red/blue as the old
/// `RingsView`, the Home strip's bars, and category-scoped Milestone
/// badges) rather than one blended grid needing an invented new color
/// scale with no existing meaning elsewhere in the app.
///
/// **140-day window, not a literal GitHub year (371 days)** — another
/// judgment call, made to match `HabitDetailView`'s already-established
/// per-habit heatmap precedent (a fixed, readable size, not a rendering
/// cost that grows with habit age) rather than introduce a second, longer
/// heatmap convention in the same app. Same day-cell/gray-shade styling as
/// that view for the same reason.
///
/// Data is handed in pre-fetched by `ProgressScreenView.reload()` from
/// `HabitRepository.fetchCategoryCompletionRates` — the same bounded,
/// aggregated-inside-the-actor query `WeeklyRingsPagerView` already uses
/// for the Home strip's own per-day rates — one query for the whole
/// 140-day window, not one query per day or per category.
struct ConsistencyHeatmapCard: View {
    /// Per-day category completion rates, already fetched for (at least)
    /// the 140-day display window.
    let ratesByDay: [Date: (good: Double, bad: Double, todo: Double)]
    /// Earliest date any real data could exist — days before this render as
    /// "no data yet" (a different shade than "data exists, nothing done").
    let earliestDataDate: Date?

    private static let windowDays = 140
    private static let cellSize: CGFloat = 10
    private static let cellSpacing: CGFloat = 3

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<Self.windowDays).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    var body: some View {
        ProgressCard(title: "Consistency Heatmap") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(HabitCategory.allCases) { category in
                    categoryGrid(category)
                }
            }
        }
    }

    private func categoryGrid(_ category: HabitCategory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(repeating: GridItem(.fixed(Self.cellSize), spacing: Self.cellSpacing), count: 7),
                    spacing: Self.cellSpacing
                ) {
                    ForEach(days, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: day, category: category))
                            .frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func color(for day: Date, category: HabitCategory) -> Color {
        if let earliestDataDate, day < Calendar.current.startOfDay(for: earliestDataDate) {
            return Color(.systemGray6)
        }
        let rate: Double
        switch category {
        case .good: rate = ratesByDay[day]?.good ?? 0
        case .bad: rate = ratesByDay[day]?.bad ?? 0
        case .todo: rate = ratesByDay[day]?.todo ?? 0
        }
        guard rate > 0 else { return Color(.systemGray5) }
        return category.accentColor.opacity(0.2 + min(rate, 1) * 0.8)
    }
}

#Preview {
    ConsistencyHeatmapCard(ratesByDay: [:], earliestDataDate: nil)
        .padding()
}
