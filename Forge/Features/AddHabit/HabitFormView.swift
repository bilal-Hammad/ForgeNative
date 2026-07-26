import SwiftUI
import UIKit

/// The habit creation/edit form (APP_REDESIGN_SPEC.md §12's recommended
/// field order): Title → Icon & Color → Goal/Unit/Increment → Repeat → Time.
///
/// Notifications, Calendar sync, and Reminders-app sync are **not** managed
/// here anymore — all three moved to a centralized system in Settings
/// (`SettingsView`'s Notifications section → `HabitSyncSettingsDetailView`),
/// reached by drilling into a habit from a list, not this create/edit form.
/// Time mode (below) stays here on purpose: it's scheduling logic (*when* a
/// notification would fire), a separate concern from the on/off toggle
/// itself. New habits get `notificationsEnabled: true`,
/// `remindersAppSyncEnabled: false`, `calendarSyncEnabled: false` as fixed
/// defaults (see each `init` below) — editing an existing habit here always
/// carries its current values through unchanged, since this form no longer
/// has any UI that could touch them.
///
/// Two modes, driven by which initializer is used:
/// - Create: seeded from a `HabitTemplate` picked in `CategoryDetailView`,
///   including its per-habit smart goal/unit/step defaults.
/// - Edit: seeded from an existing `Habit` (e.g. tapped from Home's list).
///
/// Goal and Increment are proper numeric inputs (`TextField(value:
/// format:)` bound to `Double`, plus a `Stepper`) — not free text. Unit is a
/// fixed `Picker` over `HabitUnit.pickerOptions`, not free text either; the
/// full derived unit set (and the two units folded into `.count` rather than
/// kept distinct) came from auditing the real RN app's template data, not a
/// guess.
///
/// §12 editability rule: title/icon/color are editable in both modes, even
/// for HealthKit-tracked habits — but goal/unit/step are locked whenever
/// `isHealthKitTracked` is true, in either mode, since those are fixed by
/// the underlying HK quantity type, not something Forge lets the user
/// redefine. (`HabitUnit`'s three internal-only medical units, e.g. mmHg,
/// are meant for exactly this locked-HK-template treatment too, but as of
/// the real HealthKit integration pass, zero templates in `TemplateCatalog`
/// actually use them yet — see `HealthKitTypeMapping`'s doc comment.)
///
/// Because title/icon stay editable even for HealthKit-tracked habits, this
/// form can't use either to figure out *which* real HealthKit type a saved
/// habit maps to — that's what `Habit.sourceTemplateID` (set once at
/// creation, immutable after) is for; see `HealthKitTypeMapping`.
///
/// Reminders-app/Calendar sync toggles remain UI-present, not functionally
/// wired (Phase 4+, per §10's framing). Notifications and HealthKit are
/// both real now: see `HabitNotificationScheduler` for how `timeMode`/
/// `repeatMode` map to actual scheduled reminders (permission requested at
/// the moment it's first relevant — turning that toggle on, or picking a
/// Time mode other than "None" — not proactively on first app launch), and
/// `HealthKitService`/`HealthKitTypeMapping` for read/write/background sync
/// (permission requested here, on save, the moment a new HealthKit-tracked
/// habit is actually created).
struct HabitFormView: View {
    var onSave: () -> Void

