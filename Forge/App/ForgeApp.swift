import SwiftUI
import SwiftData
import UserNotifications

@main
struct ForgeApp: App {
    private let modelContainer: ModelContainer
    private let habitRepository: HabitRepository
    private let templateSectionRepository: TemplateSectionRepository
    private let milestoneRepository: MilestoneRepository
    private let milestoneEngine: MilestoneEngine
    private let healthKitService: HealthKitService
    private let calendarSyncService: CalendarSyncService
    private let moodRepository: MoodRepository
    private let entitlementService: EntitlementService
    private let authService: AuthService
    /// Held as a `let` so it outlives `init()` — `UNUserNotificationCenter`
    /// only keeps a weak reference to its `delegate`.
    private let appNotificationDelegate = AppNotificationDelegate()

    init() {
        let schema = Schema([
            HabitModel.self,
            CompletionModel.self,
            TemplateSectionConfigurationModel.self,
            CustomSectionModel.self,
            MilestoneModel.self,
            PointsLedgerModel.self,
            MoodEntryModel.self,
        ])

        // SwiftData's default store location is Application Support, which
        // isn't guaranteed to exist yet on a fresh install — without this,
        // ModelContainer's first launch hits "Failed to stat path
        // '.../Application Support/default.store', Sandbox access to
        // file-write-create denied" and falls through to SwiftData's own
        // (CoreData-backed) recovery path before succeeding. Creating the
        // directory proactively avoids that failure/recovery round-trip
        // rather than depending on it. Best-effort: if this fails for some
        // other reason, ModelContainer below still has its own fatalError
        // as the real error path.
        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }

        // TEMPORARY — UI-test-only seed path for the weekly-pager swipe
        // investigation. Launching with `-uiTesting` switches to an
        // in-memory store (never touches the real on-device data) and
        // synchronously inserts one habit with `startDate` 8 weeks back, so
        // there's real history to page into. Remove this whole block, and
        // the `isUITesting` ternary below, once that investigation is done.
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        if isUITesting {
            let context = ModelContext(modelContainer)
            let eightWeeksAgo = Calendar.current.date(byAdding: .day, value: -56, to: .now) ?? .now
            let habit = Habit(title: "Pager Test Habit", category: .good, startDate: eightWeeksAgo)
            context.insert(HabitModel(habit: habit))
            // A short real goal (3 seconds, expressed in minutes since
            // `HabitUnit` has no seconds case) — seeded for
            // `TimerHabitTests`, so the timer genuinely reaches its goal
            // within a normal test timeout instead of needing a multi-
            // minute real wait.
            let timerHabit = Habit(title: "Timer Test Habit", category: .good, iconSystemName: "timer", goal: 0.05, unit: .minutes, startDate: eightWeeksAgo)
            context.insert(HabitModel(habit: timerHabit))
            // Seeded for `ResetHabitTests` — a plain quantity habit (small
            // goal, so a couple of taps reach partial progress quickly)
            // to exercise the long-press Complete/Reset dialog.
            let quantityHabit = Habit(title: "Quantity Test Habit", category: .good, iconSystemName: "number", goal: 3, unit: .count, step: 1, startDate: eightWeeksAgo)
            context.insert(HabitModel(habit: quantityHabit))
            // A deliberately *longer* goal than "Timer Test Habit" above —
            // seeded for `TimerHabitTests.testStopButtonStopsRunningTimer`,
            // which needs the timer to still genuinely be running while it
            // locates and taps the Stop button; the 3-second habit above
            // was found to auto-complete out from under that test before
            // it got that far (a real, measured test-timing finding, not a
            // Stop button bug — see RESULTS.md).
            let stopButtonTestHabit = Habit(title: "Stop Button Test Habit", category: .good, iconSystemName: "timer", goal: 2, unit: .minutes, startDate: eightWeeksAgo)
            context.insert(HabitModel(habit: stopButtonTestHabit))
            try? context.save()
        }
        habitRepository = SwiftDataHabitRepository(modelContainer: modelContainer)
        templateSectionRepository = SwiftDataTemplateSectionRepository(modelContainer: modelContainer)
        milestoneRepository = SwiftDataMilestoneRepository(modelContainer: modelContainer)
        milestoneEngine = MilestoneEngine(habitRepository: habitRepository, milestoneRepository: milestoneRepository)
        healthKitService = HealthKitService(habitRepository: habitRepository, milestoneEngine: milestoneEngine)
        calendarSyncService = EventKitCalendarSyncService(habitRepository: habitRepository)
        moodRepository = SwiftDataMoodRepository(modelContainer: modelContainer)
        entitlementService = StubEntitlementService()
        // `-uiTesting` gets the always-signed-out stand-in, matching the
        // in-memory `ModelConfiguration` above — a real Sign in with Apple
        // flow needs genuine user interaction with a system sheet and has
        // no place in an automated fixture.
        authService = isUITesting ? InMemoryAuthService() : AppleAuthService()

        UNUserNotificationCenter.current().delegate = appNotificationDelegate

        let service = healthKitService
        Task { await service.registerBackgroundDelivery() }

        // Re-populate `HabitTimerCoordinator`'s in-memory Live Activity
        // handles from ActivityKit's own system-tracked state — a timer
        // running before this process was last killed is still genuinely
        // active (system-rendered), just not yet known to this fresh
        // process's coordinator instance. `HomeView`'s own catch-up sweep
        // (persisted `Completion.startedAt`, not this call) is what
        // actually re-marks an overdue timer's habit complete; this only
        // restores the ability to *end* its Live Activity when that
        // happens.
        Task { HabitTimerCoordinator.shared.reattachExistingActivities() }

        // Refresh the weekly reflection notification's content on every
        // launch — see `WeeklyReflectionScheduler`'s doc comment for why
        // this is the chosen freshness mechanism (no remote push/
        // BGTaskScheduler in this app yet). Reads UserDefaults directly
        // rather than `@AppStorage`, matching `VacationSettings`'s own
        // established pattern for reading app settings outside a View.
        let repository = habitRepository
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "weeklyReflectionEnabled") != nil, defaults.bool(forKey: "weeklyReflectionEnabled") {
            let weekday = defaults.object(forKey: "weeklyReflectionWeekday") as? Int ?? 1
            let hour = defaults.object(forKey: "weeklyReflectionHour") as? Int ?? 18
            let minute = defaults.object(forKey: "weeklyReflectionMinute") as? Int ?? 0
            Task {
                await WeeklyReflectionScheduler.reschedule(
                    habitRepository: repository,
                    enabled: true,
                    weekday: weekday,
                    hour: hour,
                    minute: minute
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AppTabView()
                .environment(\.habitRepository, habitRepository)
                .environment(\.templateSectionRepository, templateSectionRepository)
                .environment(\.milestoneRepository, milestoneRepository)
                .environment(\.milestoneEngine, milestoneEngine)
                .environment(\.healthKitService, healthKitService)
                .environment(\.calendarSyncService, calendarSyncService)
                .environment(\.moodRepository, moodRepository)
                .environment(\.entitlementService, entitlementService)
                .environment(\.authService, authService)
        }
    }
}
