# App Redesign Spec — Swift Rewrite, Apple-Native Direction

Source: user requirements dictated with 4 reference screenshots (Apple Fitness weekly ring strip,
Apple Fitness tab bar, Apple Fitness Summary page, Apple Workout "Add Workout" alphabetical list,
Apple Fitness toolbar with search/add/•••, and the app's own current Good/Bad/To Do category list).
This spec is the working requirements doc for Phase 1+ of the Swift rewrite (feeds off
SWIFT_REWRITE_INVENTORY.md from Phase 0).

Every open design decision below is marked **[DEFAULT PROPOSED — CONFIRM OR CHANGE]**. These are my
best-guess sensible defaults, not final decisions — flag anything you want changed before this goes
to the coding agent.

---

## 1. Home page — top weekly calendar strip

Add a 7-day strip (S M T W T F S) at the top of the Home page, current day highlighted, tappable to
view that day's detail. **Footprint must stay identical in size** to the previous rings-based version
— this is a visual swap only, not a layout change (no reflow of the rest of Home).

**[RESOLVED — supersedes the earlier ring-mapping proposal below]** Rings replaced with a
**three connected-lines** design: one horizontal track per category (Good / Bad / To-Do), each with
a small dot per day. A dot is filled solid in the category's color when that category was 100%
complete that day, hollow/outlined when the day occurred but wasn't complete, and faint/empty for
future days (matching the existing disabled-future-day behavior). Consecutive days that are both
complete for a category get a solid connecting line between their dots — this is what visually forms
a "streak" line the longer it runs. No connector is drawn across an incomplete or future day.
Category colors: Good = green, Bad = coral, To-Do = blue, one small colored dot + label to the left
of each track for legend. Selected day keeps a subtle vertical highlight band behind its column
(spanning all three tracks), independent of which day is visually bold as "today" — same
selected-vs-today separation already resolved below. Mockup reference saved as a widget/component
for reuse (flagged as a candidate for a future WidgetKit Home Screen widget too, not just the in-app
strip — not scoped for this pass, just noting the design is reusable there).

~~**[SUPERSEDED — was DEFAULT PROPOSED]** Ring mapping: since Apple's 3 rings are Move/Exercise/Stand,
and this app's core structure is 3 categories (Good / Bad / To-Do), map the 3 rings to outer/middle/
inner ring per category. Replaced by the connected-lines design above before implementation, so the
Apple Fitness ring-visual research pass (stroke width, ring gaps, >100% overflow behavior) is no
longer needed — the lines design has its own overflow non-issue since a day's dot is a binary
complete/not-complete state, not a percentage fill.~~

### Resolved — v2 visual revision (post-build feedback, supersedes the connected-dots version below)

After seeing the built connected-dots-and-lines version on-device, three changes:

1. **Removed the "Good"/"Bad"/"To-Do" text labels** entirely — no left-side legend text at all.
2. **Removed the per-row legend dot too** — no leading marker of any kind. Each category row is now
   a single continuous full-width bar (not discrete day-dots joined by connector lines), split into 7
   equal day-segments with a 1px gap between segments and rounded corners only on the outer ends.
   Segment color: pale tint of the category color when that day is not yet complete, full saturated
   category color when complete, muted neutral gray for future/disabled days (same disabled-tap
   behavior as before). Bar height ~8px per row.
3. **Height**: felt too tall against the original single-row rings strip — flattened to thin bars (not
   dots/circles) stacked with minimal gap so total height (header + 3 bars) approximates the original
   rings-strip footprint. Header row (day letters, today bold) sits directly above the three bars,
   columns aligned 1:1 with the day segments. Selected-day highlight band still spans the full height
   behind the selected column across all three bars.

Net result: three colored progress ribbons stacked tightly under the day-letter header, no text, no
node markers — color alone (pale vs. saturated) encodes daily completion per category, continuity of
the saturated color across days reads as a streak.

### Resolved — connected-lines build (implemented, screenshot-verified on-device)

Built and verified against the design above via actual simulator screenshots
(`xcrun simctl io ... screenshot`), not just launch/no-crash checks. Layout confirmed matching spec:
same footprint, date-only header, three labeled tracks, selection highlight spanning full height
behind the selected column across all three tracks.

- **Race-condition bug caught by screenshot, not assumed as rendering lag**: a habit already 3/3
  complete for today rendered as a hollow (incomplete) dot. Verified against the real SwiftData
  SQLite record (confirmed actually complete) before treating it as a timing fluke, then ruled out
  simple async delay with a longer-wait re-screenshot. Root cause: `WeeklyRingsPagerView` computes
  each week's rates against whichever `habits` array it's handed, but `HomeView` passes it down
  asynchronously — starts as `[]`, populated once `HomeView.reload()` resolves. If the view's own
  prefetch task won that race, it would compute and permanently cache rates against zero habits, and
  the cache-guard meant it would never refresh once the real list arrived. Fixed with
  `.onChange(of: habits)` to invalidate the cache and re-fetch on every habit-list change, including
  the first empty→populated transition. Confirmed fixed with a follow-up screenshot.
- **Colors**: Bad track uses a new coral/orange, deliberately distinct from the red
  `HabitCategory.accentColor` used elsewhere (rings, milestones) — documented in code as an
  intentional exception, not an inconsistency to fix later.

### Resolved — strip header, selection state, future days, tap-counter (implemented & verified)

- **Header**: only the selected day's specific date shows above the strip. The secondary
  smaller week-range line originally under it was removed entirely.
- **Selection highlight bug**: the highlighted pill was incorrectly keyed to `isToday` — there was
  no real "selected day" concept wired through (`selectedDate` wasn't even passed into
  `RingsStripView`). Fixed by threading `selectedDate` in as a real parameter and keying the
  highlight to it. Today's weekday letter stays bold as a separate, independent marker so today
  remains identifiable even when a different day is selected.
- **Future days**: reversed from the earlier "dimmed but still tappable" default — future days
  within the week are now `.disabled`, blocking `onSelectDay` from firing, not just dimmed visually.
- **Quantity-habit tap-counter bug**: taps on an already-complete quantity habit (count == goal)
  were still incrementing past the goal. `handleTap` now no-ops once `count >= goal`, and clamps the
  crossing tap with `min(count + step, goal)`. Fixed a related HealthKit write-back precision issue
  this exposed — it was writing the full `step` amount every tap even when the clamped local delta
  was smaller; it now writes the exact delta actually applied. Decision: no over-completion tracking
  (capping is the coherent choice given the ">100%" ring-overflow display is still an open item above,
  not a shipped feature) — extra taps past goal are full no-ops.

### Resolved — day-detail view, wider pager prefetch (build succeeded, tap-open needs manual on-device check)

- **`DayDetailView` sheet — superseded, replace with inline display (see below).**
  ~~Built as a sheet, opened on tap for any non-disabled day. Habits grouped by category, each showing
  its actual recorded state for that specific date via `fetchCompletions(for:)`.~~ After review,
  a separate sheet/page is the wrong pattern — replaced by showing the selected day inline on Home
  itself, see the new item directly below.

### Resolved — selected day now drives Home's own habit list inline (no separate detail page)

**[RESOLVED]** Removed the `DayDetailView` sheet approach entirely. Instead, Home's existing habit
list (the same list component already on the page) is driven by `selectedDate` rather than always
being hardcoded to today. Tapping a day in the strip updates `selectedDate`, and the list below
re-queries and re-renders in place to show that date's habits and their recorded completion state for
that date — no navigation, no separate screen.

- **Today selected**: list stays fully interactive as it already is today — tap-to-toggle, tap-to-
  increment quantity habits, etc.
- **A past day selected (this week or a previously-paged week)**: list is **read-only** — habit rows
  render but taps do nothing (no toggling, no incrementing). This preserves the earlier decision that
  viewing history shouldn't let you silently rewrite it, now just expressed as a display-mode switch
  on the same list rather than a separate page. **[CONFIRMED]** — user chose display-only over past-day
  editing when this was flagged.
- **[RESOLVED — extends read-only scope]** First build only locked tap-to-toggle/increment and left
  swipe actions (Edit/Archive/Delete) live regardless of selected day — flagged as a judgment call at
  the time since it wasn't explicitly specified. Now confirmed: swipe actions must be locked too on
  any non-today day, and the "+" add-habit entry point must also be disabled while viewing a past day
  (you shouldn't be able to retroactively add a habit "into" a past date). Read-only now means fully
  read-only — no toggle, no increment, no edit, no archive, no delete, no add — for any day that
  isn't today.
- **[RESOLVED — tap-to-select-day investigation, condensed]** Selecting a non-today day via tap did
  not work for many rounds, through three underlying bugs found and fixed in sequence: (1) a
  hit-testing bug where `.contentShape(Rectangle())` was ordered before `.frame(...)` in the modifier
  chain, producing a degenerate tap area on non-today cells; (2) a timezone bug where day `Date`
  values carried inconsistent UTC time-of-day components that could cross the local midnight boundary,
  making `isSelected`/`isViewingToday` compute against the wrong calendar day — fixed by forcing every
  date through `Calendar.current.startOfDay(for:)`; (3) a regression, later traced to a temporary
  diagnostic debug button's `.overlay` accidentally intercepting real taps on the Saturday column. The
  actual root cause tying all of it together: the strip's original architecture split each day into a
  non-interactive visual `.overlay` (header/bars) stacked on top of a separately-positioned button
  underneath, aligned only by both sides independently computing the same `columnWidth` — a fragile
  two-layer construction prone to exactly this class of bug. **Fixed for good** by rewriting the cell
  as a single `Button`/`ZStack` owning its full content (background + letter + bar segments), with
  `.frame()` → `.contentShape(Rectangle())` applied once to that one view — selected vs. unselected
  differ only in fill color, never in view structure (the correct, Apple-idiomatic single-reusable-
  view pattern). Confirmed fixed on real device: tapping a non-highlighted day now correctly moves the
  highlight. All temporary debug instrumentation (flash, print checkpoints, debug trigger buttons)
  removed after confirmation; full blow-by-blow archived in `CLAUDE.md` if ever needed again.
  Two smaller things surfaced during this investigation, tracked separately: an `xcodebuild`
  stale-recompilation gotcha (now guarded against with `touch` + build-log verification) and a
  Simulator limitation where synthetic taps never reach anything hosted inside `TabView(.page)` (real
  hardware required for this class of UI going forward). Also flagged but unresolved: a CoreData/
  SwiftData persistent-store creation race on fresh installs (`Application Support` directory missing
  at first launch, recovers via CoreData's own fallback) — possibly related to `visibleHabits.count=0`
  appearing on fresh launches; still needs its own investigation.
- **[RESOLVED]** Add-habit "+" button: was disabled + dimmed to 40% opacity on past days — changed to
  fully hidden/removed from view entirely when viewing anything but today, not just disabled.
- **[RESOLVED]** Large empty gap under the weekly strip: leftover `.frame(height: 78)` sized for the
  old rings design, not updated when the bar design landed at a shorter actual content height. Fixed
  to `.frame(height: 58)` matching the strip's real content height.
- Same two inherent limitations carry over from the sheet version: a habit created after the viewed
  date is correctly excluded; a habit that existed then but has since been deleted won't appear (no
  historical snapshot of deleted habits exists). Archived habits excluded too, consistent with Home's
  existing convention.
- **[RESOLVED]** Tap-to-switch-day interaction and interactive/read-only mode switch — confirmed
  working on real device as part of the tap-investigation closure above.
- **Pager prefetch widened**: the earlier fix only cached one neighboring week each way, so a fast
  multi-week backward flick could outrun it. Widened to a 4-week radius each side, and switched from
  one query per week to a single batched query covering only whatever's still missing in that radius
  (already-cached weeks skipped) — so repeated swiping only fetches the newly-uncovered edge instead
  of re-fetching the whole window. Confirmed as single-device query performance (no backend exists),
  matching the scope note above.
- **[RESOLVED — root cause found and fixed]** Swiping to a previous week or selecting a past day was
  noticeably slow (multi-second freeze on some swipes). Root cause found via `os_log`-based timing
  instrumented on both sides of the `@ModelActor` await boundary (Instruments/`xctrace` don't work in
  this sandboxed environment): the SwiftData queries themselves were fast (2.6–95.7ms) — the real cost
  (89–99.9% of the observed delay, up to ~2.4s) was Swift Concurrency's resumption of the calling task
  after the actor call returned. Traced to `WeeklyRingsPagerView`'s `ForEach` ranging over a fixed
  `minWeekOffset...0` span of **5201 elements** (~100 years back) — SwiftUI's post-body reconciliation
  of that huge identity-based collection is what ate the gap, confirmed by a falsification test
  (temporarily shrinking the range to 9 elements cut the worst gap ~6×).
  **Permanent fix (not the temporary test)**: rewrote the pager to Apple's windowed/recentering
  pattern (same technique Health/Calendar/Fitness use) — `TabView(.page)` now renders a constant 2–3
  relative-offset tags around a `centerWeekOffset` state variable instead of a fixed huge range;
  swiping to an edge tag recenters `centerWeekOffset` and snaps `pageSelection` back to the middle in
  an animation-disabled transaction (imperceptible, since the middle tag's content already matches).
  `minWeekOffset` is now computed dynamically from `habits.map(\.startDate).min()` instead of a fixed
  100-year constant — no arbitrary pre-history to page into; out-of-bounds tags simply aren't
  rendered, so boundary behavior is genuine native rubber-banding, no custom gesture-blocking code
  needed. Verified two ways: (1) real device screenshots/timing before/after: worst-case gap dropped
  from ~2.4s to smooth; (2) built a real `ForgeUITests` XCUITest target with actual touch-injected
  swipe gestures (Simulator mouse-drag has never registered as a page-swipe here) plus an isolated
  `-uiTesting` in-memory seed path (8 weeks of fake history, never touches real data) — automated
  swipe round-trip (back→back→forward→forward) confirmed correct movement and return. Kept the
  `ForgeUITests` target permanently as the project's first real gesture-regression test, so a future
  swipe/drag bug doesn't require another multi-round Simulator-limitation investigation from scratch.
  Full investigation log archived in `CLAUDE.md`.
- **Aside, not a bug**: a screenshot showed a habit's icon/text red with several solid-green days in a
  row — verified against real data before assuming a regression; it's genuine seeded history (~20
  backfilled days) from the Debug → "Seed Test History" tool used between sessions, correctly
  reflected by the strip.

## 2. Tab bar

Icon + label style matching Apple's convention (reference: Fitness app's Summary/Workout/Sharing
bar — icon on top, label below, active tab in a soft capsule). Confirmed tabs: **Home, Progress,
Profile**. This is largely already built as the native Liquid Glass `TabView` — apply the same
icon+label treatment there.

## 3. "Add habit" button placement

Floating "+" button on the Home page:
- Horizontal position: centered (mid-width of the screen), not corner-anchored.
- Vertical position: directly below the last added habit card in the list — not fixed to the
  bottom of the screen. It should move down as more habits get added.

## 4. Habit-creation flow — category picker redesign

**Rename/remove:** delete the word "Templates" everywhere in this flow's UI text.

**Category count change:** currently 4 categories (Good, Health, Bad, To Do) → reduce to **3**
(Good, Bad, To Do). The "Health" category is removed as its own top-level category. Habits that are
HealthKit-trackable (auto-tracked, no manual check-in) instead:
- Get placed into whichever of Good / Bad / To-Do fits them contextually (case-by-case judgment
  call — needs a pass to sort every currently-"Health"-categorized habit into the right one of the 3).
- Get a small Apple Health logo badge on the right side of their habit card, so the user can tell
  at a glance which habits auto-track via HealthKit vs. require manual logging.

**Remove:** the search icon from this top-level category picker page.

**Restyle:** the category picker page's current look (plain grouped list with chevrons, per the
existing app screenshot) should be redesigned to match Apple's visual conventions more closely —
rounded, card-based groupings rather than a plain settings-style list.