    @Environment(\.habitRepository) private var habitRepository
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.dismiss) private var dismiss

    private let habitID: UUID
    private let isCreatingNew: Bool
    private let isHealthKitTracked: Bool
    /// Immutable once set — see `Habit.sourceTemplateID`'s doc comment for
    /// why (title/icon are editable even for HealthKit-tracked habits, so
    /// neither can double as the HealthKit-type lookup key).
    private let sourceTemplateID: String?
    /// Not exposed in this form (archiving happens via a swipe action on
    /// Home) — carried through on save so editing a habit never silently
    /// un-archives it.
    private let isArchived: Bool

    @State private var title: String
    @State private var category: HabitCategory
    @State private var iconSystemName: String
    @State private var color: HabitColor
    @State private var goal: Double
    @State private var unit: HabitUnit
    @State private var step: Double
    @State private var repeatModeKind: RepeatModeKind
    @State private var specificDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var everyXDays: Int
    @State private var timeModeKind: TimeModeKind
    @State private var fixedTime: Date
    @State private var everyXHours: Int
    @State private var timesADay: Int
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    /// Fixed defaults on create, carried through unchanged on edit — see
    /// this type's doc comment for why these three are plain `let`s, not
    /// `@State`: there's no UI here to change them anymore.
    private let notificationsEnabled: Bool
    private let remindersAppSyncEnabled: Bool
    private let calendarSyncEnabled: Bool
    /// Read-only here — only used to pass the current global state into
    /// `HabitNotificationScheduler.reschedule(...)` on save (still needed
    /// since Time mode, which affects real scheduling, is still edited in
    /// this form). The toggle itself lives in Settings now.
    @AppStorage("notificationsEnabledGlobal") private var globalNotificationsEnabled: Bool = false
    @State private var healthKitConnected = false

    /// `nil` means this habit either isn't HealthKit-tracked, or is tagged
    /// `isHealthKitTracked` but has no real HealthKit type behind it (see
    /// `HealthKitTypeMapping`'s doc comment on "cold-shower"/"vitamins") —
    /// both cases render identically here: no HealthKit section at all.
    private var healthKitMapping: HealthKitTypeMapping.Mapping? {
        guard isHealthKitTracked, let sourceTemplateID else { return nil }
        return HealthKitTypeMapping.byTemplateID[sourceTemplateID]
    }

    private enum RepeatModeKind: String, CaseIterable, Identifiable {
        case daily, specificDays, timesPerWeek, everyXDays
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .daily: "Every Day"
            case .specificDays: "Specific Days"
            case .timesPerWeek: "Times per Week"
            case .everyXDays: "Every X Days"
            }
        }
    }

    private enum TimeModeKind: String, CaseIterable, Identifiable {
        case none, fixedTime, everyXHours, timesADay
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .none: "None"
            case .fixedTime: "Time"
            case .everyXHours: "Every X Hours"
            case .timesADay: "X Times a Day"
            }
        }
    }

    private static let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    private static let iconChoices = [
        "checkmark.circle", "star.fill", "flame.fill", "drop.fill", "leaf.fill",
        "figure.walk", "figure.run", "bed.double.fill", "book.fill", "pencil",
        "heart.fill", "brain.head.profile", "cup.and.saucer.fill", "moon.fill",
        "sun.max.fill", "dumbbell.fill", "music.note", "phone.fill", "dollarsign.circle.fill",
        "house.fill",
    ]

    /// Create mode — seeded from a picked `HabitTemplate`, including its
    /// per-habit goal/unit/step defaults (not left blank).
    init(template: HabitTemplate, onSave: @escaping () -> Void) {
        self.onSave = onSave
        habitID = UUID()
        isCreatingNew = true
        isHealthKitTracked = template.isHealthKitTracked
        sourceTemplateID = template.id
        isArchived = false
        _title = State(initialValue: template.title)
        _category = State(initialValue: template.category)
        _iconSystemName = State(initialValue: template.iconSystemName)
        _color = State(initialValue: .blue)
        _goal = State(initialValue: template.goal)
        _unit = State(initialValue: template.unit)
        _step = State(initialValue: template.step)
        _repeatModeKind = State(initialValue: .daily)
        _specificDays = State(initialValue: [0, 1, 2, 3, 4, 5, 6])
        _timesPerWeek = State(initialValue: 3)
        _everyXDays = State(initialValue: 2)
        _timeModeKind = State(initialValue: .none)
        _fixedTime = State(initialValue: .now)
        _everyXHours = State(initialValue: 3)
        _timesADay = State(initialValue: 3)
        _startDate = State(initialValue: .now)
        _hasEndDate = State(initialValue: false)
        _endDate = State(initialValue: .now.addingTimeInterval(30 * 86400))
        notificationsEnabled = true
        remindersAppSyncEnabled = false
        calendarSyncEnabled = false
    }

    /// Create mode — from-scratch custom habit, no template at all. This is
    /// the Add Habit screen's "+" shortcut: since it skips category
    /// selection entirely (there's no `CategoryDetailView` step to have
    /// already fixed one), this is the one path where the form itself
    /// shows a Category picker (see `body`) rather than treating category
    /// as fixed at creation. `sourceTemplateID` stays nil and
    /// `isHealthKitTracked` stays false — a custom habit has no HealthKit
    /// type to map to by construction.
    init(customHabitCategory: HabitCategory, onSave: @escaping () -> Void) {
        self.onSave = onSave
        habitID = UUID()
        isCreatingNew = true
        isHealthKitTracked = false
        sourceTemplateID = nil
        isArchived = false
        _title = State(initialValue: "")
        _category = State(initialValue: customHabitCategory)
        _iconSystemName = State(initialValue: "checkmark.circle")
        _color = State(initialValue: .blue)
        _goal = State(initialValue: 1)
        _unit = State(initialValue: .count)
        _step = State(initialValue: 1)
        _repeatModeKind = State(initialValue: .daily)
        _specificDays = State(initialValue: [0, 1, 2, 3, 4, 5, 6])
        _timesPerWeek = State(initialValue: 3)
        _everyXDays = State(initialValue: 2)
        _timeModeKind = State(initialValue: .none)
        _fixedTime = State(initialValue: .now)
        _everyXHours = State(initialValue: 3)
        _timesADay = State(initialValue: 3)
        _startDate = State(initialValue: .now)
        _hasEndDate = State(initialValue: false)
        _endDate = State(initialValue: .now.addingTimeInterval(30 * 86400))
        notificationsEnabled = true
        remindersAppSyncEnabled = false
        calendarSyncEnabled = false
    }

    /// Edit mode — seeded from an existing, already-saved `Habit`.
    init(existingHabit habit: Habit, onSave: @escaping () -> Void) {
        self.onSave = onSave
        habitID = habit.id
        isCreatingNew = false
        isHealthKitTracked = habit.isHealthKitTracked
        sourceTemplateID = habit.sourceTemplateID
        isArchived = habit.isArchived
        _title = State(initialValue: habit.title)
        _category = State(initialValue: habit.category)
        _iconSystemName = State(initialValue: habit.iconSystemName)
        _color = State(initialValue: habit.color)
        _goal = State(initialValue: habit.goal)
        _unit = State(initialValue: habit.unit)
        _step = State(initialValue: habit.step)

        switch habit.repeatMode {
        case .daily:
            _repeatModeKind = State(initialValue: .daily)
            _specificDays = State(initialValue: [0, 1, 2, 3, 4, 5, 6])
            _timesPerWeek = State(initialValue: 3)
            _everyXDays = State(initialValue: 2)
        case .specificDays(let days):
            _repeatModeKind = State(initialValue: .specificDays)
            _specificDays = State(initialValue: days)
            _timesPerWeek = State(initialValue: 3)
            _everyXDays = State(initialValue: 2)
        case .timesPerWeek(let count):
            _repeatModeKind = State(initialValue: .timesPerWeek)
            _specificDays = State(initialValue: [0, 1, 2, 3, 4, 5, 6])
            _timesPerWeek = State(initialValue: count)
            _everyXDays = State(initialValue: 2)
        case .everyXDays(let interval):
            _repeatModeKind = State(initialValue: .everyXDays)
            _specificDays = State(initialValue: [0, 1, 2, 3, 4, 5, 6])
            _timesPerWeek = State(initialValue: 3)
            _everyXDays = State(initialValue: interval)
        }

        switch habit.timeMode {
        case .none:
            _timeModeKind = State(initialValue: .none)
            _fixedTime = State(initialValue: .now)
            _everyXHours = State(initialValue: 3)
            _timesADay = State(initialValue: 3)
        case .fixedTime(let date):
            _timeModeKind = State(initialValue: .fixedTime)
            _fixedTime = State(initialValue: date)
            _everyXHours = State(initialValue: 3)
            _timesADay = State(initialValue: 3)
        case .everyXHours(let hours):
            _timeModeKind = State(initialValue: .everyXHours)
            _fixedTime = State(initialValue: .now)
            _everyXHours = State(initialValue: hours)
            _timesADay = State(initialValue: 3)
        case .timesADay(let count):
            _timeModeKind = State(initialValue: .timesADay)
            _fixedTime = State(initialValue: .now)
            _everyXHours = State(initialValue: 3)
            _timesADay = State(initialValue: count)
        }

        _startDate = State(initialValue: habit.startDate)
        _hasEndDate = State(initialValue: habit.endDate != nil)
        _endDate = State(initialValue: habit.endDate ?? .now.addingTimeInterval(30 * 86400))
        notificationsEnabled = habit.notificationsEnabled
        remindersAppSyncEnabled = habit.remindersAppSyncEnabled
        calendarSyncEnabled = habit.calendarSyncEnabled
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("Title", text: $title)

                    if isCreatingNew && sourceTemplateID == nil {
                        Picker("Category", selection: $category) {
                            ForEach(HabitCategory.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    }

                    Picker("Icon", selection: $iconSystemName) {
                        ForEach(Self.iconChoices, id: \.self) { name in
                            Image(systemName: name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("Color")
                        Spacer()
                        ForEach(HabitColor.allCases) { option in
                            Circle()
                                .fill(option.color)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if option == color {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { color = option }
                        }
                    }
                }

                Section {
                    if isHealthKitTracked {
                        HStack {
                            Text("Goal")
                            Spacer()
                            Text(goal.formatted())
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Unit")
                            Spacer()
                            Text(unit.displayName)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Goal")
                            Spacer()
                            TextField("Goal", value: $goal, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Stepper("", value: $goal, in: 1...100000)
                                .labelsHidden()
                        }

                        Picker("Unit", selection: $unit) {
                            ForEach(HabitUnit.pickerOptions) { option in
                                Text(option.displayName).tag(option)
                            }
                        }

                        // A duration goal has no coherent "increment by a
                        // fixed step" meaning — minutes/hours habits use the
                        // native timer interaction instead of tap-to-
                        // increment (see HomeView.handleTap), so there's
                        // nothing for this field to configure.
                        if !unit.isTimeBased {
                            HStack {
                                Text("Increment")
                                Spacer()
                                TextField("Step", value: $step, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Stepper("", value: $step, in: 1...10000)
                                    .labelsHidden()
                            }
                        }
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    if isHealthKitTracked {
                        Text("Fixed by this habit's HealthKit type — not editable.")
                    }
                }

                if isHealthKitTracked {
                    Section {
                        HStack {
                            Text("Health")
                            Spacer()
                            if !HealthKitService.isAvailable {
                                Text("Not Available").foregroundStyle(.secondary)
                            } else if healthKitMapping == nil {
                                Text("Not supported").foregroundStyle(.secondary)
                            } else if healthKitConnected {
                                Label("Connected", systemImage: "heart.fill")
                                    .foregroundStyle(.pink)
                            } else {
                                Label("Not Connected", systemImage: "heart.slash")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if HealthKitService.isAvailable, healthKitMapping != nil, !healthKitConnected {
                            Button("Open iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    } footer: {
                        // `HealthKitService.isAvailable` (backed by
                        // `HKHealthStore.isHealthDataAvailable()`) is what
                        // actually goes false on iPad — Apple's real,
                        // documented platform restriction, not a device-
                        // idiom check coded around it. This same flag also
                        // covered older Simulator runtimes, which genuinely
                        // didn't support HealthKit at all; recent Simulator
                        // runtimes do (confirmed empirically this pass), so
                        // this message no longer assumes Simulator = always
                        // unavailable.
                        if !HealthKitService.isAvailable {
                            Text("Health tracking isn't available on this device (this includes iPad) — this habit still works as a plain manual habit, it just won't auto-sync.")
                        } else if healthKitMapping == nil {
                            Text("This habit is marked HealthKit-tracked, but there's no real Health data type for it — it behaves as a manual habit.")
                        } else if !healthKitConnected {
                            Text("Grant Health access for automatic read/write sync.")
                        } else {
                            Text("Real HealthKit data automatically marks this habit complete; manual taps write back to Health too.")
                        }
                    }
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $repeatModeKind) {
                        ForEach(RepeatModeKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    switch repeatModeKind {
                    case .daily:
                        EmptyView()
                    case .specificDays:
                        ForEach(0..<7, id: \.self) { weekday in
                            Toggle(Self.weekdaySymbols[weekday], isOn: Binding(
                                get: { specificDays.contains(weekday) },
                                set: { isOn in
                                    if isOn { specificDays.insert(weekday) } else { specificDays.remove(weekday) }
                                }
                            ))
                        }
                    case .timesPerWeek:
                        Stepper("\(timesPerWeek) times per week", value: $timesPerWeek, in: 1...7)
                    case .everyXDays:
                        Stepper("Every \(everyXDays) days", value: $everyXDays, in: 2...365)
                    }
                }

                Section("Time") {
                    Picker("Time", selection: $timeModeKind) {
                        ForEach(TimeModeKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }

                    switch timeModeKind {
                    case .none:
                        EmptyView()
                    case .fixedTime:
                        DatePicker("Time", selection: $fixedTime, displayedComponents: .hourAndMinute)
                    case .everyXHours:
                        Stepper("Every \(everyXHours) hours", value: $everyXHours, in: 1...12)
                    case .timesADay:
                        Stepper("\(timesADay) times a day", value: $timesADay, in: 1...12)
                    }
                }

                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Set End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

            }
            .navigationTitle(isHealthKitTracked ? title : "Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                if healthKitMapping != nil {
                    healthKitConnected = await healthKitService.isConnected(buildHabit())
                }
            }
        }
    }

    /// Builds the `Habit` this form currently represents, without saving —
    /// shared by `save()` and the HealthKit connection-status check, since
    /// both need a real `Habit` value to resolve against
    /// `HealthKitTypeMapping` (which reads `isHealthKitTracked` +
    /// `sourceTemplateID` off the habit itself, not the form's raw state).
    private func buildHabit() -> Habit {
        let repeatMode: RepeatMode
        switch repeatModeKind {
        case .daily: repeatMode = .daily
        case .specificDays: repeatMode = .specificDays(specificDays)
        case .timesPerWeek: repeatMode = .timesPerWeek(timesPerWeek)
        case .everyXDays: repeatMode = .everyXDays(everyXDays)
        }

        let timeMode: TimeMode
        switch timeModeKind {
        case .none: timeMode = .none
        case .fixedTime: timeMode = .fixedTime(fixedTime)
        case .everyXHours: timeMode = .everyXHours(everyXHours)
        case .timesADay: timeMode = .timesADay(timesADay)
        }

        return Habit(
            id: habitID,
            title: title,
            category: category,
            isHealthKitTracked: isHealthKitTracked,
            sourceTemplateID: sourceTemplateID,
            iconSystemName: iconSystemName,
            color: color,
            goal: goal,
            unit: unit,
            step: step,
            repeatMode: repeatMode,
            timeMode: timeMode,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            notificationsEnabled: notificationsEnabled,
            remindersAppSyncEnabled: remindersAppSyncEnabled,
            calendarSyncEnabled: calendarSyncEnabled,
            isArchived: isArchived
        )
    }

    private func save() async {
        let habit = buildHabit()
        let isNewHealthKitHabit = isCreatingNew && healthKitMapping != nil
        try? await habitRepository.save(habit)
        await HabitNotificationScheduler.reschedule(for: habit, globalNotificationsEnabled: globalNotificationsEnabled)
        if isNewHealthKitHabit {
            await healthKitService.requestAuthorization(for: habit)
        }
        onSave()
    }
}

#Preview("Create") {
    HabitFormView(
        template: HabitTemplate(id: "drink-water", title: "Drink Water", category: .good, iconSystemName: "drop.fill", isHealthKitTracked: true, goal: 8, unit: .glasses, step: 1),
        onSave: {}
    )
    .environment(\.habitRepository, InMemoryHabitRepository())
}

#Preview("Edit") {
    HabitFormView(
        existingHabit: Habit(title: "Read a Book", category: .good, iconSystemName: "book.fill", goal: 20, unit: .minutes, step: 5),
        onSave: {}
    )
    .environment(\.habitRepository, InMemoryHabitRepository())
}
