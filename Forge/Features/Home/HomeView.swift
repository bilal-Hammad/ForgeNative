import SwiftUI
import UIKit
import os

/// Permanent — surfaces a failed post-optimistic-removal delete rather than
/// swallowing it silently (Production Scaling Standard #8). See
/// `HomeView.dispatchHabitDeletion(_:)`'s doc comment for why the actual
/// repository delete can fail after the row is already gone from the list.
private let habitDeletionLogger = Logger(subsystem: "com.bilalhammad.forge.native", category: "HabitDeletion")

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
/// - Long press → context-aware on the habit's current progress for the
///   day, not a blind force-complete: no progress yet → instantly completes
///   (the original behavior, unchanged, via a custom `LongPressGesture`);
///   partial progress (a quantity habit's `count` above 0 but below goal,
///   or a running timer that hasn't reached goal) → a native
///   `.contextMenu(menuItems:preview:)` — the card lifts with its own real
///   content as the preview (system-rendered Liquid Glass background, no
///   manual material/blur added), offering "Complete" (jump to goal, same
///   as the no-progress case) and a red/destructive "Reset" (zero the day
///   back out — see `resetHabit`); already complete → the same menu with
///   only "Reset". Picking an item is itself the confirmation for Reset —
///   no second "are you sure." (An earlier version of this used
///   `.confirmationDialog` instead of a real context menu — replaced per
///   explicit request to match native iOS's own long-press-menu affordance,
///   e.g. Contacts' "Delete Contact.")
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
    @Environment(\.calendarSyncService) private var calendarSyncService
    @Environment(\.scenePhase) private var scenePhase
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
                    habitRow(for: habit)
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
            .onChange(of: scenePhase) { _, newPhase in
                // Catch-up sweep: a running timer's one-shot completion
                // (`HabitTimerCoordinator.scheduleCompletion`) only fires
                // while this process stays alive — if the app was
                // backgrounded (or killed and relaunched) past the goal
                // time, this is what actually marks it complete, driven
                // purely off persisted `Completion.startedAt`, not
                // anything the coordinator remembers. Same self-healing
                // shape as `MilestoneEngine.runCatchUp()` elsewhere in
                // this app.
                guard newPhase == .active else { return }
                Task {
                    await processPendingTimerStops()
                    await checkTimerCompletions()
                }
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
                    delete(habit)
                }
            } message: { habit in
                Text("\"\(habit.title)\" and all of its completion history will be permanently deleted. This can't be undone.")
            }
        }
    }

    /// Builds one habit's row, including its long-press affordance — split
    /// out of `body` since the affordance itself depends on
    /// `longPressState`, not just a static modifier chain.
    ///
    /// Not viewing today: the plain card, no gesture/menu attached at all —
    /// matches every other interaction on a historical day being withheld
    /// outright (see the type's doc comment), not just guarded inside an
    /// action closure.
    ///
    /// Viewing today, no progress: unchanged from before this feature
    /// existed — a composed `LongPressGesture(...).exclusively(before:
    /// TapGesture())` (see the doc comment where this was introduced, right
    /// above, for why the ordering and the single composed `.gesture(...)`
    /// — not two independent `.onTapGesture`/`.onLongPressGesture`
    /// modifiers — are both load-bearing).
    ///
    /// Viewing today, partial/complete progress: a real `.contextMenu`
    /// instead of that composed gesture — `UIContextMenuInteraction` is its
    /// own separate long-press recognizer from SwiftUI's `Gesture` system,
    /// so it coexists cleanly with a plain `.onTapGesture` for the tap-to-
    /// increment/toggle behavior alongside it (the same pattern Apple's own
    /// apps use for "tap opens, long-press previews/menus" rows — e.g.
    /// Mail, Files). `preview:` reuses `HabitCardRow` itself (its own real
    /// content, `.frame(maxWidth: .infinity)` so it fills the same width as
    /// the list row) rather than a bespoke preview view — the system
    /// supplies the lift/shadow/Liquid Glass chrome automatically.
    @ViewBuilder
    private func habitRow(for habit: Habit) -> some View {
        let card = HabitCardRow(
            habit: habit,
            completion: selectedDayCompletions[habit.id],
            isHealthKitConnected: healthKitConnectionStatus[habit.id] ?? false,
            referenceDate: selectedDate,
            interactionToken: lastInteraction,
            onStopTimer: { Task { await cancelTimer(for: habit) } }
        )
        .contentShape(Rectangle())

        if !isViewingToday {
            card
        } else {
            switch longPressState(for: habit, completion: selectedDayCompletions[habit.id]) {
            case .noProgress:
                card.gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .exclusively(before: TapGesture())
                        .onEnded { result in
                            switch result {
                            case .first:
                                Task { await handleLongPress(habit) }
                            case .second:
                                Task { await handleTap(habit) }
                            }
                        }
                )
            case .partial:
                card
                    .onTapGesture { Task { await handleTap(habit) } }
                    .contextMenu {
                        Button {
                            Task { await handleLongPress(habit) }
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            Task { await resetHabit(habit) }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    } preview: {
                        habitPreview(for: habit)
                    }
            case .complete:
                card
                    .onTapGesture { Task { await handleTap(habit) } }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await resetHabit(habit) }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                    } preview: {
                        habitPreview(for: habit)
                    }
            }
        }
    }

    private func habitPreview(for habit: Habit) -> some View {
        HabitCardRow(
            habit: habit,
            completion: selectedDayCompletions[habit.id],
            isHealthKitConnected: healthKitConnectionStatus[habit.id] ?? false,
            referenceDate: selectedDate,
            interactionToken: nil,
            // A context-menu preview is a static snapshot, not a live
            // interactive view — no real tap ever reaches this closure.
            onStopTimer: {}
        )
        .frame(maxWidth: .infinity)
    }

    private func reload() async {
        let allHabits = (try? await habitRepository.fetchAll()) ?? []
        habits = allHabits.filter { !$0.isArchived }
        await reloadSelectedDayCompletions()
        await processPendingTimerStops()
        if isViewingToday {
            await checkTimerCompletions()
        }
        dispatchDailyReminderCatchUp()
    }

    /// Nothing in this app runs a scheduled background job, so a Reminders-
    /// synced habit's *today* occurrence(s) only ever get created at the
    /// moment `CalendarSyncService.sync(habit:)` actually runs — see that
    /// protocol's doc comment. Every app open is a reasonable proxy for
    /// "today may not have its reminder(s) yet," so this re-syncs every
    /// active habit here, same fire-and-forget shape as
    /// `dispatchMilestoneCheck` (each call is a fast, idempotent no-op for
    /// any habit that isn't actually sync-enabled, or whose reminders
    /// already exist for today — never awaited inline since it shouldn't
    /// delay the list rendering).
    private func dispatchDailyReminderCatchUp() {
        let habitsSnapshot = habits
        Task {
            for habit in habitsSnapshot {
                await calendarSyncService.sync(habit: habit)
            }
        }
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
            guard connected, let hkState = await healthKitService.todayCompletionState(for: habit) else {
                continue
            }

            var completion = selectedDayCompletions[habit.id] ?? Completion(habitID: habit.id, date: .now)
            guard completion.count != hkState.count || completion.isComplete != hkState.isComplete else {
                continue
            }
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
        // Time-unit habits (minutes/hours goal) replace tap-to-increment
        // entirely with the native timer — checked first, ahead of both
        // `timeMode` and the quantity branch below, since a duration goal
        // has no coherent "increment by step" or "started at" meaning of
        // its own. Gated purely on `habit.unit`, not on template/name.
        if habit.unit.isTimeBased {
            await handleTimerTap(habit)
            return
        }

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
            let newUUIDs = await healthKitService.writeManualEntry(for: habit, habitUnitAmount: healthKitDelta, at: .now)
            if !newUUIDs.isEmpty {
                completion.healthKitSampleUUIDs.append(contentsOf: newUUIDs)
                try? await habitRepository.upsertCompletion(completion)
                selectedDayCompletions[habit.id] = completion
            }
        }
        // Deliberately NOT awaited here — see `dispatchMilestoneCheck`'s doc
        // comment for why this was a measured ~900ms block on every tap,
        // not a guess.
        dispatchMilestoneCheck(for: habit)
        dispatchReminderCompletionMirror(for: habit)
    }

    private func durationSeconds(for habit: Habit) -> TimeInterval {
        habit.goal * habit.unit.secondsPerUnit
    }

    /// Tap on a time-unit habit: starts the timer if idle, cancels it if
    /// already running (a plain second tap as the escape hatch — no
    /// separate cancel UI), no-ops if already complete for today (matches
    /// how a further tap on an at-goal quantity habit is already a no-op
    /// just above, in `handleTap`). **Judgment call**: cancelling clears
    /// `startedAt` rather than, say, pausing/resuming — this feature has no
    /// pause concept, only start/cancel/instant-complete (long press).
    private func handleTimerTap(_ habit: Habit) async {
        let completion = selectedDayCompletions[habit.id]
        guard completion?.isComplete != true else { return }
        if completion?.startedAt != nil {
            await cancelTimer(for: habit)
        } else {
            await startTimer(for: habit)
        }
    }

    private func startTimer(for habit: Habit) async {
        var completion = selectedDayCompletions[habit.id] ?? Completion(habitID: habit.id, date: .now)
        let start = Date.now
        completion.startedAt = start
        completion.loggedAt = start
        try? await habitRepository.upsertCompletion(completion)
        selectedDayCompletions[habit.id] = completion

        let end = start.addingTimeInterval(durationSeconds(for: habit))
        HabitTimerCoordinator.shared.startLiveActivity(
            habitID: habit.id,
            title: habit.title,
            iconSystemName: habit.iconSystemName,
            color: habit.color,
            start: start,
            end: end
        )
        // See `HabitTimerCoordinator.scheduleCompletion`'s doc comment —
        // this is what makes completion feel instant while the app stays
        // foregrounded; `checkTimerCompletions` (below) is what actually
        // guarantees correctness if it doesn't get the chance to fire.
        HabitTimerCoordinator.shared.scheduleCompletion(habitID: habit.id, at: end) {
            await completeTimerHabit(habitID: habit.id)
        }
    }

    private func cancelTimer(for habit: Habit) async {
        guard var completion = selectedDayCompletions[habit.id], completion.startedAt != nil else { return }
        completion.startedAt = nil
        completion.loggedAt = .now
        try? await habitRepository.upsertCompletion(completion)
        selectedDayCompletions[habit.id] = completion
        HabitTimerCoordinator.shared.endLiveActivity(habitID: habit.id, completed: false)
    }

    /// Fires once a time-unit habit's timer genuinely reaches its goal —
    /// called both from the one-shot scheduled completion (app stayed
    /// foregrounded) and from `checkTimerCompletions`' catch-up sweep (app
    /// was backgrounded/killed past the goal). Looks the habit up fresh by
    /// ID rather than trusting a captured `Habit` value, since this can run
    /// long after the tap that scheduled it.
    private func completeTimerHabit(habitID: Habit.ID) async {
        guard let habit = habits.first(where: { $0.id == habitID }) else { return }
        guard var completion = selectedDayCompletions[habitID],
              let startedAt = completion.startedAt,
              !completion.isComplete else { return }

        // Logged as the real elapsed time, not a hardcoded `habit.goal` —
        // per explicit instruction to "log the actual elapsed duration."
        // This is normally ~equal to the goal (the one-shot fires right at
        // the end instant), but can genuinely exceed it when this runs from
        // the catch-up sweep instead, after the app was away for a while.
        let elapsedSeconds = Date.now.timeIntervalSince(startedAt)
        let elapsedInHabitUnit = elapsedSeconds / habit.unit.secondsPerUnit
        completion.count = elapsedInHabitUnit
        completion.isComplete = true
        completion.loggedAt = .now
        try? await habitRepository.upsertCompletion(completion)
        selectedDayCompletions[habitID] = completion

        lastInteraction = InteractionToken(habitID: habitID)
        CompletionFeedback.complete()

        // See `handleTap`'s comment on this same guard for why it's here,
        // not just inside `writeManualEntry`.
        if habit.isHealthKitTracked {
            let newUUIDs = await healthKitService.writeManualEntry(for: habit, habitUnitAmount: elapsedInHabitUnit, at: .now)
            if !newUUIDs.isEmpty {
                completion.healthKitSampleUUIDs.append(contentsOf: newUUIDs)
                try? await habitRepository.upsertCompletion(completion)
                selectedDayCompletions[habitID] = completion
            }
        }
        dispatchMilestoneCheck(for: habit)
        dispatchReminderCompletionMirror(for: habit)
        HabitTimerCoordinator.shared.endLiveActivity(habitID: habitID, completed: true)
    }

    /// Processes any pending "stop this timer" signals left by
    /// `StopTimerIntent` — the Live Activity's interactive Stop button,
    /// which runs entirely in the `ForgeWidgets` extension process and
    /// never launches this app. The Live Activity itself already ended the
    /// instant the user tapped it; this just catches up the *persisted*
    /// `Completion.startedAt` next time the app is opened, same
    /// self-healing shape as `checkTimerCompletions()` right below (called
    /// on cold launch via `reload()`, and on every foreground via the
    /// `scenePhase` handling in `body`).
    ///
    /// Resolves against real `.now`, never `selectedDate` — a running
    /// timer only ever exists for today, and this can run while the user
    /// happens to be viewing a different day.
    private func processPendingTimerStops() async {
        let pendingHabitIDs = SharedTimerStopSignal.drainPendingStops()
        guard !pendingHabitIDs.isEmpty else { return }
        let todaysCompletions = (try? await habitRepository.fetchCompletions(for: .now)) ?? []
        var completionsByHabit = Dictionary(uniqueKeysWithValues: todaysCompletions.map { ($0.habitID, $0) })
        for habitID in pendingHabitIDs {
            guard var completion = completionsByHabit[habitID], completion.startedAt != nil else { continue }
            completion.startedAt = nil
            completion.loggedAt = .now
            try? await habitRepository.upsertCompletion(completion)
            completionsByHabit[habitID] = completion
            if isViewingToday {
                selectedDayCompletions[habitID] = completion
            }
            HabitTimerCoordinator.shared.endLiveActivity(habitID: habitID, completed: false)
        }
    }

    /// Catch-up sweep for time-unit habits whose goal time has already
    /// passed without the in-process one-shot completion having fired —
    /// called on initial load and every time the app returns to the
    /// foreground (see `scenePhase` handling in `body`). Purely derived
    /// from persisted `Completion.startedAt`, so this is correct even after
    /// a full app relaunch, not just a background/foreground cycle.
    private func checkTimerCompletions() async {
        let now = Date.now
        for habit in visibleHabits where habit.unit.isTimeBased {
            guard let completion = selectedDayCompletions[habit.id],
                  let startedAt = completion.startedAt,
                  !completion.isComplete else { continue }
            if now >= startedAt.addingTimeInterval(durationSeconds(for: habit)) {
                await completeTimerHabit(habitID: habit.id)
            }
        }
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

    /// Pushes today's completion state to the habit's Reminders sync, if
    /// active — fired from the same 4 sites `dispatchMilestoneCheck` is,
    /// right after `selectedDayCompletions[habit.id]` is updated, so it
    /// always reads the just-settled final state for this tap. Deliberately
    /// not awaited inline for the same reason `dispatchMilestoneCheck`
    /// isn't — `CalendarSyncService.mirrorCompletion` ultimately hits
    /// `EKEventStore`, which has no async save/remove API of its own and
    /// would otherwise block this actor hop synchronously; nothing on
    /// screen needs to wait for it (the card's own visual state is already
    /// correct by this point, same as the milestone case above).
    private func dispatchReminderCompletionMirror(for habit: Habit) {
        guard let completion = selectedDayCompletions[habit.id] else { return }
        Task { await calendarSyncService.mirrorCompletion(habit: habit, completion: completion) }
    }

    /// Three states a habit's selected-day progress can be in, driving
    /// which long-press affordance `habitRow(for:)` attaches.
    private enum LongPressState {
        /// Count is 0 (or, for a timer habit, never started) — long-press
        /// instantly completes, no menu, exactly the original behavior.
        case noProgress
        /// A quantity habit's `count` is above 0 but below goal, or a
        /// timer habit's `startedAt` is set but goal isn't reached yet.
        case partial
        case complete
    }

    private func longPressState(for habit: Habit, completion: Completion?) -> LongPressState {
        guard let completion else { return .noProgress }
        if completion.isComplete { return .complete }
        if habit.unit.isTimeBased {
            return completion.startedAt != nil ? .partial : .noProgress
        }
        if habit.goal > 1 {
            return completion.count > 0 ? .partial : .noProgress
        }
        return .noProgress
    }

    /// Instant force-complete — the "no progress" long-press case, and the
    /// context menu's "Complete" item for a partial-progress habit.
    /// Unchanged from this feature's original single behavior.
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

        // A running timer (if any) is superseded by this instant force-
        // complete — end its Live Activity/scheduled completion rather
        // than leaving a phantom countdown running for an already-done
        // habit. `endLiveActivity` itself is a no-op if none is active.
        if habit.unit.isTimeBased {
            HabitTimerCoordinator.shared.endLiveActivity(habitID: habit.id, completed: true)
        }

        let healthKitDelta = habit.goal > 1 ? max(0, habit.goal - previousCount) : (wasAlreadyComplete ? 0 : habit.goal)
        // See `handleTap`'s comment on this same guard for why it's here,
        // not just inside `writeManualEntry`.
        if healthKitDelta > 0 && habit.isHealthKitTracked {
            let newUUIDs = await healthKitService.writeManualEntry(for: habit, habitUnitAmount: healthKitDelta, at: .now)
            if !newUUIDs.isEmpty {
                completion.healthKitSampleUUIDs.append(contentsOf: newUUIDs)
                try? await habitRepository.upsertCompletion(completion)
                selectedDayCompletions[habit.id] = completion
            }
        }
        // See `dispatchMilestoneCheck`'s doc comment (above `handleTap`).
        dispatchMilestoneCheck(for: habit)
        dispatchReminderCompletionMirror(for: habit)
    }

    /// Zeros the selected day's progress back out, cascading through every
    /// system that reads from it — not just the visible count/timer.
    /// Reachable only from the long-press context menu's "Reset" item
    /// (partial or already-complete progress; see `habitRow(for:)`).
    ///
    /// **What this does and doesn't touch, explicitly**:
    /// - The completion record itself: `count`/`startedAt` back to their
    ///   zero values, `isComplete` back to `false`, persisted through the
    ///   same repository every other mutation in this file uses.
    /// - Streaks: nothing to do here — `StreakMath` is pure, always
    ///   recomputed fresh from real completions wherever it's read
    ///   (`HabitDetailView`, `MilestoneEngine`, Progress's streak card), so
    ///   persisting the reset above is already the whole fix. Confirmed by
    ///   reading `StreakMath.swift`: it takes `completedDates` as an input,
    ///   there's no separately-cached streak number anywhere to go stale.
    /// - Points: nothing to do here either, and deliberately so — read
    ///   `MilestoneEngine.catchUpPoints()`'s own loop bound
    ///   (`while day <= yesterday`): *today* is never evaluated into
    ///   `PointsLedger.cumulativePoints` until tomorrow's catch-up looks
    ///   back at today's *final* state, whatever that ends up being. A
    ///   same-day reset can't create orphaned points because today's
    ///   points were never awarded in the first place — verified by
    ///   reading the ledger code, not assumed.
    /// - Milestones: `dispatchMilestoneCheck` below re-runs
    ///   `checkHabitStreak`/`checkCategoryStreak`, which now also revoke
    ///   any previously-awarded streak badge the reset just invalidated
    ///   (see `MilestoneEngine.revokeInvalidStreakMilestones`). Category
    ///   challenges don't need this: like points, they only ever evaluate
    ///   a *fully-elapsed* past month, never today.
    /// - Progress page: reads fresh on every tab appearance now (see
    ///   `ProgressScreenView`'s `.onAppear`, changed from `.task` — a
    ///   `TabView`'s tabs stay resident in memory, so a parameterless
    ///   `.task` only ever ran once per app launch, not once per visit).
    /// - HealthKit: deletes exactly the samples *Forge itself* wrote for
    ///   this completion (tracked via `healthKitSampleUUIDs`) — never any
    ///   other sample of the same type. See `HealthKitService
    ///   .deleteSamples`'s doc comment for why this is safe, and its own
    ///   real limitation: a completion whose `healthKitSampleUUIDs` is
    ///   empty (e.g. one driven entirely by real external Health data, or
    ///   one from before this field existed) has nothing to retract — the
    ///   local display still resets, but if HealthKit still genuinely has
    ///   that data, the next reconcile (`reconcileHealthKitHabits`, which
    ///   treats HealthKit as authoritative) will correctly re-sync the
    ///   habit back to complete. That's not a bug: Forge deleting real,
    ///   non-Forge-written Health data would be actively wrong.
    private func resetHabit(_ habit: Habit) async {
        guard var completion = selectedDayCompletions[habit.id] else { return }
        let uuidsToDelete = completion.healthKitSampleUUIDs

        completion.count = 0
        completion.isComplete = false
        completion.startedAt = nil
        completion.healthKitSampleUUIDs = []
        completion.loggedAt = .now
        try? await habitRepository.upsertCompletion(completion)
        selectedDayCompletions[habit.id] = completion

        if habit.unit.isTimeBased {
            HabitTimerCoordinator.shared.endLiveActivity(habitID: habit.id, completed: false)
        }

        if habit.isHealthKitTracked && !uuidsToDelete.isEmpty {
            await healthKitService.deleteSamples(for: habit, uuids: uuidsToDelete)
        }

        // Drives the same "un-completing" shrink-back animation a toggled-
        // off simple habit already gets — see `HabitCardRow`'s doc comment.
        lastInteraction = InteractionToken(habitID: habit.id)
        CompletionFeedback.uncomplete()
        dispatchMilestoneCheck(for: habit)
        dispatchReminderCompletionMirror(for: habit)
    }

    private func archive(_ habit: Habit) async {
        var updated = habit
        updated.isArchived = true
        try? await habitRepository.save(updated)
        HabitNotificationScheduler.removeAll(for: habit.id)
        if habit.unit.isTimeBased {
            HabitTimerCoordinator.shared.endLiveActivity(habitID: habit.id, completed: false)
        }
        await reload()
    }

    /// Optimistic removal: the row leaves `habits`/`selectedDayCompletions`
    /// immediately, animated, before any backend work starts. Measured (real
    /// numbers, Simulator warm run — see RESULTS.md): with everything
    /// awaited inline as this used to be, `removeSync` and
    /// `reconcileHealthKitHabits` — this investigation's original two
    /// suspects — were both cheap (single-digit ms), but the repository
    /// delete itself (~136ms) and notification/Live Activity cleanup
    /// (~84ms) were not, and stacked with `reload()`'s own cost (~74ms)
    /// they added up to a real, avoidable ~300ms of dead time even on
    /// Simulator — before accounting for the real device, which this
    /// project's own prior investigations (CLAUDE.md's "MainActor
    /// continuation-resumption latency" findings) have repeatedly measured
    /// as materially slower than Simulator for this exact class of
    /// actor-hop. Rather than pick a single "dominant" call to dispatch,
    /// none of this backend work has any user-visible urgency at deletion
    /// time — the row is already gone — so all of it moves off the
    /// critical path together.
    private func delete(_ habit: Habit) {
        withAnimation {
            habits.removeAll { $0.id == habit.id }
            selectedDayCompletions.removeValue(forKey: habit.id)
            healthKitConnectionStatus.removeValue(forKey: habit.id)
        }
        HabitNotificationScheduler.removeAll(for: habit.id)
        if habit.unit.isTimeBased {
            HabitTimerCoordinator.shared.endLiveActivity(habitID: habit.id, completed: false)
        }
        dispatchHabitDeletion(habit)
    }

    /// Deliberately not awaited inline — see `delete(_:)`'s doc comment
    /// above, and `dispatchMilestoneCheck`'s doc comment for the same
    /// established shape elsewhere in this file. This plain `Task { }`
    /// (not a view-lifecycle-bound `.task { }`) keeps running independent
    /// of `HomeView`'s own lifecycle, so it isn't silently dropped if the
    /// view disappears mid-cleanup (Production Scaling Standard #8). The
    /// repository delete's failure is explicitly logged rather than
    /// swallowed, since silently losing it would leave the row
    /// optimistically gone from the UI while the underlying data survives —
    /// reappearing, unexplained, on the next `reload()`. `removeSync`
    /// itself isn't throwing (`CalendarSyncService`'s protocol signature,
    /// unchanged by this fix) — an orphaned `EKEvent`/`EKReminder` from a
    /// failed internal remove isn't newly introduced by dispatching this
    /// off the critical path, and reworking that protocol to surface its
    /// own internal errors is out of scope here.
    private func dispatchHabitDeletion(_ habit: Habit) {
        Task {
            // Before the repository delete — the habit's own
            // `calendarEventIdentifier`/`reminderIdentifiers` are what
            // `removeSync` needs to find and remove the right
            // EKEvent/EKReminder(s); they're unrecoverable once the habit
            // record itself is gone.
            await calendarSyncService.removeSync(for: habit)
            do {
                try await habitRepository.delete(id: habit.id)
            } catch {
                habitDeletionLogger.error("Failed to delete habit \(habit.id, privacy: .public) (\(habit.title, privacy: .public)): \(error, privacy: .public)")
            }
            await reload()
        }
    }
}

