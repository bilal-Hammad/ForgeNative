import Foundation

/// The suggested-habit catalog shown in the category-detail browser
/// (APP_REDESIGN_SPEC.md §5), ported from the RN app's real
/// `src/templates/seed.ts` + `healthTemplates.ts` content — not placeholder
/// data. This is a representative subset of the ~150 templates in the
/// original app, organized into the sections agreed for this phase; the
/// remaining long tail of templates is a content-porting pass, not an
/// architecture one, and can follow once this structure is confirmed.
///
/// Every template's `goal`/`unit`/`step` below is reasoned per-habit from
/// the real RN data's own `defaultGoal`/`unit`/`step` values where present
/// (cross-referenced by id), not one generic default applied to everything.
/// Where the RN data had no goal at all (a plain daily habit like "Make
/// Your Bed"), the default is goal 1 / count / step 1, matching that exact
/// example from the naming-audit discussion.
///
/// Two RN naming-audit renames applied here (the other three confirmed
/// renames — Stretch, Learn New Words, Limit Salt — were never part of this
/// ported subset to begin with, so there's nothing to rename; flagged
/// separately as net-new content not yet added, not silently skipped):
/// - `steps-10k` "10,000 Steps" → "Steps", goal 10000 (was baked into the
///   name; also happens to make it a non-duplicate of the RN app's own
///   already-correctly-named `hk-steps` "Steps" entry, which was never
///   separately ported here).
/// - `sleep` "Sleep 8 Hours" → "Sleep", goal 8.
/// `read-book`'s goal/step (20 min) folds in the RN app's separate
/// "Read 20 minutes" (`read-20`) legacy entry rather than porting both as
/// near-duplicates — same real-world habit, same values.
///
/// SF Symbol names below are chosen from confident, long-standing symbols;
/// a few less-common ones (e.g. `mouth`) should be spot-checked in Xcode's
/// SF Symbols picker during QA since they can't be rendered/verified here.
enum TemplateCatalog {
    static let sections: [TemplateSection] = [

        // MARK: - Good

        TemplateSection(
            id: "good-health-fitness",
            category: .good,
            displayName: "Health & Fitness",
            tier: .free,
            templates: [
                HabitTemplate(id: "drink-water", title: "Drink Water", category: .good, iconSystemName: "drop.fill", isHealthKitTracked: true, goal: 8, unit: .glasses, step: 1),
                HabitTemplate(id: "eat-healthy", title: "Eat a Healthy Meal", category: .good, iconSystemName: "fork.knife", goal: 3, unit: .count, step: 1),
                // "Cold Shower"/"Vitamins" were previously tagged isHealthKitTracked, but
                // there's no real HealthKit type for either: no cold-shower metric exists
                // at all, and HealthKit's vitamin types are per-specific-vitamin-with-dose
                // (e.g. vitamin C in mg), not a fit for a generic "took vitamins" habit.
                // Manual habits now — no HealthKit connection implied, so the pink badge
                // doesn't promise a sync that was never real.
                HabitTemplate(id: "cold-shower", title: "Take a Cold Shower", category: .good, iconSystemName: "snowflake", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "vitamins", title: "Take Vitamins", category: .good, iconSystemName: "pills.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "walk", title: "Go for a Walk", category: .good, iconSystemName: "figure.walk", goal: 30, unit: .minutes, step: 5),
                HabitTemplate(id: "run", title: "Run", category: .good, iconSystemName: "figure.run", isHealthKitTracked: true, goal: 20, unit: .minutes, step: 5),
                HabitTemplate(id: "cycling", title: "Cycling", category: .good, iconSystemName: "bicycle", isHealthKitTracked: true, goal: 30, unit: .minutes, step: 10),
                HabitTemplate(id: "swim", title: "Swimming", category: .good, iconSystemName: "figure.pool.swim", isHealthKitTracked: true, goal: 30, unit: .minutes, step: 15),
                HabitTemplate(id: "yoga", title: "Yoga", category: .good, iconSystemName: "figure.yoga", isHealthKitTracked: true, goal: 20, unit: .minutes, step: 5),
                HabitTemplate(id: "workout", title: "Workout", category: .good, iconSystemName: "figure.strengthtraining.traditional", isHealthKitTracked: true, goal: 30, unit: .minutes, step: 5),
                HabitTemplate(id: "steps-10k", title: "Steps", category: .good, iconSystemName: "shoeprints.fill", isHealthKitTracked: true, goal: 10000, unit: .steps, step: 1000),
                HabitTemplate(id: "sleep", title: "Sleep", category: .good, iconSystemName: "bed.double.fill", isHealthKitTracked: true, goal: 8, unit: .hours, step: 1),
                HabitTemplate(id: "floss", title: "Floss Teeth", category: .good, iconSystemName: "mouth", goal: 1, unit: .count, step: 1),
                // New this pass, real HealthKit types confirmed against the
                // installed SDK's HKTypeIdentifiers.h (not guessed) — see
                // `HealthKitTypeMapping`'s doc comment for the full
                // per-type reasoning, including the handful of habits that
                // were investigated but have no real HealthKit type at all
                // (flossing above, plus "pelvic floor"/"sleep diary" — not
                // added as templates for that reason).
                HabitTemplate(id: "hk-handwashing", title: "Wash Your Hands", category: .good, iconSystemName: "hands.and.sparkles.fill", isHealthKitTracked: true, goal: 5, unit: .count, step: 1),
                HabitTemplate(id: "hk-basketball", title: "Basketball", category: .good, iconSystemName: "basketball.fill", isHealthKitTracked: true, goal: 30, unit: .minutes, step: 10),
                // No literal "Aerobics" HKWorkoutActivityType exists — mapped to
                // `.mixedCardio` (Apple's own successor to "Mixed Metabolic Cardio
                // Training"), the closest real match. See `HealthKitTypeMapping`.
                HabitTemplate(id: "hk-aerobic", title: "Aerobic Training", category: .good, iconSystemName: "figure.mixed.cardio", isHealthKitTracked: true, goal: 20, unit: .minutes, step: 5),
                // The six templates below are read-only auto-tracking (no
                // write-back — Forge's completion UI has no real value entry
                // for a vital reading, and reproductive-health data stays
                // read-only regardless as a conservative default). Each is a
                // "did you log a reading today" habit (goal 1), not a
                // magnitude/target-value habit — this app doesn't make body-
                // composition or vitals target judgments.
                HabitTemplate(id: "hk-blood-pressure", title: "Blood Pressure", category: .good, iconSystemName: "waveform.path.ecg", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-weight", title: "Weight", category: .good, iconSystemName: "scalemass.fill", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-lean-mass", title: "Lean Body Mass", category: .good, iconSystemName: "figure.arms.open", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-body-fat", title: "Body Fat %", category: .good, iconSystemName: "percent", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-height", title: "Height", category: .good, iconSystemName: "ruler.fill", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-blood-glucose", title: "Blood Glucose", category: .good, iconSystemName: "cross.vial.fill", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                // Reproductive health — read-only regardless of write-back
                // feasibility, per `HealthKitTypeMapping`'s doc comment.
                HabitTemplate(id: "hk-menstrual", title: "Menstrual Log", category: .good, iconSystemName: "calendar.circle.fill", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-contraceptive-pill", title: "Contraceptive Pill", category: .good, iconSystemName: "pills.fill", isHealthKitTracked: true, goal: 1, unit: .count, step: 1),
            ]
        ),
        TemplateSection(
            id: "good-mindfulness",
            category: .good,
            displayName: "Mindfulness",
            tier: .free,
            templates: [
                HabitTemplate(id: "meditation", title: "Meditate", category: .good, iconSystemName: "brain.head.profile", goal: 10, unit: .minutes, step: 5),
                HabitTemplate(id: "gratitude", title: "Gratitude", category: .good, iconSystemName: "heart.text.square.fill", goal: 3, unit: .count, step: 1),
                HabitTemplate(id: "journal", title: "Journal Entry", category: .good, iconSystemName: "pencil.and.outline", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "breathe", title: "Breathing Exercise", category: .good, iconSystemName: "wind", goal: 5, unit: .minutes, step: 1),
                HabitTemplate(id: "pray", title: "Pray", category: .good, iconSystemName: "hands.sparkles.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "reflect-day", title: "Reflect on My Day", category: .good, iconSystemName: "text.book.closed.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-mindful", title: "Mindful Session", category: .good, iconSystemName: "figure.mind.and.body", isHealthKitTracked: true, goal: 10, unit: .minutes, step: 5),
                HabitTemplate(id: "listen-music", title: "Listen to Music", category: .good, iconSystemName: "music.note", goal: 1, unit: .count, step: 1),
            ]
        ),
        TemplateSection(
            id: "good-productivity",
            category: .good,
            displayName: "Productivity",
            tier: .free,
            templates: [
                HabitTemplate(id: "make-your-bed", title: "Make Your Bed", category: .good, iconSystemName: "bed.double", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "wake-up-time", title: "Wake Up on Time", category: .good, iconSystemName: "sunrise.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "clean-email", title: "Clean Up Email", category: .good, iconSystemName: "envelope.badge", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "plan-tomorrow", title: "Plan Tomorrow", category: .good, iconSystemName: "calendar.badge.checkmark", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "deep-work", title: "Deep Work", category: .good, iconSystemName: "laptopcomputer", goal: 90, unit: .minutes, step: 30),
                HabitTemplate(id: "no-phone", title: "No-Phone Hour", category: .good, iconSystemName: "iphone.slash", goal: 60, unit: .minutes, step: 15),
                HabitTemplate(id: "digital-detox", title: "Digital Detox Hour", category: .good, iconSystemName: "leaf.fill", goal: 60, unit: .minutes, step: 15),
            ]
        ),
        TemplateSection(
            id: "good-learning",
            category: .good,
            displayName: "Learning",
            tier: .free,
            templates: [
                HabitTemplate(id: "read-book", title: "Read a Book", category: .good, iconSystemName: "book.fill", goal: 20, unit: .minutes, step: 5),
                HabitTemplate(id: "learn-language", title: "Learn a Language", category: .good, iconSystemName: "character.bubble.fill", goal: 20, unit: .minutes, step: 5),
                HabitTemplate(id: "play-instrument", title: "Play Instrument", category: .good, iconSystemName: "guitars.fill", goal: 30, unit: .minutes, step: 5),
                HabitTemplate(id: "podcast", title: "Listen to a Podcast", category: .good, iconSystemName: "mic.fill", goal: 30, unit: .minutes, step: 10),
                HabitTemplate(id: "audiobook", title: "Listen to an Audiobook", category: .good, iconSystemName: "headphones", goal: 30, unit: .minutes, step: 10),
                HabitTemplate(id: "coding", title: "Coding Practice", category: .good, iconSystemName: "chevron.left.forwardslash.chevron.right", goal: 30, unit: .minutes, step: 5),
                HabitTemplate(id: "study-session", title: "Study Session", category: .good, iconSystemName: "graduationcap.fill", goal: 45, unit: .minutes, step: 5),
            ]
        ),
        TemplateSection(
            id: "good-social",
            category: .good,
            displayName: "Social",
            tier: .free,
            templates: [
                HabitTemplate(id: "call-parents", title: "Call Parents", category: .good, iconSystemName: "phone.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "meet-friend", title: "Meet a Friend", category: .good, iconSystemName: "person.2.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "give-compliment", title: "Give a Compliment", category: .good, iconSystemName: "hand.thumbsup.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "help-someone", title: "Help Someone", category: .good, iconSystemName: "hands.sparkles", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "start-conversation", title: "Start a Conversation", category: .good, iconSystemName: "bubble.left.and.bubble.right.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
        // Relocated here (not a default section) per the decision to make it
        // a premium suggested section rather than drop it or fold it into
        // Mindfulness — content unchanged from the original app.
        TemplateSection(
            id: "good-islamic",
            category: .good,
            displayName: "Islamic",
            tier: .premium,
            templates: [
                HabitTemplate(id: "five-prayers", title: "الصلوات الخمس", category: .good, iconSystemName: "building.columns.fill", goal: 5, unit: .count, step: 1),
                HabitTemplate(id: "read-quran", title: "قراءة القرآن", category: .good, iconSystemName: "book.closed.fill", goal: 20, unit: .minutes, step: 5),
                HabitTemplate(id: "morning-adhkar", title: "الأذكار الصباحية", category: .good, iconSystemName: "sunrise.fill", goal: 10, unit: .minutes, step: 1),
                HabitTemplate(id: "evening-adhkar", title: "الأذكار المسائية", category: .good, iconSystemName: "moon.stars.fill", goal: 10, unit: .minutes, step: 1),
                HabitTemplate(id: "istighfar", title: "الاستغفار", category: .good, iconSystemName: "circle.grid.cross.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "night-prayer", title: "قيام الليل", category: .good, iconSystemName: "moon.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "mon-thu-fast", title: "صيام الإثنين والخميس", category: .good, iconSystemName: "moon.zzz.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "daily-sadaqah", title: "الصدقة اليومية", category: .good, iconSystemName: "gift.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "tasbih", title: "تلاوة الأذكار", category: .good, iconSystemName: "circle.grid.cross", goal: 1, unit: .count, step: 1),
            ]
        ),

        // MARK: - Bad

        TemplateSection(
            id: "bad-screen-time",
            category: .bad,
            displayName: "Screen Time",
            tier: .free,
            templates: [
                HabitTemplate(id: "less-social-media", title: "Less Social Media", category: .bad, iconSystemName: "iphone", goal: 30, unit: .minutes, step: 10),
                HabitTemplate(id: "less-tv", title: "Less TV", category: .bad, iconSystemName: "tv", goal: 60, unit: .minutes, step: 30),
                HabitTemplate(id: "dont-play-games", title: "Don't Play Games", category: .bad, iconSystemName: "gamecontroller", goal: 1, unit: .count, step: 1),
            ]
        ),
        TemplateSection(
            id: "bad-substances",
            category: .bad,
            displayName: "Substances",
            tier: .free,
            templates: [
                HabitTemplate(id: "no-alcohol", title: "No Alcohol", category: .bad, iconSystemName: "wineglass", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "no-smoking", title: "Quit Smoking / Vaping", category: .bad, iconSystemName: "smoke", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "hk-coffee", title: "Limit Coffee", category: .bad, iconSystemName: "cup.and.saucer.fill", isHealthKitTracked: true, goal: 400, unit: .milligrams, step: 50),
                // HealthKit's real matching type is `numberOfAlcoholicBeverages` — a plain
                // drink count, not grams of pure alcohol (there's no such HK quantity type).
                // goal: 2 matches common daily moderate-drinking guidance (e.g. CDC's "up to
                // 2 drinks/day"), replacing the old grams-based "14" (which read like a
                // weekly-units guideline value, but was being evaluated as a daily limit).
                HabitTemplate(id: "hk-alcohol", title: "Limit Alcoholic Drinks", category: .bad, iconSystemName: "wineglass.fill", isHealthKitTracked: true, goal: 2, unit: .count, step: 1),
                HabitTemplate(id: "no-sugar", title: "No Sugar", category: .bad, iconSystemName: "cube.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
        // No corresponding content exists in the current app under Bad for a
        // "Spending" theme (save-money/pay-bills etc. are Good/To-Do content,
        // not Bad) — left structurally present but empty rather than
        // inventing new habits; flagged for a real decision later.
        TemplateSection(
            id: "bad-spending",
            category: .bad,
            displayName: "Spending",
            tier: .free,
            templates: []
        ),
        TemplateSection(
            id: "bad-procrastination",
            category: .bad,
            displayName: "Procrastination",
            tier: .free,
            templates: [
                HabitTemplate(id: "dont-procrastinate", title: "Don't Procrastinate", category: .bad, iconSystemName: "hourglass", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "dont-complain", title: "Don't Complain", category: .bad, iconSystemName: "face.dashed", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "dont-get-angry", title: "Don't Get Angry", category: .bad, iconSystemName: "flame", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "dont-swear", title: "Don't Swear", category: .bad, iconSystemName: "exclamationmark.bubble", goal: 1, unit: .count, step: 1),
            ]
        ),

        // MARK: - To-Do
        // Renamed from the spec's proposed "Daily Tasks" to "Admin & Legal" —
        // the actual existing To-Do content is all periodic life-admin tasks
        // (file taxes, renew documents), never literally daily, so the
        // original name didn't fit what's actually here. Every To-Do
        // template in the real RN data is a one-off task with no unit/goal
        // — goal 1 / count / step 1 throughout, matching that.

        TemplateSection(
            id: "todo-admin-legal",
            category: .todo,
            displayName: "Admin & Legal",
            tier: .free,
            templates: [
                HabitTemplate(id: "file-taxes", title: "File Taxes", category: .todo, iconSystemName: "building.columns", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "renew-passport", title: "Renew Passport", category: .todo, iconSystemName: "person.text.rectangle", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "renew-license", title: "Renew Driver's License", category: .todo, iconSystemName: "person.text.rectangle.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "check-insurance", title: "Check Insurance", category: .todo, iconSystemName: "checklist", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "update-passwords", title: "Update Passwords", category: .todo, iconSystemName: "lock.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
        TemplateSection(
            id: "todo-chores",
            category: .todo,
            displayName: "Chores",
            tier: .free,
            templates: [
                HabitTemplate(id: "clean-house", title: "Deep Clean House", category: .todo, iconSystemName: "house.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "car-maintenance", title: "Car Maintenance", category: .todo, iconSystemName: "car.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "optimize-bedroom", title: "Optimize Bedroom for Sleep", category: .todo, iconSystemName: "bed.double.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
        TemplateSection(
            id: "todo-errands",
            category: .todo,
            displayName: "Errands",
            tier: .free,
            templates: [
                HabitTemplate(id: "buy-gift", title: "Buy a Gift", category: .todo, iconSystemName: "gift.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "print-documents", title: "Print Documents", category: .todo, iconSystemName: "printer.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "doctor-appt", title: "Book Doctor Appt.", category: .todo, iconSystemName: "stethoscope", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "health-equipment", title: "Buy Health Equipment", category: .todo, iconSystemName: "dumbbell.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
        TemplateSection(
            id: "todo-work",
            category: .todo,
            displayName: "Work",
            tier: .free,
            templates: [
                HabitTemplate(id: "update-resume", title: "Update Resume", category: .todo, iconSystemName: "doc.text.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "schedule-meeting", title: "Schedule a Meeting", category: .todo, iconSystemName: "calendar", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "set-up-budget", title: "Set Up a Budget", category: .todo, iconSystemName: "chart.pie.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "automate-finances", title: "Automate Your Finances", category: .todo, iconSystemName: "banknote.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
    ]

    static func sections(for category: HabitCategory) -> [TemplateSection] {
        sections.filter { $0.category == category }
    }

    /// Default active section IDs for a category: free-tier sections, in
    /// catalog order. Shared by `InMemoryTemplateSectionRepository` (what
    /// "Reset" restores) and `EditSectionsView` (whether "Reset" has
    /// anything to actually do) — one source of truth so the two can't drift.
    static func defaultSectionIDs(for category: HabitCategory) -> [String] {
        sections(for: category)
            .filter { $0.tier == .free }
            .map(\.id)
    }
}
