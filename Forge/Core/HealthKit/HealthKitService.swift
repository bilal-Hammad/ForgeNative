import Foundation
@preconcurrency import HealthKit

/// The only place that talks to `HKHealthStore` — authorization, reading
/// today's real value for a HealthKit-tracked habit, writing a manual
/// tap/long-press back to Health, and registering background delivery so
/// completions update even when Forge isn't open. Constructed once in
/// `ForgeApp` (same pattern as the repositories) and reached via
/// `@Environment(\.healthKitService)`.
///
/// **HealthKit is authoritative for HK-mapped habits.** A habit's local
/// `Completion.count` for one of these habits isn't an independently
/// accumulated counter that then needs "merging" with HealthKit's own
/// total — it's a cache of the last-read HealthKit total. Reconciling
/// always *overwrites* the local count with HealthKit's real cumulative
/// value rather than taking a max/min against it. This matters specifically
/// for a "Bad"/limit habit like "Limit Coffee": if the app tried to combine
/// its own locally-tracked count with HealthKit's separately-read total,
/// the app's own manual write (which HealthKit's next read already
/// includes) would double-count. Treating HealthKit as the single source
/// of truth avoids that entirely — manual taps still feel instant because
/// `HomeView` applies an optimistic local bump immediately after writing,
/// and the next reconcile (screen reload or a background observer firing)
/// self-corrects to HealthKit's real number regardless.
///
/// **Real HealthKit constraints that shaped this, not worked around:**
/// - `HKHealthStore.isHealthDataAvailable()` — every entry point here
///   checks this first and no-ops otherwise, so the app doesn't crash/hang
///   anywhere it's `false`. This was long believed to be *always* false in
///   Simulator (a real, historical HealthKit limitation) — re-verified
///   empirically this pass (a temporary logged check at app launch, not
///   assumed) and that's **no longer true**: it returns `true` on this
///   project's current Simulator runtime (iOS 26.5), which is what makes
///   the real read/write/background-delivery verification in this pass's
///   commit possible at all without a physical device. iPad remains a real
///   `false` case regardless of Simulator-vs-device — Apple's stated
///   platform restriction, confirmed by this same flag, not a special case
///   coded around.
/// - Apple deliberately does not expose *read* authorization status, to
///   stop apps from inferring sensitive health facts from a denial —
///   `authorizationStatus(for:)` only ever reflects **share (write)**
///   permission. The "not connected" indicator this feature shows is
///   therefore driven by write status plus `isHealthDataAvailable()`; if a
///   user grants write but denies read (or vice versa), the UI can't fully
///   distinguish that — an Apple platform limitation, not a gap in this
///   code.
actor HealthKitService {
    private let healthStore = HKHealthStore()
    private let habitRepository: HabitRepository
    private let milestoneEngine: MilestoneEngine

    init(habitRepository: HabitRepository, milestoneEngine: MilestoneEngine) {
        self.habitRepository = habitRepository
        self.milestoneEngine = milestoneEngine
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Authorization

    /// Requests read (+ write, only if this mapping actually writes)
    /// authorization for exactly the one HealthKit type this habit needs —
    /// called once, at the moment a HealthKit-tracked habit is first
    /// created (see `HabitFormView`), not proactively on launch.
    ///
    /// **`toShare` only ever includes the type when `supportsWriteBack` is
    /// true — a real crash this pass found empirically, not a
    /// theoretical concern**: requesting *share* authorization for an
    /// `HKCorrelationType` (Blood Pressure's mapping) is flatly disallowed
    /// by HealthKit — Apple's own documented rule, since a correlation is a
    /// composite built from its constituent quantity samples, not an
    /// independently shareable object — and asking for it anyway doesn't
    /// error gracefully, it crashes the process outright
    /// (`NSInvalidArgumentException: Authorization to share the following
    /// types is disallowed: HKCorrelationTypeIdentifierBloodPressure`,
    /// caught live during this pass's Simulator verification). Every
    /// read-only mapping already has `supportsWriteBack: false` for its own
    /// separate reasons (see `HealthKitTypeMapping`'s doc comment), so
    /// gating `toShare` on that same flag fixes this correctly for free —
    /// read access (needed for every mapping, writable or not) is
    /// unaffected.
    @discardableResult
    func requestAuthorization(for habit: Habit) async -> Bool {
        guard Self.isAvailable, let mapping = HealthKitTypeMapping.mapping(for: habit) else { return false }
        let shareTypes: Set<HKSampleType> = mapping.supportsWriteBack ? [mapping.sampleType] : []
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: [mapping.sampleType])
            return true
        } catch {
            return false
        }
    }

    /// Write (share) authorization only — see the type's doc comment for
    /// why read status can't be introspected the same way. `.notDetermined`
    /// covers "not HealthKit-available," "not HealthKit-tracked," and
    /// "genuinely never asked" uniformly, since all three should render the
    /// same "not connected yet" way in the UI.
    func writeAuthorizationStatus(for habit: Habit) -> HKAuthorizationStatus {
        guard Self.isAvailable, let mapping = HealthKitTypeMapping.mapping(for: habit) else { return .notDetermined }
        return healthStore.authorizationStatus(for: mapping.sampleType)
    }

    /// Convenience for badge/UI state: true only once write access is
    /// actually granted for a habit that really does map to a HealthKit
    /// type.
    func isConnected(_ habit: Habit) -> Bool {
        guard habit.isHealthKitTracked, HealthKitTypeMapping.mapping(for: habit) != nil else { return false }
        return writeAuthorizationStatus(for: habit) == .sharingAuthorized
    }

    // MARK: - Read

    /// Today's real HealthKit-derived value for this habit, and whether it
    /// already satisfies the habit's goal (respecting Bad-habit "limit"
    /// semantics, or `.discreteCount`'s "count of samples, not a summed
    /// magnitude" semantics) — `nil` if HealthKit isn't available, the
    /// habit has no resolvable mapping, or the query itself fails.
    func todayCompletionState(for habit: Habit) async -> (count: Double, isComplete: Bool)? {
        guard Self.isAvailable, let mapping = HealthKitTypeMapping.mapping(for: habit) else { return nil }

        let calendar = Calendar.current
        let now = Date.now
        let startOfDay = calendar.startOfDay(for: now)

        // `.discreteCount` (vitals/reproductive-health/handwashing reads)
        // counts samples directly, generically across every `Kind`, rather
        // than going through the per-kind cumulative-sum logic below.
        if mapping.rule == .discreteCount {
            let count = await sampleCount(
                type: mapping.sampleType,
                start: startOfDay,
                end: now,
                categoryValueFilter: mapping.categoryValueFilter
            )
            let habitValue = Double(count)
            return (habitValue, habitValue >= habit.goal)
        }

        let rawHKValue: Double
        switch mapping.kind {
        case .quantity(let identifier):
            rawHKValue = await cumulativeQuantitySum(type: HKQuantityType(identifier), unit: mapping.hkUnit, start: startOfDay, end: now)
        case .category(let identifier) where identifier == .sleepAnalysis:
            // "Today's sleep" means last night's, which can start well
            // before midnight — a trailing 24h window is a simpler, honest
            // stand-in for a precise "last night" boundary.
            guard let dayAgo = calendar.date(byAdding: .hour, value: -24, to: now) else { return nil }
            let samples = await categorySamples(type: HKCategoryType(identifier), start: dayAgo, end: now)
            let asleepSeconds = samples
                .filter { HKCategoryValueSleepAnalysis(rawValue: $0.value)?.isAsleep ?? false }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            rawHKValue = durationValue(seconds: asleepSeconds, in: mapping.hkUnit)
        case .category(let identifier):
            let samples = await categorySamples(type: HKCategoryType(identifier), start: startOfDay, end: now)
            let totalSeconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            rawHKValue = durationValue(seconds: totalSeconds, in: mapping.hkUnit)
        case .workout(let activityType):
            let workouts = await workoutSamples(activityType: activityType, start: startOfDay, end: now)
            let totalSeconds = workouts.reduce(0.0) { $0 + $1.duration }
            rawHKValue = durationValue(seconds: totalSeconds, in: mapping.hkUnit)
        }

        let habitValue = rawHKValue * mapping.habitUnitsPerHKUnit
        let isComplete = mapping.rule == .cumulativeLimit ? habitValue <= habit.goal : habitValue >= habit.goal
        return (habitValue, isComplete)
    }

    // MARK: - Write

    /// Writes a manual tap/long-press back to Health. `habitUnitAmount` is
    /// the delta the app just applied locally (a Stepper's `step` for a
    /// quantity habit, or the remaining amount to reach `goal` for a
    /// long-press force-complete) — not the running total, since HealthKit
    /// quantity/category/workout samples are discrete entries that
    /// `todayCompletionState` sums, not a single mutable counter.
    ///
    /// Returns every `HKSample.uuid` this call actually wrote (usually one;
    /// the `.discreteCount` branch can write several) — `HKObject.uuid` is
    /// generated client-side at construction, before `save`, so this is
    /// free to read straight off the sample. Callers persist these onto the
    /// day's `Completion.healthKitSampleUUIDs`, which is what makes
    /// `deleteSamples(for:uuids:)` below able to retract *exactly* what
    /// Forge itself wrote later (see `HomeView.resetHabit`) — the gap this
    /// type's doc comment used to describe as real-but-unaddressed is now
    /// closed for anything written through this method from this point
    /// forward (existing installs' completions from before this field
    /// existed still have no UUIDs to retract, which is the correct,
    /// honest lightweight-migration behavior — there's nothing to recover
    /// for a write this app genuinely didn't track at the time).
    @discardableResult
    func writeManualEntry(for habit: Habit, habitUnitAmount: Double, at date: Date) async -> [UUID] {
        guard habitUnitAmount > 0, Self.isAvailable, let mapping = HealthKitTypeMapping.mapping(for: habit) else { return [] }
        // Read-only vitals/reproductive-health mappings never reach here —
        // see `HealthKitTypeMapping`'s doc comment for why a write-back
        // would either be dishonest data (no real value to write) or
        // deliberately conservative given the data's sensitivity.
        guard mapping.supportsWriteBack else { return [] }
        guard writeAuthorizationStatus(for: habit) == .sharingAuthorized else { return [] }

        let hkValue = habitUnitAmount / mapping.habitUnitsPerHKUnit

        switch mapping.kind {
        case .quantity(let identifier):
            let type = HKQuantityType(identifier)
            let quantity = HKQuantity(unit: mapping.hkUnit, doubleValue: hkValue)
            let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
            guard (try? await healthStore.save(sample)) != nil else { return [] }
            return [sample.uuid]
        case .category(let identifier) where mapping.rule == .discreteCount:
            // `habitUnitAmount` is a plain count of discrete events (e.g.
            // "washed hands once") here, not a duration — `mapping.hkUnit`
            // is `.count()` for every `.discreteCount` mapping, which isn't
            // dimensionally convertible to seconds the way the duration-
            // based branch below needs, so this writes one short, fixed-
            // duration event sample per unit instead of deriving a length
            // from the habit's own unit conversion.
            let type = HKCategoryType(identifier)
            let eventCount = Int(habitUnitAmount.rounded())
            guard eventCount > 0 else { return [] }
            var uuids: [UUID] = []
            for _ in 0..<eventCount {
                let sample = HKCategorySample(type: type, value: 0, start: date, end: date)
                guard (try? await healthStore.save(sample)) != nil else { continue }
                uuids.append(sample.uuid)
            }
            return uuids
        case .category(let identifier):
            let type = HKCategoryType(identifier)
            let durationSeconds = HKQuantity(unit: mapping.hkUnit, doubleValue: hkValue).doubleValue(for: .second())
            let start = date.addingTimeInterval(-durationSeconds)
            let value = identifier == .sleepAnalysis ? HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue : 0
            let sample = HKCategorySample(type: type, value: value, start: start, end: date)
            guard (try? await healthStore.save(sample)) != nil else { return [] }
            return [sample.uuid]
        case .workout(let activityType):
            let durationSeconds = HKQuantity(unit: mapping.hkUnit, doubleValue: hkValue).doubleValue(for: .second())
            let start = date.addingTimeInterval(-durationSeconds)
            let workout = HKWorkout(activityType: activityType, start: start, end: date)
            guard (try? await healthStore.save(workout)) != nil else { return [] }
            return [workout.uuid]
        }
    }

    /// Deletes exactly the samples Forge itself previously wrote for this
    /// habit, identified by the `HKSample.uuid`s `writeManualEntry` handed
    /// back at write time (persisted on `Completion.healthKitSampleUUIDs`).
    /// Queries for the real objects first (`HKHealthStore.delete` needs the
    /// actual `HKObject`, not a bare UUID) via `HKQuery.predicateForObjects
    /// (with:)` — the documented, real API for exactly this "delete by
    /// previously-recorded identifier" case — then deletes only what's
    /// actually found. Never touches any other sample of the same type
    /// (e.g. a real Steps reading from the Health app/Apple Watch): a
    /// habit's completion driven entirely by external HealthKit data has an
    /// empty `uuids` array (nothing for Forge to have tracked), so this is
    /// a safe no-op for that case rather than something that needs its own
    /// separate guard.
    func deleteSamples(for habit: Habit, uuids: [UUID]) async {
        guard !uuids.isEmpty, Self.isAvailable, let mapping = HealthKitTypeMapping.mapping(for: habit) else { return }
        let predicate = HKQuery.predicateForObjects(with: Set(uuids))
        let objects: [HKObject] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: mapping.sampleType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples ?? [])
            }
            healthStore.execute(query)
        }
        guard !objects.isEmpty else { return }
        try? await healthStore.delete(objects)
    }

    // MARK: - Background delivery

    /// Registers one `HKObserverQuery` + `enableBackgroundDelivery` per
    /// distinct HealthKit sample type this app ever maps a habit to (a
    /// small, fixed set from `HealthKitTypeMapping.allSampleTypes` — not
    /// dynamically limited to "types a habit currently exists for," which
    /// would need re-registering every time a habit is added; registering
    /// the whole known catalog up front is simpler and the extra idle
    /// observers cost nothing). Must be called again every app launch —
    /// `enableBackgroundDelivery`'s *preference* persists in HealthKit
    /// itself, but the observer query registration does not.
    ///
    /// This is the piece the original RN app's entitlements declared but
    /// never implemented — real now: when new data lands from the user's
    /// Watch or another Health app, iOS wakes Forge briefly in the
    /// background specifically for this (HealthKit's own background-wake
    /// mechanism, distinct from `BGTaskScheduler`), and the observer here
    /// re-reads and re-persists completion state for every affected habit.
    func registerBackgroundDelivery() async {
        guard Self.isAvailable else { return }
        for sampleType in HealthKitTypeMapping.allSampleTypes {
            try? await healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate)
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, _ in
                // HKObserverQuery's closure type predates Swift 6's
                // Sendable audits, so none of its captures are seen as
                // provably Sendable by the checker even though they safely
                // are (an actor reference, an immutable HealthKit type
                // value, and a completion handler HealthKit itself invokes
                // from arbitrary threads). Asserting that explicitly here
                // rather than fighting the checker.
                nonisolated(unsafe) let handler = completionHandler
                nonisolated(unsafe) let capturedSampleType = sampleType
                nonisolated(unsafe) let service = self
                Task {
                    await service?.handleObserverUpdate(for: capturedSampleType)
                    handler()
                }
            }
            healthStore.execute(query)
        }
    }

    /// Fired by an `HKObserverQuery` for one sample type — re-reads and
    /// re-persists every non-archived habit that actually maps to that
    /// type (a small, bounded set: however many habits share one
    /// HealthKit type, realistically a handful, not a scaling concern),
    /// then runs the same milestone check a real in-app tap would.
    private func handleObserverUpdate(for sampleType: HKSampleType) async {
        let allHabits = (try? await habitRepository.fetchAll()) ?? []
        let affected = allHabits.filter { habit in
            guard !habit.isArchived, let mapping = HealthKitTypeMapping.mapping(for: habit) else { return false }
            return mapping.sampleType == sampleType
        }
        guard !affected.isEmpty else { return }

        for habit in affected {
            guard let hkState = await todayCompletionState(for: habit) else { continue }
            let todaysCompletions = (try? await habitRepository.fetchCompletions(for: .now)) ?? []
            var completion = todaysCompletions.first(where: { $0.habitID == habit.id }) ?? Completion(habitID: habit.id, date: .now)
            completion.count = hkState.count
            completion.isComplete = hkState.isComplete
            completion.loggedAt = .now
            try? await habitRepository.upsertCompletion(completion)
            await milestoneEngine.afterCompletionLogged(habit: habit)
        }
    }

    // MARK: - Query helpers

    /// Count of samples of `type` within `[start, end]`, optionally
    /// restricted to a specific `HKCategoryValue` raw value (used only by
    /// the contraceptive-pill mapping, to count just `.oral` entries) —
    /// backs every `.discreteCount` mapping, generically across
    /// quantity/category/workout sample types, since "how many samples
    /// exist" doesn't depend on which of those three `type` actually is.
    private func sampleCount(type: HKSampleType, start: Date, end: Date, categoryValueFilter: Int?) async -> Int {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples else {
                    continuation.resume(returning: 0)
                    return
                }
                guard let categoryValueFilter else {
                    continuation.resume(returning: samples.count)
                    return
                }
                let matching = samples.filter { ($0 as? HKCategorySample)?.value == categoryValueFilter }
                continuation.resume(returning: matching.count)
            }
            healthStore.execute(query)
        }
    }

    private func cumulativeQuantitySum(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(type: HKCategoryType, start: Date, end: Date) async -> [HKCategorySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func workoutSamples(activityType: HKWorkoutActivityType, start: Date, end: Date) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let activityPredicate = HKQuery.predicateForWorkouts(with: activityType)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, activityPredicate])
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func durationValue(seconds: Double, in unit: HKUnit) -> Double {
        HKQuantity(unit: .second(), doubleValue: seconds).doubleValue(for: unit)
    }
}

private extension HKCategoryValueSleepAnalysis {
    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: true
        case .inBed, .awake: false
        @unknown default: false
        }
    }
}