private extension Color {
    /// The completed-card background tint, same hue as the source color but
    /// a different shade per color scheme (APP_REDESIGN_SPEC.md §16's
    /// "Color derivation formula"), so a full-saturation icon/ring on top
    /// stays readable in both.
    ///
    /// - Dark mode: a deep, low-brightness/high-saturation variant — modeled
    ///   on Apple Watch's Workout app card treatment (bright icon, deep-toned
    ///   card, same hue) rather than a plain `.opacity()` tint, which would
    ///   read as pastel/washed-out against a light background instead of a
    ///   genuinely dark tile.
    /// - Light mode: the inverse relationship the spec calls for — heavily
    ///   lightened *and* desaturated (~90–95% brightness, saturation cut to
    ///   roughly a quarter), a pale tint rather than a deep one, since
    ///   light-mode cards read as light surfaces by convention. Previously
    ///   this used the same deep-tint formula in both modes; that read as a
    ///   near-black tile in light mode instead of a light surface.
    func deepCardTint(for colorScheme: ColorScheme) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        switch colorScheme {
        case .light:
            return Color(
                UIColor(hue: hue, saturation: saturation * 0.25, brightness: 0.94, alpha: alpha)
            )
        case .dark:
            fallthrough
        @unknown default:
            return Color(
                UIColor(hue: hue, saturation: min(1, saturation * 1.1), brightness: brightness * 0.35, alpha: alpha)
            )
        }
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
    /// Invoked by the visible Stop button in `timerStatusIndicator`'s
    /// running case — calls `HomeView.cancelTimer(for:)`, the exact same
    /// logic a second tap on the row already triggered before this button
    /// existed. That tap-again convention still works too (this button
    /// doesn't replace it, just gives it a real visual affordance) — see
    /// this property's use site for why a nested `Button` and the row's own
    /// `.onTapGesture` don't conflict.
    let onStopTimer: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Transient pop applied to the simple-habit checkmark on a completion
    /// transition — not the source of truth for anything, just an
    /// animation detail local to this row.
    @State private var iconBounceScale: CGFloat = 1
    /// Transient pulse applied to a quantity habit's count number on each
    /// routine increment (case #2) — skipped on the crossing tap itself
    /// (case #3), which gets the full card treatment instead.
    @State private var countBounceScale: CGFloat = 1

