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
    private let moodRepository: MoodRepository
    private let entitlementService: EntitlementService
    /// Held as a `let` so it outlives `init()` — `UNUserNotificationCenter`
    /// only keeps a weak reference to its `delegate`.
    private let moodNotificationDelegate = MoodNotificationDelegate()

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
            try? context.save()
        }
        habitRepository = SwiftDataHabitRepository(modelContainer: modelContainer)
        templateSectionRepository = SwiftDataTemplateSectionRepository(modelContainer: modelContainer)
        milestoneRepository = SwiftDataMilestoneRepository(modelContainer: modelContainer)
        milestoneEngine = MilestoneEngine(habitRepository: habitRepository, milestoneRepository: milestoneRepository)
        healthKitService = HealthKitService(habitRepository: habitRepository, milestoneEngine: milestoneEngine)
        moodRepository = SwiftDataMoodRepository(modelContainer: modelContainer)
        entitlementService = StubEntitlementService()

        UNUserNotificationCenter.current().delegate = moodNotificationDelegate

        let service = healthKitService
        Task { await service.registerBackgroundDelivery() }
    }

    var body: some Scene {
        WindowGroup {
            AppTabView()
                .environment(\.habitRepository, habitRepository)
                .environment(\.templateSectionRepository, templateSectionRepository)
                .environment(\.milestoneRepository, milestoneRepository)
                .environment(\.milestoneEngine, milestoneEngine)
                .environment(\.healthKitService, healthKitService)
                .environment(\.moodRepository, moodRepository)
                .environment(\.entitlementService, entitlementService)
        }
    }
}