## 5. Inside a category (Good / Bad / To-Do detail page)

Style this after Apple's "Add Workout" list screen (reference screenshot): rounded dark cards, one
icon per item, grouped into labeled sections with a scrubber index on the right — **but replace the
A–Z alphabetical grouping with thematic "sections"** relevant to habits.

**[DEFAULT PROPOSED]** Section groupings per category (adjust freely):
- **Good:** Health & Fitness, Mindfulness, Productivity, Learning, Social
- **Bad:** Screen Time, Substances, Spending, Procrastination
- **To-Do:** Daily Tasks, Chores, Errands, Work

Icon style: match Apple's SF Symbols-based icon language (simple, filled, single-color glyphs) —
exact icon choices to be worked out per habit, prioritizing recognizability over literal copying.

**Top-right toolbar** on this page: search icon + "•••" menu (reference: Fitness app's
search/add/••• toolbar). Tapping "•••" opens two options:
- **Edit** — lets the user reorder sections, delete a section, add a custom section, or add a
  suggested section (with its bundled suggested habits) from a preset list.
- **Reset** — reverts section order/customizations back to default.

## 6. Progress page

**[RESOLVED — confirmed with research, supersedes the plain Apple-Fitness-card-mapping default below]**
User flagged two concerns when confirming this section: (1) the app is going to be a **paid** app, so
the Progress page should differentiate with genuinely premium-feeling analytics, not just a reskinned
Apple Fitness Summary page, and (2) the "Today's Rings" card (literal 3-ring Good/Bad/To-Do rings)
reads as a visual copy of Apple's Activity Rings, which is a legal/originality concern for a paid app
(same class of concern already resolved for Milestones in Section 11 — needs to be genuinely distinct,
not just re-colored).