    private var isComplete: Bool { completion?.isComplete == true }

    /// Plain integer under 1000 (the overwhelming majority of quantity
    /// habits — a step count, a glass count, a rep count); compact notation
    /// ("11.2K") above that, so a real HealthKit-linked habit with a large
    /// real count (Steps can easily be 4+ digits) never truncates inside
    /// the fixed-width ring — the number must never truncate, per this
    /// feature's own requirement, and a fixed-size ring has no room to grow
    /// to fit an arbitrarily long integer the way inline text could.
    private static func formattedQuantityCount(_ count: Double) -> String {
        guard count >= 1000 else { return "\(Int(count))" }
        return count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

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
                    .fill(habit.color.color.deepCardTint(for: colorScheme))
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
        if habit.unit.isTimeBased {
            timerStatusIndicator
        } else if habit.timeMode != .none {
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

    /// Three states for a time-unit habit, gated purely on `habit.unit`
    /// (see `HomeView.handleTap`) — idle (never tapped today), running
    /// (a live native countdown, see `HabitTimerRingView`), and complete
    /// (reuses the same checkmark every simple habit uses once done — a
    /// time-unit habit is still a once-a-day completion at heart, just
    /// reached via a timer instead of a tap).
    @ViewBuilder
    private var timerStatusIndicator: some View {
        if isComplete {
            simpleCompletionIcon
                .accessibilityIdentifier("timerStatus.complete")
        } else if let startedAt = completion?.startedAt {
            // A visible Stop control — previously, cancelling a running
            // timer relied entirely on the invisible "tap the row again"
            // convention, with no on-screen affordance hinting it exists.
            // `Button` is a real nested interactive control here, not a
            // second competing `Gesture` recognizer on the same view (the
            // ambiguous-gesture bug this project hit and fixed elsewhere in
            // this file was specifically about two independent `Gesture`-
            // protocol modifiers on one view; a `Button`'s own built-in hit
            // testing is a different, well-defined mechanism that already
            // reliably coexists with an ancestor's `.onTapGesture`
            // elsewhere in this app, e.g. `List` swipe-action buttons) —
            // but this is still verified with a real XCUITest, not just
            // assumed correct from that reasoning, matching this project's
            // own standing bar for gesture/interaction work.
            //
            // A real, empirically-found finding worth keeping in mind for
            // future work in this file: `.accessibilityIdentifier` applied
            // to a *wrapping* `HStack` here was found (via a failing
            // XCUITest and its captured accessibility-hierarchy dump, not
            // guessed) to cascade down and overwrite each child's own
            // individually-set identifier — the Button ended up exposed
            // with identifier `timerStatus.running` (the parent's) instead
            // of `timerStatus.stopButton` (its own), making it
            // unfindable by the identifier this code actually sets on it.
            // Fixed by putting the identifier on `HabitTimerRingView`
            // directly (matching exactly where it lived before this
            // feature added the wrapping HStack) rather than on the
            // container — each element now keeps its own distinct
            // identifier, no propagation.
            HStack(spacing: 8) {
                Button {
                    onStopTimer()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop Timer")
                .accessibilityIdentifier("timerStatus.stopButton")

                HabitTimerRingView(
                    start: startedAt,
                    end: startedAt.addingTimeInterval(habit.goal * habit.unit.secondsPerUnit),
                    tint: habit.color.color
                )
                .accessibilityIdentifier("timerStatus.running")
            }
        } else {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(Color(.systemGray3))
                .accessibilityIdentifier("timerStatus.idle")
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
    ///
    /// Sizing/text treatment (frame, stroke width, font size/weight,
    /// monospaced digits, `minimumScaleFactor` as a safety net rather than
    /// the primary strategy) is deliberately identical to
    /// `HabitTimerRingView`'s — real device screenshots previously showed
    /// this ring's number truncating (e.g. "Steps") at the old 34×34/
    /// `.caption` sizing, and the timer ring's own text shrinking as far as
    /// 4.5pt to fit its old 9pt-base/36pt-wide box. Both are now the same
    /// design language at the same size, not just coincidentally matching
    /// dimensions.
    private var quantityProgressIndicator: some View {
        let count = completion?.count ?? 0
        let goal = max(habit.goal, 1)
        let progress = min(count / goal, 1.0)

        return ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(habit.color.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3), value: progress)
            Text(Self.formattedQuantityCount(count))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .frame(width: 38)
                .foregroundStyle(isComplete ? habit.color.color : .primary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.25, dampingFraction: 0.7), value: count)
        }
        .frame(width: 44, height: 44)
        .scaleEffect(countBounceScale)
        // Test seam for `ResetHabitTests` (and any future quantity-habit
        // test) — reads the exact count/goal without needing to parse
        // pixel-level ring progress.
        .accessibilityIdentifier("quantityProgress")
        .accessibilityLabel("\(Int(count)) of \(Int(goal))")
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
