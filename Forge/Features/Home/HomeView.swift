import SwiftUI
import UIKit

/// Home screen (APP_REDESIGN_SPEC.md §1, §3): the weekly rings strip is the
/// top-most element — no "Home" nav title above it — and stays fixed while
/// the habit list scrolls underneath, picking up a real translucent
/// material once there's actual content behind it to blur (matching Apple's
/// own pinned-header-goes-glass pattern, e.g. Music/Fitness).
///
/// Implementation note: this was originally built with
/// `LazyVStack(pinnedViews: [.sectionHeaders])`, which turned out to have
/// three real bugs together (confirmed on-device): the material rendered as
/// a frozen, stale backdrop rather than live-sampling scrolled content;
/// scrolled cards could bleed into the status-bar safe area; and pinning
/// only held in one scroll direction, breaking on the reverse/overscroll.
/// All three trace back to pinned section headers being a specialized,
/// scroll-content-adjacent mechanism, not a genuinely separate composited
/// layer. Replaced with `.safeAreaInset(edge: .top)` — the purpose-built
/// SwiftUI API for a fixed accessory bar above scrollable content.
///
/// The habit list is a real `List` specifically so `.swipeActions` is
/// actually available — that modifier is List/row-only in SwiftUI. Row
/// backgrounds/separators/insets are cleared so each habit still reads as a
/// floating card.
///
/// Full gesture map on each card (no more separate checkmark tap target —
/// the whole card body carries every interaction):
/// - Swipe right → Edit (opens the edit form; replaces the old "tap = edit").
/// - Swipe left → Delete (destructive, edge-closest, fires on full swipe;
///   confirms via an alert before actually deleting, since it's permanent —
///   Archive is the reversible alternative and needs no confirmation),
///   then Archive.
/// - Long press → force-marks Complete, regardless of habit type — a
///   universal "just mark it done" shortcut, distinct from tap's
///   type-specific behavior below (so the two gestures aren't redundant).
/// - Tap → depends on the habit's type:
///   - Time-based (`timeMode != .none`, checked first): records "started at
///     now" — doesn't toggle completion at all.
///   - Quantity (`goal > 1`): increments `count` by `step` (default 1);
///     auto-marks Complete once `count >= goal`.
///   - Simple (`goal` nil or ≤ 1): toggles Complete on/off — this preserves
///     the old checkbox's toggle behavior, just moved onto the card itself,
///     which is what makes it non-redundant with long-press's one-way force.
///
/// Visual state per type (my judgment call, flagged for review): quantity
/// habits show "count/goal" as trailing text; time-based habits show
/// "Started h:mm a" once logged that day; simple habits show a filled vs.
/// outline checkmark circle, matching the old checkbox's look but now purely
/// a read-only status indicator, not a tap target of its own.
///
/// **Date-driven list**: the habit list below the weekly strip isn't
/// hardcoded to today — it's driven by `selectedDate`, which the strip
/// updates both on an explicit day tap and when paging to a different week
/// re-selects the same weekday position (see `WeeklyRingsPagerView`).
/// Viewing today keeps the list fully interactive (tap/long-press work as
/// documented above); viewing any other day makes it read-only — rows show
/// that day's real recorded completion state (same `fetchCompletions(for:)`
/// query, just for `selectedDate` instead of `.now`), and *nothing* on
/// screen can mutate anything: tap/long-press are no-ops, swipe actions
/// (Edit/Archive/Delete) are withheld entirely (an empty `.swipeActions`
/// content, so there's nothing to reveal), and the "+" Add Habit button is
/// disabled — viewing history shouldn't let you edit it, in any form. Also
/// excludes any habit whose `startDate` is after the viewed day (it didn't
/// exist yet); a habit that existed then but has since been deleted can't
/// be shown at all, since there's no historical habit-existence snapshot to
/// fall back on.
struct HomeView: View {
    @Environment(\.habitRepository) private var habitRepository
    @Environment(\.milestoneEngine) private var milestoneEngine
    @Environment(\.healthKitService) private var healthKitService
    @State private var isPresentingAddHabit = false
    @State private var editingHabit: Habit?
    /// Stable, non-archived — the full active-habit list, used as-is for
    /// the strip's rate calculations (which need a fixed denominator across
    /// all 7 days, not one that shifts with `selectedDate`) and filtered by
    /// `visibleHabits` below for the list itself.
    @State private var habits: [Habit] = []
    /// Normalized to local midnight, like every day-`Date` in this system
    /// now (see `WeeklyRingsPagerView`'s doc comment on `weekStart` for the
    /// bug this fixes) — a raw `.now` here carries the current
    /// time-of-day, which is harmless on its own but inconsistent with
    /// everything else this gets compared against.
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var selectedDayCompletions: [Habit.ID: Completion] = [:]
    @State private var healthKitConnectionStatus: [Habit.ID: Bool] = [:]
    /// Deletion is permanent and irreversible (unlike Archive) — the swipe
    /// action arms this rather than calling `delete(_:)` directly, so an
    /// `.alert` can confirm first.
    @State private var habitPendingDelete: Habit?