**Competitive research on paid habit-tracker analytics** (Streaks, $4.99 one-time — Apple Health
integration, watch complications, weekly/monthly success-rate %; Habitify, $4.99/mo or $21.99/yr —
analytics dashboard breaking completion rate down **by day of week, by time of day, and by streak
length**, so users see exactly when they tend to fall off) shows the actual premium differentiator in
this category isn't prettier charts, it's **deeper behavioral analytics** most free apps don't bother
computing. Adopt this as Forge's premium angle:
- Add a **"Best day of week" / "Best time of day"** breakdown per habit and per category — this is
  Habitify's specific premium differentiator and directly answers "when do I actually fall off,"
  which a flat weekly bar chart doesn't.
- Add a **streak-length distribution** view (how many 7-day streaks vs. 30-day+ streaks a user has
  built historically), not just the single current-streak number.
- These become genuine premium-gated analytics per Section 10's monetization split (free tier gets
  the basic rings/streak/breakdown cards below; premium tier unlocks the day-of-week/time-of-day/
  streak-distribution views) — gives Section 10's "premium suggested sections" monetization a second,
  stronger pillar (premium *analytics*, not just premium *content*).

**Rings redesign — moves away from literal Apple rings entirely, consistent with Section 1's own
precedent.** Section 1's Home strip already replaced literal rings with flat colored bars/ribbons
specifically to avoid the Apple-copy look — the Progress page should follow the same visual language
for consistency, rather than reintroducing rings just here. Research into non-ring habit-progress
visualizations (GitHub-style contribution/heatmap graphs, streak-indicator grids, chart/trend-based
views) points to a **GitHub-style contribution heatmap** as the strongest fit: a grid of day-cells
shaded by completion intensity, per category or blended — visually distinct from Apple's circular
rings, well-established as its own recognizable pattern (not Apple-associated), and a natural fit for
"glanceable long-range consistency" the way rings are for "today's snapshot." Pair it with the
existing segmented-bar language from Section 1 for the "today" snapshot (reuse, don't reinvent), so
the whole app consistently avoids circular ring metaphors rather than only fixing it in one place.

**Card-by-card content mapping (revised):**
- **Activity Rings → Consistency Heatmap** — GitHub-style contribution grid (see above), replacing
  the literal-rings default entirely.
- **Step Count chart → Streak chart** — current streak count + a bar chart of daily completion
  rate over the past 7 days. **(free tier)**
- **Step Distance chart → Category Breakdown** — proportion of engagement across Good / Bad /
  To-Do this week. **(free tier)**
- **New premium card — Best Day/Time & Streak Distribution** — the day-of-week/time-of-day
  breakdown and streak-length distribution described above. **(premium tier, per Section 10)**
- **Sessions → Recent Activity** — a list of the most recently completed/logged habits, with
  timestamps. **(free tier)**
- **Awards → Milestones** — achievement badges for streak milestones (7-day, 30-day, 100-day,
  etc.), visually styled like Apple's award badges.
- **Trends → Habit Trends** — longer-range charts per habit or category (e.g. comparing this
  month vs. last month), similar to how Apple's Trends compares recent vs. long-term baselines.

---

## Open decisions needing your confirmation before this goes to the coding agent

**All four items below are now resolved — nothing left blocking in this list.**

1. ~~Ring mapping for the home strip (Section 1)~~ **MOOT** — superseded long ago by the
   connected-lines/flat-bars redesign (Section 1's "v2 visual revision"), which was built and
   screenshot-verified on-device. There is no literal ring on the Home strip to map; this item was
   just stale bookkeeping left over from before that redesign landed.
2. ~~Which specific currently-"Health"-tagged habits go into which of Good/Bad/To-Do (Section 4)~~
   **RESOLVED** — see "Health sorting — resolved" below.
3. Section groupings and their exact suggested habits, per category (Section 5) — **RESOLVED, defaults
   adopted as-is.** Note: "Islamic" is NOT one of the default Good sections — see "Islamic section —
   resolved" below.
4. Progress page card content mapping (Section 6) — **RESOLVED**, revised with competitive research
   into premium-tier analytics and a non-ring visual redesign — see Section 6 above for the full
   updated mapping.

### Health sorting — resolved

Sorted against the real template data (`src/templates/seed.ts` + `healthTemplates.ts`), not the
spec's placeholder guess:

- **Bad:** "Limit Coffee" (`hk-coffee`), "Limit Alcoholic Drinks" (`hk-alcohol`) — moderation/
  limiting habits, matching the existing `no-alcohol`/`no-sugar` Bad-category pattern.
- **Good:** everything else — all workout/activity types, Sleep, Mindful Session, Blood Pressure,
  body measurements (weight/lean mass/fat %/height/glucose), Wash Your Hands, Drink Water, plus
  every `seed.ts` health-only item (steps, swim, floss, basketball, aerobic training, pelvic floor,
  sleep diary, menstrual log, contraceptive pill, etc.).
- **To-Do:** none — Health items are recurring self-care behaviors, not one-off tasks.

### Islamic section — resolved

The current app has a real "Islamic" section (9 religious habits: five prayers, Quran reading,
adhkar, etc.) as its own top-level section in `seed.ts`. This does NOT get folded into any of the
default Good sections (Health & Fitness / Mindfulness / Productivity / Learning / Social) and does
NOT become its own default section either.

**Decision:** "Islamic" becomes one of the **premium (paid) suggested sections** from Section 10 —
available through the Edit mode's "add suggested section" flow, gated behind the StoreKit 2
subscription rather than shown by default to every user. Content (the 9 habits) is preserved
exactly as it exists today, just relocated from a default top-level section to an unlockable
suggested one.

## 7. Platform reach — architect for now, build later

These don't need full implementation in the first Swift build, but the data layer and app
architecture should be designed so adding them later doesn't require rework:

- **iPhone widgets** (WidgetKit) — habit streaks/rings as home-screen/lock-screen widgets.
- **Apple Watch app** — companion app for logging habits and viewing rings on-wrist.
- **Siri & Apple Intelligence / App Intents** — voice-driven habit logging ("log my workout").
- **Shortcuts app integration** — expose habit actions as Shortcuts building blocks.
- **Push notifications** — real remote push (currently the RN app only has local notifications
  despite having the `aps-environment` entitlement — this is where that gets used for real).
- **Contacts** — for the friends/competition feature (Section 8) once that's built.
- **iCloud sync** — cross-device sync of habit data (in addition to/alongside the existing
  Supabase sync layer — needs a decision later on whether iCloud complements or replaces
  Supabase for this data).

Practically: keep the data layer (repository pattern, not tightly coupled to any one store's
direct-access convention — see the `useHabitStore` inconsistency flagged in Phase 0) structured so
any of these consumers (widget, watch, Siri) can read/write habit state through the same interface
the phone app uses, rather than each needing custom plumbing.

## 8. Streaks, points, and vacation mode

**Streaks:** per-habit streak counter (consecutive days completed for Good/To-Do, or consecutive
days avoided for Bad), as already implied by the existing rings/progress design.

**Points — [DEFAULT PROPOSED, you asked for a suggestion]:**
- Completing a Good habit or a To-Do item for the day: **+1 point**.
- Successfully avoiding a Bad habit for the day: **+1 point**.
- Relapsing into a Bad habit: **−1 point**.
- Missing a Good habit or To-Do item by day's end: **−1 point**.
- Keep it flat/simple (no per-habit difficulty weighting) for v1 — easy to explain to the user,
  easy to reason about. Weighting by category/difficulty can be added later if flat points feel
  unbalanced in practice.

**Vacation mode:** manual toggle, user picks a specific date range in advance (e.g. "Jul 20–27").
During that window:
- No point loss for missed Good/To-Do habits or Bad-habit relapses.
- **[DEFAULT PROPOSED]** Streaks also pause rather than break during vacation (i.e. the streak
  counter neither increments nor resets) — so a user doesn't lose a 40-day streak just because
  they took a planned week off. Confirm this is what you want, or prefer streaks to simply reset
  as normal and only points are protected.

## 9. Compete with friends on habits — deferred to a later phase (blocked on real Sign-In)

**Feature detail:** not a general leaderboard — the user picks a specific habit they want to
compete on, and picks specifically which friend(s) to compete with on that habit. Scoped,
opt-in, per-habit challenges rather than one global ranking.

**Hard dependency:** this genuinely cannot be built before real Apple Sign-In is implemented
(currently a disabled stub) — you can't have "friends" without real user identity. Sequencing:
finish remaining Phase 4+ integrations → implement real Sign-In → then build this.

**Design note to revisit when this phase starts:** be deliberate about privacy/tone. Per-habit
opt-in sharing (a user might want to compete on "Steps" but not want a friend seeing their
"Limit Alcohol" data) rather than all-or-nothing friend visibility. For Bad-habit competitions
specifically, keep framing positive/playful rather than shaming — consistent with the
non-judgmental tone principle already established for engagement notifications (§13).

Confirmed: not in v1 of the Swift rewrite. Build the core app (Sections 1–6) and points/streaks
(Section 8) first, then design this as its own phase once the basics are solid.

Worth flagging now though: the Phase 0 inventory already found two Supabase tables —
`shared_sections` and `official_sections` — fully defined with RLS policies but with **zero
consuming code** anywhere in the current app. These may well be early groundwork for exactly this
kind of feature (shared/official habit sections between users) and should be reviewed when this
phase starts, rather than assuming they need to be built from scratch.

## 10. Monetization — StoreKit 2 subscription for premium suggested sections

From the Edit mode in Section 5 (add a suggested section, with its bundled suggested habits):
split "suggested sections" into a **free tier** and a **premium tier**.

- **Always free:** creating a fully custom section from scratch (Section 5's "add custom section")
  — never gated behind payment.
- **Free tier of suggested sections:** a basic set of ready-made suggested sections/habits,
  available to everyone.
- **Premium tier of suggested sections:** additional, more specialized suggested sections/habits,
  unlocked via a **recurring subscription** (monthly/yearly) implemented with **StoreKit 2**.

**[OPEN — needs a decision later, not blocking Phase 1-3]:** exact split of which suggested
sections/habits go in the free vs. premium tier, and subscription pricing/tiers (monthly vs. yearly
price points). Flag this as a Phase 4+ concern — StoreKit 2 integration should happen alongside the
other "sensitive integrations" (Section titled Calendar/Reminders/Notifications/HealthKit in the
phased migration plan), not before the core app is working.

Architecture note: use StoreKit 2's modern `Transaction`/`Product` async APIs (not the older
StoreKit 1 `SKPaymentQueue` APIs), and gate premium-section visibility through the same
repository-pattern boundary described in Section 7, so entitlement checks are centralized rather
than scattered across views.

## 11. Milestones — 3D badge awards (inspired by Fitness, not a copy)

Reference: Apple Fitness's Awards system — a tappable, tilt-responsive 3D badge (device-motion
parallax), grouped into categories like "Monthly Challenges," record-based awards, and streak
awards, with a detail page showing who earned it and when ("Earned by [Name] in [Month Year]").

**This is already named "Milestones" in Section 6** (not "Awards") — keep that naming throughout,
never "Awards."

**To stay a distinct, legally clean design rather than a copy, change the following from Apple's
specific implementation:**

- **Shape:** Apple uses a hexagon for challenge/streak awards, a circle for record awards, and a
  banner for goal-multiplier awards — this three-shape hexagon/circle/banner system is a
  recognizable Apple Fitness signature. Use a different shape family entirely for Forge's
  milestones — e.g. a rounded-square/squircle "tile," a droplet/leaf silhouette (ties to the app's
  own habit-tracking identity), or a shield shape. Pick one consistent shape, not Apple's hexagon.
- **Material/finish:** Apple's badges use a metallic, faceted, beveled-edge 3D look. Forge's
  version should have its own distinct material language — e.g. a flatter glass/gradient finish
  consistent with the rest of the app's Liquid Glass aesthetic, rather than replicating the metallic
  bevel look.
- **Interaction (keep, it's a general technique not an Apple-exclusive one):** the tilt-responsive
  3D parallax effect (device motion moves the badge's highlight/perspective) is a well-established
  technique, not something exclusive to Apple — safe to reuse the *interaction pattern* (built with
  RealityKit/SceneKit responding to `CMDeviceMotion`), just with Forge's own shape/material design
  applied to it.
- **Detail page copy:** keep the spirit ("Earned by [Name] in [Month Year]", a short description of
  what was achieved) but write original wording, not verbatim Apple phrasing.

**Where it lives:** Progress page's "Milestones" card (Section 6) shows a horizontal preview of
recent badges; tapping it opens a full Milestones list page (categories: e.g. "Streak Milestones,"
"Category Challenges," grouped similarly to Apple's "Monthly Challenges" grouping-by-time-period
pattern), each badge tappable to a detail page with the 3D tilt view.

**Milestone categories to design (adapt Apple's grouping logic, not its exact categories):**
- Streak milestones (7-day, 30-day, 100-day, etc. — ties to Section 8's streak system).
- Category challenges (e.g. completing all habits in a section for a full month).
- Points milestones (reaching point thresholds from Section 8's points system).

## 12. Habit editing & the creation-form field order/terminology

### Editability scope

**Habit name, icon, and color should be editable for ALL habits — not just custom ones.** These
are purely cosmetic metadata that don't affect tracking behavior, so there's no reason to restrict
personalization to custom-created habits only; a user should be able to re-icon or rename "Drink
Water" if they want. **Exception:** for HealthKit-tracked habits (the pink-badge ones), the
underlying HealthKit type binding, unit, and goal semantics should NOT be freely editable — those
are fixed by whatever HK quantity type the habit maps to (e.g. water volume), since letting a user
change "unit" on a HealthKit-bound habit would break the read/write mapping. Name/icon/color stay
editable even on these; goal/unit/HK-linkage do not.

### Recommended field order for the creation/edit form

Based on Apple's own Reminders app conventions (researched, not guessed) adapted to habit-tracking
needs where Reminders has no direct equivalent:

1. **Title** (habit name)
2. **Icon & Color**
3. **Goal / Unit / Step** (optional, for quantity-tracked habits)
4. **Repeat** — Apple's own Reminders terminology for this exact field is literally "Repeat." Its
   standard options are *Never, Every Day, Every Week, Every 2 Weeks, Every Month, Every Year*, with
   a "Custom" mode underneath for specific weekdays or every-N-days/weeks intervals. Habit-tracking
   apps need finer-grained options Reminders doesn't offer natively (flexible "N times this week,
   any days" tracking) — so Forge's Repeat options should read: **Every Day, Specific Days, Times
   per Week, Every X Days** — styled in Apple's plain, direct naming tone even though "Times per
   Week" isn't a literal Reminders option (Reminders has no flexible weekly-count mode).
5. **Time** — Apple's actual terminology split here is: a manually-chosen time is just called
   **"Time"** (a plain time picker); an ML-suggested time based on typed natural language is called
   **"Suggested Time"** in Reminders (not "Smart Time" — that's not real Apple terminology). For
   Forge v1, recommend just **"Time"** with a plain picker (Fixed Time) as the only option — a true
   "suggested/smart" ML-based time recommendation is a real engineering lift (needs usage-pattern
   learning) and should be flagged as a Phase 5+ enhancement, not built now.
   - "Every X Hours" / "X Times a Day" (e.g. for water-drinking-style habits) are Forge-specific
     extensions beyond what Reminders offers — keep them, styled in the same plain naming
     convention, positioned right after "Time" as an alternate sub-mode for interval-based habits.
6. **Notifications** — a toggle for local app notifications (Apple's own term is just
   "Notifications," matching Settings app usage).
7. **Sync to Reminders App** / **Sync to Calendar** — toggles, already built in the current form
   (per the Phase 3 verification), UI present but not functionally wired until Phase 4+ per Section
   10's framing.

### Delete confirmation — resolved

**[RESOLVED]** Deleting a habit is destructive and irreversible (data loss), so it must never fire
immediately from a single tap. Add a confirmation alert ("Delete this habit? This can't be undone" /
Cancel / Delete-destructive-style) in front of every delete entry point for a habit (swipe-to-delete
action, any delete button in the edit/detail view, and any bulk/multi-select delete if one exists).
Applies to habit deletion specifically for this pass — if other destructive deletes exist elsewhere
in the app (e.g. deleting a custom category), flag those too rather than assuming they're already
covered.

## 13. Engagement notifications & daily mood check-in

### Weekly reflection notifications

A real push/local notification (ties to Section 7's push infrastructure) sent roughly once a week.
**[RESOLVED]** Default day/time: **Sunday evening** (still user-configurable in Profile/Settings —
this is just the shipped default, not a fixed setting). Reflects back on the week's habit
performance, per habit or per category. Examples:

- "You stuck with Drink Water all week — 7/7 days." (positive reinforcement)
- "You missed Less Social Media 3 times this week. Want to adjust the goal, or keep going?" (a
  miss, framed as a neutral question/option, not a scolding — important for tone: never shame or
  guilt the user over a missed habit, always frame misses as information + an easy next action,
  consistent with healthy habit-formation practice)

**[DEFAULT PROPOSED]** Ties into the points/streak system (Section 8) — the notification can
reference points earned/lost or streak status that week. Should be a togglable setting per user
(some people won't want weekly check-ins), and ideally togglable per-habit too (mute reflection
notifications for specific habits without disabling all of them).

### Daily mood check-in

A simple, optional daily prompt — "How are you feeling today?" — logged once per day.

**[RESOLVED — researched Apple Health's "State of Mind" feature per user's request, adapted rather
than copied]** User liked Apple Health's mood-logging UX but flagged the same paid-app originality
concern as the rings redesign above — Apple's specific mechanic (a continuous Very-Unpleasant-to-
Very-Pleasant **slider**, with a fixed purple/blue/orange color spectrum, plus a follow-up screen of
mood-adjective words like "Amazed/Peaceful/Joyful/Calm," plus an "impact factors" correlation screen)
is a distinctive, recognizable Apple design — reusing the *slider* mechanic and *that exact color
spectrum* specifically would read as a copy. Forge's version keeps what's genuinely good UX (fast,
low-friction, mood-over-time data collection) but differs in mechanic and treatment:
- **Input style: discrete 5-option emoji/icon picker** (great / good / okay / low / rough), not a
  continuous slider — this was already the original default here and turns out to already be
  sufficiently distinct from Apple's slider mechanic; keeping it as final. Tap one option, done —
  faster than Apple's two-step slider-then-adjective-words flow.
- **Visual treatment**: Forge's own color language (tie mood tiers to the app's existing palette,
  not Apple's purple/blue/orange spectrum) and iconography (simple filled glyphs/emoji consistent
  with the rest of the app, not Apple's specific adjective-word-chip UI).
- **Where it lives**: a small card at the top of the Home page (near the weekly strip from Section 1),
  plus an optional lightweight daily notification reminder — both, notification as the nudge, Home
  card as the always-available fallback.
- Never mandatory/blocking — always skippable, no guilt-tripping if skipped for a day or several.
- **Premium tie-in (new, consistent with the Progress-page premium-analytics angle above)**: the
  mood-vs-habit-completion correlation view (e.g. "days you completed your Good habits tend to have
  higher mood ratings") — directly inspired by Apple Health's own "impact factors" correlation
  concept but built on Forge's own habit-completion data instead of Apple's exercise/sleep/daylight
  factors — becomes a **premium-tier Progress page feature** once enough mood entries exist, not a
  free first-pass feature. This gives the mood check-in a genuine premium payoff, consistent with
  Section 10's monetization strategy, rather than being purely observational forever.
- Mood data does **not** feed into the points/streak system (Section 8) — stays purely
  observational/reflective, so logging a bad day never costs points, avoiding turning emotional
  check-ins into another thing to "perform well" at.

## 14. Goal/Unit/Step rework — implementation decisions log

See conversation for full context. Final decisions: "times"+no-unit consolidated into "Count";
mmHg/mg/dL/% kept internal-only (not in user-facing picker); "Things" folded into Count;
`steps-10k` dropped as a duplicate of `hk-steps`; `limit-salt` naming/goal-split fix applied but its
ceiling-goal semantics issue excluded from this pass (flagged for a future "goal direction"
concept if more ceiling-style habits get added).

## 15. Habit completion feedback — animation, sound, haptic

Currently (per user's own observation) a habit card looks identical before/after completing it or
incrementing a step — no animation, sound, or haptic distinguishes the moment. Every item below is
**[DEFAULT PROPOSED — CONFIRM OR CHANGE]**.

Four distinct interaction moments need their own tuned feedback, not one blanket "tap effect":

1. **Simple habit toggled complete** (binary Good/Bad/To-Do item)
2. **Quantity habit step increment, still below goal** (each tap adds one `step`)
3. **Quantity habit's crossing tap — increment that reaches the goal** (the "real" completion moment
   for a quantity habit, distinct from an ordinary step)
4. **Un-completing** (toggling a completed habit back off)

### Animation

- **Simple complete (1)**: icon transitions outline → filled with a spring-based fill/scale (short,
  snappy — Apple's own checkbox/toggle timing, not a slow ease). Card background animates from its
  neutral/muted resting state into the monochromatic colored-card treatment from the earlier card-
  design discussion (Section — card color derived from the habit's own color) — so the completion
  animation and the visual redesign reinforce each other: completing a habit is what "unlocks" its
  colored card.
- **Step increment, sub-goal (2)**: lighter feedback than full completion — the count number pulses
  (brief scale bounce, like a live-updating stat) and the habit's progress ring/bar fills the
  incremental amount with an animated stroke. Card stays in its neutral/muted state until goal is
  actually reached — no premature "success" look for a partial step.
- **Crossing into complete via increment (3)**: same treatment as (1) once the goal is reached on that
  tap — this is the moment that should look and feel like "done," not another routine increment.
- **Un-completing (4)**: reverse of (1), faster and less pronounced — a clean shrink/fade back to the
  neutral state. Should read as "undone," not as a negative/punishing animation.
- **Respect Reduce Motion**: honor `UIAccessibility.isReduceMotionEnabled` — fall back to a simple
  crossfade instead of spring/bounce/scale animations. The state change itself (icon fill, card color)
  must always be clear without relying on the animation to communicate it.

### Sound

- **Simple complete (1) and crossing-to-complete (3)**: a short, satisfying system-style sound —
  reference Apple Fitness's ring-close sound or Reminders' checkbox-tick, not a loud/gamey chime.
- **Step increment, sub-goal (2)**: **no sound**, or a near-silent tick at most — a habit like "drink
  water" might get tapped 8 times in a row, and a sound on every single tap would get grating fast.
  Save the audible moment for the actual completion.
- **Un-completing (4)**: either silent, or a distinct lower/muted tone — avoid reusing the celebratory
  completion sound in reverse, which could read as confusing rather than as "undo."
- **Settings**: add a "Sound Effects" toggle (Apple's own naming convention, matches Health/Fitness
  settings) so users can opt out entirely; always honor the silent switch/mute state.

### Haptic

- **Simple complete (1) and crossing-to-complete (3)**: `UINotificationFeedbackGenerator`
  `.notificationOccurred(.success)` — the system's standard double-pulse "success" pattern.
- **Step increment, sub-goal (2)**: light `UIImpactFeedbackGenerator` `.impactOccurred(.light)` (or
  Selection feedback) per tap — subtle tactile confirmation, similar to a picker wheel's per-notch
  feedback, appropriate for something that repeats multiple times per habit.
- **Un-completing (4)**: a distinct pattern from success — e.g. `.impactOccurred(.rigid)` or
  `.notificationOccurred(.warning)` — different enough to signal "this reversed something" without
  implying an error.
- Haptics are supplementary, never the sole feedback channel — the visual state change must always be
  legible on its own (accessibility requirement, also just good practice for a device in Silent Mode
  or with haptics off).

### Net effect

Tiered feedback across the four moments: sub-goal taps stay quiet and light (visual pulse + light
haptic only), while an actual completion — whether a simple toggle or the tap that crosses a quantity
goal — gets the full treatment (spring animation into the colored card state, success haptic, short
completion sound). Un-completing is deliberately its own smaller, distinct pattern rather than either
of the above played backward.

## 16b. New, broader performance regression (post-completion-feedback work)

**[RESOLVED — confirmed by user, root cause/fix details not captured in this doc]** User previously
reported everything in the app feeling slow (not just week/day switching) following the
`CompletionFeedback`/`HabitCardRow` rewrite work. User has since confirmed this is fixed. Whichever of
the suspected causes (synchronous `AudioServicesPlaySystemSound`, per-interaction recompute of the
two-layer material/HSB-tinted `HabitCardRow` background, `InteractionToken` gating overhead) was
responsible, and the exact fix applied, weren't relayed back into this doc — flag to whoever picks up
related work later that the diagnostic detail lives elsewhere (agent session log / `CLAUDE.md`), not
here, if it's ever needed again. The 9 pre-existing build warnings noted below are unrelated compiler
cleanup, still open if anyone wants to pick them up as a low-priority pass.

## 16. Habit card design — monochromatic icon/card color, per-state treatment

Inspired by the Apple Watch Workout app's card style (reference screenshot: bright icon, card
background a deep tint of the *same* hue, not a different color). Applies to the daily habit-tracking
card/row (`HabitCardRow` — the component on Home's list, including the inline per-day list from
Section 1), not the "Add Workout"-style browsing list in Section 5, which is a different, separate
component. Every item below is **[DEFAULT PROPOSED — CONFIRM OR CHANGE]**.

### Card anatomy
- Rounded card (consistent corner radius with the app's other cards), leading icon, habit name as the
  primary label, a status/subtitle line below it, trailing "•••" menu button.
- Status line content: for simple habits, a checkmark + state text once complete (nothing showy while
  incomplete — just the plain resting state). For quantity habits, the running count/goal (e.g.
  "3 / 8 glasses") communicates progress as text, not as a separate graphic on the card.
- The "•••" menu button stays neutral-colored regardless of card state, for consistent affordance —
  it shouldn't recolor with the rest of the card.

### Color states — ties directly into Section 15's completion feedback
- **Incomplete**: card background stays neutral (`--surface-1`, matching the app's other resting
  cards). Icon rendered in outline/reduced-strength style using the habit's own color, not full
  saturation — a subtle preview of "this is the color it becomes," without looking done.
- **Complete**: card background becomes a monochromatic derived tint of the habit's own color (same
  hue as the icon, different shade — matching the Watch reference), icon becomes a full-saturation
  fill. This is exactly the "unlocked colored card" state that Section 15's completion animation
  transitions into.
- **Quantity habits mid-progress (below goal)**: stay in the neutral/incomplete treatment until the
  goal is actually reached — no partial-fill visual language on the card background itself, consistent
  with already moving away from ring/gradient partial-fill treatments for the weekly strip. Progress is
  communicated through the status-line text only.

### Color derivation formula (for implementation)
- **Dark mode**: completed-card background = the habit's hue at reduced brightness (~25–35%),
  saturation kept close to the icon's, producing the "deep tone of the same color" look from the
  reference. Icon stays at full brightness/saturation.
- **Light mode**: inverted relationship — completed-card background = the habit's hue heavily
  lightened/desaturated (~90–95% lightness), a pale tint rather than a deep one, since light-mode cards
  read as light surfaces by convention. Icon stays full-saturation on top of that pale tint.
- Always derive text/subtitle color from the same hue's appropriate darkest/lightest stop (matching the
  app's existing convention of never placing plain black/white text on a colored fill) so contrast
  holds up regardless of which color the user picked for that habit.
- Since habit color is user-customizable per-habit (Section 12 — independent of category), this
  derivation must work for *any* hue the user picks, not just the app's own preset category colors.

## HealthKit note (carried over from prior discussion)

Per earlier decision: HealthKit write access and background delivery will be fully implemented in
the Swift rewrite (currently declared in entitlements but unused — read-only via polling in the RN
version). This ties directly into the "Health-badge" habits in Section 4 — those are the habits
that should read AND write via HealthKit background delivery once implemented, rather than manual
logging.
