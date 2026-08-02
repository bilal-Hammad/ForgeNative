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
        // MARK: Islamic pack (P1 Phase 7) — English-first, four thematic
        // sub-groups rather than one flat list, all premium (unlocked by the
        // Forge Premium subscription OR the standalone Islamic Pack
        // non-consumable — see ProductIdentifiers.packProductID, which maps
        // every `good-islamic-*` id to the pack). Replaced the old Arabic-only
        // `good-islamic` section. The 5 Fard prayers lead Group 1 as the
        // suggested starter subset.
        //
        // Group 1 — Prayers: prayer-window habits (`.prayerRelative`), so each
        // gets the strict completion window + auto-miss lock from Phase 3. The
        // offset is a display/notification hint; the completion window is the
        // anchor prayer's window regardless (a "before"/"after" sunnah still
        // completes within that prayer's window). 12 of these templates (5
        // Fard + 5 Sunnah + Witr + Qiyam al-Layl) get restricted, bucket-
        // specific editing rules in `HabitFormView`/`CategoryDetailView` — see
        // `CorePrayerTemplate`. The 5 "Adhkar after <prayer>" templates below
        // deliberately stay fully editable/unrestricted.
        TemplateSection(
            id: "good-islamic-prayers",
            category: .good,
            displayName: "Prayers",
            tier: .premium,
            templates: [
                HabitTemplate(id: "islamic-fajr-fard", title: "Fajr Prayer", category: .good, iconSystemName: "sunrise.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 0))),
                HabitTemplate(id: "islamic-dhuhr-fard", title: "Dhuhr Prayer", category: .good, iconSystemName: "sun.max.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .dhuhr, offsetMinutes: 0))),
                HabitTemplate(id: "islamic-asr-fard", title: "Asr Prayer", category: .good, iconSystemName: "sun.min.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .asr, offsetMinutes: 0))),
                HabitTemplate(id: "islamic-maghrib-fard", title: "Maghrib Prayer", category: .good, iconSystemName: "sunset.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .maghrib, offsetMinutes: 0))),
                HabitTemplate(id: "islamic-isha-fard", title: "Isha Prayer", category: .good, iconSystemName: "moon.stars.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .isha, offsetMinutes: 0))),
                HabitTemplate(id: "islamic-sunnah-before-fajr", title: "Sunnah before Fajr (2 rak'ah)", category: .good, iconSystemName: "moon.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: -15))),
                // Qabliyah Dhuhr — genuinely two sets of 2 rak'ah; goal 4 /
                // step 2 is now fully fixed under the hood (Goal + Increment
                // both hidden from the form, same as the binary bucket) —
                // needs exactly 2 taps to complete. See CorePrayerTemplate
                // (.qabliyahDhuhr bucket).
                HabitTemplate(id: "islamic-sunnah-before-dhuhr", title: "Sunnah before Dhuhr (4 rak'ah)", category: .good, iconSystemName: "moon.fill", goal: 4, step: 2, timeMode: .prayerRelative(PrayerAnchor(prayer: .dhuhr, offsetMinutes: -15))),
                HabitTemplate(id: "islamic-sunnah-after-dhuhr", title: "Sunnah after Dhuhr (2 rak'ah)", category: .good, iconSystemName: "moon.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .dhuhr, offsetMinutes: 25))),
                HabitTemplate(id: "islamic-sunnah-after-maghrib", title: "Sunnah after Maghrib (2 rak'ah)", category: .good, iconSystemName: "moon.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .maghrib, offsetMinutes: 15))),
                HabitTemplate(id: "islamic-sunnah-after-isha", title: "Sunnah after Isha (2 rak'ah)", category: .good, iconSystemName: "moon.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .isha, offsetMinutes: 15))),
                // Witr — odd-only rak'ah count, no Increment field in the
                // form at all: `step` is kept in sync with `goal`
                // programmatically by CorePrayerTemplate.enforce (never a
                // separate user-facing value), so a single tap always
                // completes it regardless of the configured goal. Seed
                // goal 1 (the minimum valid Witr) / step 1 to match — this
                // raw seed value never actually survives past the first
                // save (enforce() always recomputes it), kept in sync here
                // purely for a future reader's clarity. See
                // CorePrayerTemplate (.witrLike bucket).
                HabitTemplate(id: "islamic-witr", title: "Witr Prayer", category: .good, iconSystemName: "moon.circle.fill", goal: 1, step: 1, timeMode: .prayerRelative(PrayerAnchor(prayer: .isha, offsetMinutes: 30))),
                // Qiyam al-Layl (new) — even-only rak'ah count, Increment
                // constrained to a 2-or-4 segmented picker in the form.
                // Anchored to Isha like Witr — `PrayerWindowResolver` keys a
                // habit's completion window purely on `anchor.prayer`, not
                // the offset, so this automatically reuses the exact same
                // Isha→next-day-Fajr cross-midnight window already built for
                // Qiyam al-layl (see PrayerWindowResolver's own doc comment)
                // — no new window logic needed. `offsetMinutes: 60` (an hour
                // after Isha, later than Witr's +30) is a judgment call for
                // display/notification purposes only; it doesn't affect the
                // window. See CorePrayerTemplate (.qiyam bucket).
                HabitTemplate(id: "islamic-qiyam", title: "Qiyam al-Layl", category: .good, iconSystemName: "star.and.crescent.fill", goal: 2, step: 2, timeMode: .prayerRelative(PrayerAnchor(prayer: .isha, offsetMinutes: 60))),
                HabitTemplate(id: "islamic-dhikr-after-fajr", title: "Adhkar after Fajr", category: .good, iconSystemName: "hands.sparkles.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .fajr, offsetMinutes: 5))),
                HabitTemplate(id: "islamic-dhikr-after-dhuhr", title: "Adhkar after Dhuhr", category: .good, iconSystemName: "hands.sparkles.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .dhuhr, offsetMinutes: 10))),
                HabitTemplate(id: "islamic-dhikr-after-asr", title: "Adhkar after Asr", category: .good, iconSystemName: "hands.sparkles.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .asr, offsetMinutes: 5))),
                HabitTemplate(id: "islamic-dhikr-after-maghrib", title: "Adhkar after Maghrib", category: .good, iconSystemName: "hands.sparkles.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .maghrib, offsetMinutes: 10))),
                HabitTemplate(id: "islamic-dhikr-after-isha", title: "Adhkar after Isha", category: .good, iconSystemName: "hands.sparkles.fill", timeMode: .prayerRelative(PrayerAnchor(prayer: .isha, offsetMinutes: 10))),
            ]
        ),
        // Group 2 — Dhikr & Tasbih: counter habits (Phase 6) — `.count` with a
        // classic tasbih goal, tap-to-increment with the selection-tick haptic.
        TemplateSection(
            id: "good-islamic-dhikr",
            category: .good,
            displayName: "Dhikr & Tasbih",
            tier: .premium,
            templates: [
                HabitTemplate(id: "islamic-tasbih-subhanallah", title: "SubhanAllah", category: .good, iconSystemName: "circle.grid.cross.fill", goal: 33, unit: .count, step: 1),
                HabitTemplate(id: "islamic-tasbih-alhamdulillah", title: "Alhamdulillah", category: .good, iconSystemName: "circle.grid.cross.fill", goal: 33, unit: .count, step: 1),
                HabitTemplate(id: "islamic-tasbih-allahuakbar", title: "Allahu Akbar", category: .good, iconSystemName: "circle.grid.cross.fill", goal: 33, unit: .count, step: 1),
                HabitTemplate(id: "islamic-tasbih-istighfar", title: "Istighfar (Astaghfirullah)", category: .good, iconSystemName: "circle.grid.cross.fill", goal: 100, unit: .count, step: 1),
                HabitTemplate(id: "islamic-tasbih-salawat", title: "Salawat upon the Prophet ﷺ", category: .good, iconSystemName: "circle.grid.cross.fill", goal: 10, unit: .count, step: 1),
            ]
        ),
        // Group 3 — Quran, Character & General Adhkar: plain daily check-off
        // habits (Type C) — no special mechanic, reuses existing habit types.
        TemplateSection(
            id: "good-islamic-quran-character",
            category: .good,
            displayName: "Quran & Character",
            tier: .premium,
            templates: [
                HabitTemplate(id: "islamic-read-quran", title: "Read Qur'an", category: .good, iconSystemName: "book.closed.fill", goal: 15, unit: .minutes, step: 5),
                HabitTemplate(id: "islamic-morning-adhkar", title: "Morning Adhkar", category: .good, iconSystemName: "sunrise.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-evening-adhkar", title: "Evening Adhkar", category: .good, iconSystemName: "sunset.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-sleep-adhkar", title: "Adhkar before Sleep", category: .good, iconSystemName: "moon.zzz.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-waking-adhkar", title: "Adhkar upon Waking", category: .good, iconSystemName: "sun.horizon.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-ayat-al-kursi", title: "Recite Ayat al-Kursi", category: .good, iconSystemName: "sparkles", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-three-quls", title: "Recite the Three Quls", category: .good, iconSystemName: "book.closed.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-honor-parents", title: "Honor Your Parents", category: .good, iconSystemName: "heart.circle.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-family-ties", title: "Maintain Family Ties", category: .good, iconSystemName: "person.2.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-sadaqah", title: "Give in Charity (Sadaqah)", category: .good, iconSystemName: "gift.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-spread-salam", title: "Spread Salam", category: .good, iconSystemName: "hand.raised.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-visit-sick", title: "Visit the Sick", category: .good, iconSystemName: "cross.case.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-guard-tongue", title: "Guard Your Tongue", category: .good, iconSystemName: "bubble.left.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-control-anger", title: "Control Your Anger", category: .good, iconSystemName: "flame.fill", goal: 1, unit: .count, step: 1),
                HabitTemplate(id: "islamic-forgive", title: "Forgive Others", category: .good, iconSystemName: "heart.fill", goal: 1, unit: .count, step: 1),
            ]
        ),
        // Group 4 — Weekly: existing "specific days" repeat mode (Type E) — no
        // new engineering. Day convention 0=Sun…6=Sat (see RepeatMode).
        TemplateSection(
            id: "good-islamic-weekly",
            category: .good,
            displayName: "Weekly Practices",
            tier: .premium,
            templates: [
                HabitTemplate(id: "islamic-surah-al-kahf", title: "Surah Al-Kahf (Friday)", category: .good, iconSystemName: "book.closed.fill", repeatMode: .specificDays([5])),
                HabitTemplate(id: "islamic-friday-salawat", title: "Increased Salawat (Friday)", category: .good, iconSystemName: "hands.sparkles.fill", repeatMode: .specificDays([5])),
                HabitTemplate(id: "islamic-jumuah-early", title: "Attend Jumu'ah Early", category: .good, iconSystemName: "person.3.fill", repeatMode: .specificDays([5])),
                HabitTemplate(id: "islamic-jumuah-ghusl", title: "Ghusl for Jumu'ah", category: .good, iconSystemName: "drop.fill", repeatMode: .specificDays([5])),
                HabitTemplate(id: "islamic-mon-thu-fast", title: "Fast Monday & Thursday", category: .good, iconSystemName: "moon.zzz.fill", repeatMode: .specificDays([1, 4])),
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

    /// Flat lookup of any built-in template by its id — used by
    /// `CorePrayerTemplate.enforce` to force the canonical (unrenameable)
    /// title of the 11 core prayer templates. Returns `nil` for a
    /// user-created custom template (those live in per-user config, not here).
    static func template(withID id: String) -> HabitTemplate? {
        for section in sections {
            if let match = section.templates.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
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
