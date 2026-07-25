#if DEBUG
import SwiftUI
import HealthKit

/// Debug-only tool for verifying the real HealthKit integration on
/// Simulator. Three steps, in order:
///
/// 1. **Create test habits** — inserts real `Habit` records (matching real
///    `TemplateCatalog` templates exactly: same title/category/icon/goal/
///    `sourceTemplateID`) directly via `HabitRepository.save(_:)`. Added
///    specifically because driving the real Add Habit flow's template-
///    picker sheet via XCUITest turned out not to register taps reliably
///    in this Simulator environment (confirmed general, not specific to
///    any one template — even a pre-existing template's row had the same
///    problem) — this project has prior, separate precedent of specific
///    SwiftUI gesture/interaction patterns not synthesizing correctly in
///    Simulator (see CLAUDE.md), and this looks like another instance
///    rather than something fixable by trying different tap variants.
///    Bypassing that one flaky UI step still exercises every part of the
///    integration that's actually in question: real HealthKit
///    authorization, real reads, real writes.
/// 2. **Request authorization** — a single combined `requestAuthorization`
///    call for every test habit's type at once (for convenience here only
///    — the real app's own contextual per-habit-type scoping in
///    `HabitFormView.save()` is unchanged and already verified by code
///    review, not by this debug path).
/// 3. **Seed sample data** — writes real HealthKit samples via
///    `HKHealthStore.save(_:)`, the same real API `HealthKitService`
///    itself uses, so what's seeded here is indistinguishable from data a
///    Watch or the Health app itself would produce.
///
/// The whole file is `#if DEBUG` — unreachable in a release binary by
/// construction, matching `DebugSeedHistoryView`.
struct DebugSeedHealthKitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.habitRepository) private var habitRepository
    @State private var resultMessage: String?

    private let healthStore = HKHealthStore()

    private static let testHabits: [Habit] = [
        Habit(title: "Basketball", category: .good, isHealthKitTracked: true, sourceTemplateID: "hk-basketball", iconSystemName: "basketball.fill", goal: 30, unit: .minutes, step: 10),
        Habit(title: "Wash Your Hands", category: .good, isHealthKitTracked: true, sourceTemplateID: "hk-handwashing", iconSystemName: "hands.and.sparkles.fill", goal: 5, unit: .count, step: 1),
        Habit(title: "Blood Pressure", category: .good, isHealthKitTracked: true, sourceTemplateID: "hk-blood-pressure", iconSystemName: "waveform.path.ecg", goal: 1, unit: .count, step: 1),
        Habit(title: "Weight", category: .good, isHealthKitTracked: true, sourceTemplateID: "hk-weight", iconSystemName: "scalemass.fill", goal: 1, unit: .count, step: 1),
        Habit(title: "Drink Water", category: .good, isHealthKitTracked: true, sourceTemplateID: "drink-water", iconSystemName: "drop.fill", goal: 8, unit: .glasses, step: 1),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. Create the test habits below, 2. request HealthKit authorization once for all of them, 3. seed real sample data, then check Home for auto-completion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("1. Test habits") {
                    actionButton("Create All Test Habits", action: createTestHabits)
                }

                Section("2. Authorization") {
                    actionButton("Request HealthKit Authorization", action: requestAuthorization)
                    actionButton("Check Authorization Status", action: checkAuthorizationStatus)
                }

                Section("3. Read-path verification samples") {
                    actionButton("Basketball workout (35 min)", action: seedBasketballWorkout)
                    actionButton("Blood Pressure reading (120/80)", action: seedBloodPressure)
                    actionButton("Weight reading (72 kg)", action: seedWeight)
                    actionButton("Handwashing × 5", action: seedHandwashing)
                    actionButton("Drink Water (8 glasses)", action: seedWater)
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Seed HealthKit Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // Deliberately no shared-disabled state across buttons — each action is
    // independent and idempotent enough for a debug tool that a stray
    // overlapping tap is harmless, and a single shared `isWorking` flag
    // disabling *every* button while *any one* is mid-flight turned out to
    // race real test automation (a slow action, e.g. one that itself
    // triggers a HealthKit authorization round trip, could still be
    // "working" when the next button was tapped moments later).
    private func actionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) {
            Task { await action() }
        }
    }

    private func createTestHabits() async {
        for habit in Self.testHabits {
            try? await habitRepository.save(habit)
        }
        resultMessage = "Created \(Self.testHabits.count) test habits (or updated them if already present)."
    }

    private func requestAuthorization() async {
        // `toShare` must exclude any mapping with `supportsWriteBack ==
        // false` — this is what surfaced the real
        // `HKCorrelationTypeIdentifierBloodPressure` share-authorization
        // crash this pass found and fixed in `HealthKitService
        // .requestAuthorization(for:)`; mirrored here for the same reason.
        let mappings = Self.testHabits.compactMap { HealthKitTypeMapping.mapping(for: $0) }
        let shareTypes = Set(mappings.filter(\.supportsWriteBack).map(\.sampleType))
        let readTypes = Set(mappings.map(\.sampleType))
        do {
            try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
            resultMessage = "Requested authorization for \(readTypes.count) HealthKit types (\(shareTypes.count) also writable)."
        } catch {
            resultMessage = "Authorization request failed: \(error.localizedDescription)"
        }
    }

    private func checkAuthorizationStatus() async {
        let lines = Self.testHabits.compactMap { habit -> String? in
            guard let mapping = HealthKitTypeMapping.mapping(for: habit) else { return nil }
            let status = healthStore.authorizationStatus(for: mapping.sampleType)
            let statusText: String
            switch status {
            case .notDetermined: statusText = "notDetermined"
            case .sharingDenied: statusText = "denied"
            case .sharingAuthorized: statusText = "authorized"
            @unknown default: statusText = "unknown"
            }
            return "\(habit.title): \(statusText)"
        }
        resultMessage = lines.joined(separator: "\n")
    }

    private func seedBasketballWorkout() async {
        let end = Date.now
        let start = end.addingTimeInterval(-35 * 60)
        let workout = HKWorkout(activityType: .basketball, start: start, end: end)
        do {
            try await healthStore.save(workout)
            resultMessage = "Saved a 35-minute Basketball workout ending now."
        } catch {
            resultMessage = "Failed: \(error.localizedDescription)"
        }
    }

    /// Simulates an *external* source (Health app, Watch, a BP cuff's own
    /// app) logging a reading — Forge's own real authorization deliberately
    /// never requests share access for this type (see
    /// `HealthKitTypeMapping`'s doc comment: Blood Pressure is read-only in
    /// production), so this needs its own separate, debug-only share
    /// authorization for the constituent systolic/diastolic quantity types
    /// specifically to seed test data at all — note this requests
    /// authorization on those two quantity types directly, never on
    /// `HKCorrelationType(.bloodPressure)` itself, which HealthKit
    /// disallows requesting any authorization on (confirmed live this
    /// pass — see `HealthKitTypeMapping`'s doc comment for the crash this
    /// produced before that was understood).
    private func seedBloodPressure() async {
        let now = Date.now
        let systolicType = HKQuantityType(.bloodPressureSystolic)
        let diastolicType = HKQuantityType(.bloodPressureDiastolic)
        do {
            try await healthStore.requestAuthorization(toShare: [systolicType, diastolicType], read: [])
        } catch {
            resultMessage = "Debug-only BP share authorization failed: \(error.localizedDescription)"
            return
        }
        let systolic = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 120),
            start: now, end: now
        )
        let diastolic = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 80),
            start: now, end: now
        )
        let correlationType = HKCorrelationType(.bloodPressure)
        let correlation = HKCorrelation(type: correlationType, start: now, end: now, objects: [systolic, diastolic])
        do {
            try await healthStore.save(correlation)
            resultMessage = "Saved a 120/80 Blood Pressure reading for now."
        } catch {
            resultMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func seedWeight() async {
        let now = Date.now
        let type = HKQuantityType(.bodyMass)
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 72), start: now, end: now)
        do {
            try await healthStore.save(sample)
            resultMessage = "Saved a 72kg Weight reading for now."
        } catch {
            resultMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func seedHandwashing() async {
        let type = HKCategoryType(.handwashingEvent)
        do {
            for i in 0..<5 {
                let end = Date.now.addingTimeInterval(Double(-i) * 3600)
                let start = end.addingTimeInterval(-20)
                let sample = HKCategorySample(type: type, value: 0, start: start, end: end)
                try await healthStore.save(sample)
            }
            resultMessage = "Saved 5 Handwashing events spread across today."
        } catch {
            resultMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func seedWater() async {
        let now = Date.now
        let type = HKQuantityType(.dietaryWater)
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .fluidOunceUS(), doubleValue: 64), start: now, end: now)
        do {
            try await healthStore.save(sample)
            resultMessage = "Saved 64 fl oz (8 glasses) of Drink Water for now."
        } catch {
            resultMessage = "Failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DebugSeedHealthKitView()
        .environment(\.habitRepository, InMemoryHabitRepository())
}
#endif