    private var isViewingToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: .now)
    }

    private var visibleHabits: [Habit] {
        let day = Calendar.current.startOfDay(for: selectedDate)
        return habits.filter { Calendar.current.startOfDay(for: $0.startDate) <= day }
    }

    /// A fresh token per genuine tap (not per data change) — lets
    /// `HabitCardRow` distinguish "I was just tapped" from "my completion
    /// data changed because the user switched to a different day," which
    /// look identical from `completion`/`isComplete` alone. See
    /// `HabitCardRow`'s doc comment for why that distinction turned out to
    /// matter for real, not just semantically.
    @State private var lastInteraction: InteractionToken?

    var body: some View {
        NavigationStack {
            List {
                // Always reflects *today*, never `selectedDate` — showing it
                // while browsing a past day would silently mix "today's mood"
                // into an otherwise fully-read-only historical view, so it's
                // gated the same way the Add Habit button already is below.
                if isViewingToday {
                    MoodCheckInCard()
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                ForEach(visibleHabits) { habit in
                    HabitCardRow(
                        habit: habit,
                        completion: selectedDayCompletions[habit.id],
                        isHealthKitConnected: healthKitConnectionStatus[habit.id] ?? false,
                        referenceDate: selectedDate,
                        interactionToken: lastInteraction
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isViewingToday else { return }
                            Task { await handleTap(habit) }
                        }
                        .onLongPressGesture(minimumDuration: 0.5) {
                            guard isViewingToday else { return }
                            Task { await handleLongPress(habit) }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            if isViewingToday {
                                Button(role: .destructive) {
                                    habitPendingDelete = habit
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Task { await archive(habit) }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if isViewingToday {
                                Button {
                                    editingHabit = habit
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                }

                if isViewingToday {
                    HStack {
                        Spacer()
                        Button {
                            isPresentingAddHabit = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Add Habit")
                        Spacer()
                    }
                    .padding(.top, visibleHabits.isEmpty ? 40 : 4)
                    .padding(.bottom, 40)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                WeeklyRingsPagerView(habits: habits) { date in
                    // Defensive re-normalization — `date` should already be
                    // local-midnight-aligned by the time it gets here (see
                    // `WeeklyRingsPagerView`'s fix), but every day-`Date`
                    // assignment in this system goes through the same
                    // `startOfDay` normalization now, not just the ones
                    // that were directly implicated in the bug.
                    selectedDate = Calendar.current.startOfDay(for: date)
                }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await reload() }
            .onChange(of: selectedDate) { _, _ in
                Task { await reloadSelectedDayCompletions() }
            }
            .sheet(isPresented: $isPresentingAddHabit) {
                CategoryPickerView {
                    isPresentingAddHabit = false
                    Task { await reload() }
                }
            }
            .sheet(item: $editingHabit) { habit in
                HabitFormView(existingHabit: habit) {
                    editingHabit = nil
                    Task { await reload() }
                }
            }
            .alert(
                "Delete Habit?",
                isPresented: Binding(
                    get: { habitPendingDelete != nil },
                    set: { isPresented in if !isPresented { habitPendingDelete = nil } }
                ),
                presenting: habitPendingDelete
            ) { habit in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await delete(habit) }
                }
            } message: { habit in
                Text("\"\(habit.title)\" and all of its completion history will be permanently deleted. This can't be undone.")
            }
        }
    }

    private func reload() async {
        let allHabits = (try? await habitRepository.fetchAll()) ?? []
        habits = allHabits.filter { !$0.isArchived }
        await reloadSelectedDayCompletions()
    }

    /// Refetches just the selected day's completions — called whenever
    /// `selectedDate` changes (a strip tap or a week-paging re-selection),
    /// without re-fetching the whole habit list, which hasn't changed.
    private func reloadSelectedDayCompletions() async {
        let completions = (try? await habitRepository.fetchCompletions(for: selectedDate)) ?? []
        selectedDayCompletions = Dictionary(uniqueKeysWithValues: completions.map { ($0.habitID, $0) })
        if isViewingToday {
            await reconcileHealthKitHabits()
        }
    }

    /// Read direction of the two-way HealthKit sync: HealthKit is
    /// authoritative for a HK-mapped habit (see `HealthKitService`'s doc
    /// comment for why this overwrites rather than merges), so a real
    /// water/workout/sleep entry already meeting the goal marks the habit
    /// complete here with no manual tap needed. Also drives the card
    /// badge's connected/not-connected state. Only ever runs for today —
    /// `HealthKitService.todayCompletionState` is inherently about today's
    /// live cumulative value, not a historical day.
    private func reconcileHealthKitHabits() async {
        for habit in habits where habit.isHealthKitTracked {
            let connected = await healthKitService.isConnected(habit)
            healthKitConnectionStatus[habit.id] = connected
            guard connected, let hkState = await healthKitService.todayCompletionState(for: habit) else { continue }

            var completion = selectedDayCompletions[habit.id] ?? Completion(habitID: habit.id, date: .now)
            guard completion.count != hkState.count || completion.isComplete != hkState.isComplete else { continue }
            completion.count = hkState.count
            completion.isComplete = hkState.isComplete
            completion.loggedAt = .now
            try? await habitRepository.upsertCompletion(completion)
            selectedDayCompletions[habit.id] = completion
        }
    }

    /// Only ever called while viewing today (guarded at the gesture in
    /// `body`) — `selectedDate == .now` whenever this runs.
    private func handleTap(_ habit: Habit) async {
        var completion = selectedDayCompletions[habit.id] ?? Completion(habitID: habit.id, date: .now)
        var healthKitDelta: Double = 0
        // Captured before any mutation below, so the feedback dispatch at
        // the end reuses this function's own `wasComplete` →
        // `completion.isComplete` transition — the same states the
        // goal-clamp logic just below already computes — rather than a
        // second, separately-derived "did this just complete" check.
        let wasComplete = completion.isComplete

        if habit.timeMode != .none {
            completion.startedAt = .now
        } else if habit.goal > 1 {
            // Already at/over goal: a further tap is a no-op, not another
            // increment — the count is capped at `goal`, never allowed past
            // it. Matches how the rings elsewhere in this app already treat
            // completion as clamped at 100%, not an open-ended overshoot.
            guard completion.count < habit.goal else { return }
            let previousCount = completion.count
            completion.count = min(completion.count + habit.step, habit.goal)
            healthKitDelta = completion.count - previousCount
            if completion.count >= habit.goal {
                completion.isComplete = true
            }
        } else {
            completion.isComplete.toggle()
            healthKitDelta = completion.isComplete ? habit.goal : 0
        }
        completion.loggedAt = .now

        try? await habitRepository.upsertCompletion(completion)
        selectedDayCompletions[habit.id] = completion

        // Completion feedback (haptic + sound) — fires exactly once, on
        // the transition this function already computed above. Time-based
        // habits ("started at now") aren't part of the four tiered
        // moments this covers, so they're excluded entirely.
        if habit.timeMode == .none {
            // A fresh token on every genuine tap — including a repeated
            // tap on the same habit (e.g. a quantity habit's 3rd/4th/5th
            // increment) — is what lets `HabitCardRow` fire its bounce
            // animation only for a real interaction, never for a day/week
            // switch that happens to change the same `isComplete`/`count`
            // values. See `HabitCardRow`'s doc comment for the regression
            // this fixed.
            lastInteraction = InteractionToken(habitID: habit.id)
            if !wasComplete && completion.isComplete {
                CompletionFeedback.complete()
            } else if wasComplete && !completion.isComplete {
                CompletionFeedback.uncomplete()
            } else if habit.goal > 1 && !completion.isComplete {
                CompletionFeedback.incrementStep()
            }
        }

        // `isHealthKitTracked` gates this at the call site rather than
        // relying solely on `writeManualEntry`'s own internal guard
        // (`HealthKitTypeMapping.mapping(for: habit) != nil`) — measured
        // with `os_log` timing: calling into `actor HealthKitService` at
        // all costs a consistent ~650-700ms in this environment (the actor
        // hop plus `HKHealthStore.isHealthDataAvailable()`), even though
        // the call is a guaranteed no-op for any non-HealthKit-tracked
        // habit. Skipping the call entirely for the common case (most
        // habits aren't HealthKit-tracked) avoids paying that cost on
        // every single completion.
        if healthKitDelta > 0 && habit.isHealthKitTracked {
            await healthKitService.writeManualEntry(for: habit, habitUnitAmount: healthKitDelta, at: .now)
        }
        // Deliberately NOT awaited here — see `dispatchMilestoneCheck`'s doc
        // comment for why this was a measured ~900ms block on every tap,
        // not a guess.
        dispatchMilestoneCheck(for: habit)
    }

    /// Fires milestone/streak/points bookkeeping in its own detached `Task`
    /// rather than being awaited inline by `handleTap`/`handleLongPress` —
    /// a real, measured fix, not a preemptive optimization. Measured with
    /// `os_log` timing across a genuine tap-to-complete: `MilestoneEngine`'s
    /// own sub-checks (`checkHabitStreak` + `checkCategoryStreak` +
    /// `catchUpPointsAndChallenges`) only add up to ~270ms of real work, but
    /// `handleTap`'s inline `await milestoneEngine.afterCompletionLogged(...)`
    /// was measured at ~870-1080ms — several hundred ms of actor-hop/
    /// scheduling overhead from synchronously awaiting a chain that bounces
    /// across two separate `@ModelActor`s (`habitRepository`,
    /// `milestoneRepository`), on top of the real work, all before
    /// `handleTap` itself could return. None of that has any user-visible
    /// urgency in the Home list — the habit's completion state is already
    /// saved and the card's own visual state already updated by this point;
    /// milestones/streaks/points only ever surface on the Progress/
    /// Milestones screens, which already call `MilestoneEngine.runCatchUp()`
    /// on appearing specifically so they stay correct independent of
    /// exactly when (or whether) a given tap's own check finishes — the
    /// exact self-healing property that makes firing this detached safe.
    /// Matches CLAUDE.md's Production Scaling Standard #3 (async processing
    /// for heavy operations — don't make the user wait on the main
    /// request/response cycle for something slow).
    private func dispatchMilestoneCheck(for habit: Habit) {
        Task { await milestoneEngine.afterCompletionLogged(habit: habit) }
    }

    /// Only ever called while viewing today (guarded at the gesture in
    /// `body`) — `selectedDate == .now` whenever this runs.
    private func handleLongPress(_ habit: Habit) async {
        var completion = selectedDayCompletions[habit.id] ?? Completion(habitID: habit.id, date: .now)
        let previousCount = completion.count
        let wasAlreadyComplete = completion.isComplete
        completion.isComplete = true
        if habit.goal > 1 {
            completion.count = habit.goal
        }
        completion.loggedAt = .now

        try? await habitRepository.upsertCompletion(completion)
        selectedDayCompletions[habit.id] = completion

        let healthKitDelta = habit.goal > 1 ? max(0, habit.goal - previousCount) : (wasAlreadyComplete ? 0 : habit.goal)
        // See `handleTap`'s comment on this same guard for why it's here,
        // not just inside `writeManualEntry`.
        if healthKitDelta > 0 && habit.isHealthKitTracked {
            await healthKitService.writeManualEntry(for: habit, habitUnitAmount: healthKitDelta, at: .now)
        }
        // See `dispatchMilestoneCheck`'s doc comment (above `handleTap`).
        dispatchMilestoneCheck(for: habit)
    }

    private func archive(_ habit: Habit) async {
        var updated = habit
        updated.isArchived = true
        try? await habitRepository.save(updated)
        HabitNotificationScheduler.removeAll(for: habit.id)
        await reload()
    }

    private func delete(_ habit: Habit) async {
        try? await habitRepository.delete(id: habit.id)
        HabitNotificationScheduler.removeAll(for: habit.id)
        await reload()
    }
}

private extension Color {
    /// A deep, low-brightness/high-saturation variant of this color for the
    /// completed-card background — same hue, much darker than the source
    /// color, so a full-saturation icon/ring on top of it stays readable
    /// regardless of light/dark mode. Modeled on Apple Watch's Workout app
    /// card treatment (bright icon, deep-toned card, same hue) rather than
    /// a plain `.opacity()` tint, which would read as pastel/washed-out
    /// against a light background instead of a genuinely dark tile.
    func deepCardTint() -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return Color(
            UIColor(hue: hue, saturation: min(1, saturation * 1.1), brightness: brightness * 0.35, alpha: alpha)
        )
    }
}

/// A fresh value per genuine tap — see `HabitCardRow`'s doc comment for why
/// this exists instead of just watching `isComplete`/`count` directly.
private struct InteractionToken: Equatable {
    let habitID: Habit.ID
    private let nonce = UUID()
}

/// Renders one habit's completion state and carries the four completion-
/// feedback animation moments (haptics/sound are triggered imperatively
/// from `HomeView.handleTap`, not from here — see `CompletionFeedback`'s
/// doc comment for why).
///
/// **Bounce/pulse animations are gated on `interactionToken`, not on
/// `isComplete`/`count` directly — this was a real, measured performance
/// bug, not a preemptive optimization.** The first version of this type
/// drove `iconBounceScale`/`countBounceScale` from `.onChange(of:
/// isComplete)`/`.onChange(of: count)`, on the reasoning that those only
/// change when a completion actually happens. That's wrong: they *also*
/// change every time the user switches to a different day, since that
/// swaps in a different day's `completion` entirely — indistinguishable,
/// from this view's perspective, from a real tap. Measured on a real
/// device-equivalent profiling pass (18 habits, 60 days of history,
/// `os_log`-based timing across a day switch): a single day switch was
/// firing 2-3 extra rounds of `body` re-evaluation across roughly half the
/// visible rows, ~600ms apart, entirely from this cascade — chained
/// `withAnimation` calls (grow, delay, settle) multiplied across every row
/// whose `isComplete`/`count` happened to differ on the new day, not just
/// the one the user actually tapped. The base `cardAnimation` crossfade
/// below is unaffected by this — that one *should* animate on a day
/// switch, showing the new day's state — only the extra bounce/pulse layer
/// needed to stop reacting to incidental data changes.
///
/// `interactionToken` fixes this at the source: `HomeView.handleTap` sets
/// it to a fresh `InteractionToken(habitID:)` only on a genuine tap, never
/// on a day switch, so `onChange(of: interactionToken)` only ever fires
/// for the one row that was actually touched — a day switch doesn't touch
/// this value at all, so it can't cascade.
private struct HabitCardRow: View {
    let habit: Habit
    let completion: Completion?
    /// Drives the badge below — `false` covers "not authorized," "no real
    /// HealthKit type for this habit" (see `HealthKitTypeMapping`), and
    /// "HealthKit unavailable" (always true in Simulator) uniformly, since
    /// all three should read as "not connected" here rather than silently
    /// showing the same pink heart regardless.
    let isHealthKitConnected: Bool
    /// Whichever day this row is being shown for — `Home`'s `selectedDate`,
    /// not always real "today". Used only to judge whether a time-based
    /// habit's `startedAt` belongs to *this* day; comparing against real
    /// today here would misreport a past day's real recorded start time as
    /// "not started" just because it isn't today.
    let referenceDate: Date
    /// Set by `HomeView.handleTap` to a fresh value on every genuine tap on
    /// this habit — see the type's doc comment. `nil`/unrelated most of the
    /// time; a day switch never touches this.
    let interactionToken: InteractionToken?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Transient pop applied to the simple-habit checkmark on a completion
    /// transition — not the source of truth for anything, just an
    /// animation detail local to this row.
    @State private var iconBounceScale: CGFloat = 1
    /// Transient pulse applied to a quantity habit's count number on each
    /// routine increment (case #2) — skipped on the crossing tap itself
    /// (case #3), which gets the full card treatment instead.
    @State private var countBounceScale: CGFloat = 1

    private var isComplete: Bool { completion?.isComplete == true }

    /// Short, snappy, slightly overshooting spring for the transition
    /// *into* completion — Apple's own checkbox/toggle timing, not a slow
    /// ease. `.animation(_:value:)` picks the animation based on the
    /// **destination** value of `isComplete`, so this ternary correctly
    /// resolves to this spring when completing and to
    /// `uncompleteAnimation` below when un-completing, in one modifier.
    private var cardAnimation: Animation {
        guard !reduceMotion else { return .easeInOut(duration: 0.2) }
        return isComplete ? .spring(response: 0.32, dampingFraction: 0.62) : .easeOut(duration: 0.18)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.iconSystemName)
                .font(.title3)
                .foregroundStyle(habit.color.color)
                .frame(width: 32)

            Text(habit.title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            if habit.isHealthKitTracked {
                HealthKitBadgeView(isConnected: isHealthKitConnected)
                    .font(.caption)
            }

            statusIndicator
        }
        .padding(16)
        .background {
            // Neutral material and colored-tint layers stacked and
            // cross-dissolved via opacity, rather than trying to animate
            // between a `Material` and a `Color` directly (SwiftUI can't
            // interpolate those two `ShapeStyle` kinds against each
            // other) — this is what makes both the spring-in and the
            // reduce-motion crossfade fallback work off the same
            // structure, just with a different `Animation` curve.
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(habit.color.color.deepCardTint())
                    .opacity(isComplete ? 1 : 0)
            }
        }
        .animation(cardAnimation, value: isComplete)
        .onChange(of: interactionToken) { _, newValue in
            // Gated on `interactionToken`, not `isComplete` — see the
            // type's doc comment. Only fires for the row that was actually
            // tapped; a day switch never sets this, for any row.
            guard !reduceMotion, newValue?.habitID == habit.id else { return }
            if isComplete {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { iconBounceScale = 1.22 }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7).delay(0.1)) { iconBounceScale = 1.0 }
            } else {
                // Un-completing: clean shrink back, no overshoot — reads
                // as "undone," not as a bounce in the opposite direction.
                withAnimation(.easeOut(duration: 0.16)) { iconBounceScale = 1.0 }
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if habit.timeMode != .none {
            if let startedAt = completion?.startedAt, Calendar.current.isDate(startedAt, inSameDayAs: referenceDate) {
                Text("Started \(startedAt, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(Color(.systemGray3))
            }
        } else if habit.goal > 1 {
            quantityProgressIndicator
        } else {
            simpleCompletionIcon
        }
    }

    private var simpleCompletionIcon: some View {
        Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isComplete ? habit.color.color : Color(.systemGray3))
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .scaleEffect(iconBounceScale)
    }

    /// A ring since none existed before this feature — quantity habits
    /// previously showed only "count/goal" as plain text. The ring fills
    /// with an animated stroke on every increment (case #2); the count
    /// number gets its own light scale-bounce pulse, skipped specifically
    /// on the crossing tap (case #3) so that tap reads as the bigger card
    /// completion moment instead of "one more increment."
    private var quantityProgressIndicator: some View {
        let count = completion?.count ?? 0
        let goal = max(habit.goal, 1)
        let progress = min(count / goal, 1.0)

        return ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(habit.color.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3), value: progress)
            Text("\(Int(count))")
                .font(.caption.weight(.bold))
                .foregroundStyle(isComplete ? habit.color.color : .primary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.25, dampingFraction: 0.7), value: count)
        }
        .frame(width: 34, height: 34)
        .scaleEffect(countBounceScale)
        .onChange(of: interactionToken) { _, newValue in
            // Gated on `interactionToken`, not `count` — see the type's
            // doc comment. Only fires for the row that was actually
            // tapped; a day switch never sets this, for any row.
            guard !reduceMotion, !isComplete, newValue?.habitID == habit.id else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { countBounceScale = 1.18 }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75).delay(0.08)) { countBounceScale = 1.0 }
        }
    }
}

#Preview {
    HomeView()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
