# Forge – Claude Code Project Guide

## Stack
- **Expo SDK 56** · React Native 0.85.3 · Hermes · **Expo Router** (file-based, typed routes)
- **Zustand** stores (manual AsyncStorage persistence, not `zustand/middleware/persist`)
- Custom i18n: `LanguageContext.tsx` + `translations.ts` → `useLanguage()` → `t(key)`
- Supabase (`@supabase/supabase-js` v2) with AsyncStorage session storage
- `expo-apple-authentication` for Sign in with Apple (iOS only, requires dev build)

## Production Scaling Standards

**Applies to all future backend/database/external-API work in this project
(and the Swift rewrite) — not a one-time checklist, a standing bar every such
feature is built against.** AI-assisted code commonly hits a scaling cliff:
logic that's correct and fast against a handful of test rows/users can
collapse under real traffic/data volume, not because the logic is wrong but
because it was never designed with scale in mind. Flag it explicitly, rather
than silently shipping, whenever a feature conflicts with one of these:

1. **Database queries — proper indexing, targeted queries.** No `SELECT *`
   over full tables. Every query should be scoped/indexed so it stays fast as
   row counts grow from hundreds to hundreds of thousands, not just fast
   against today's small test dataset.
2. **A clear caching strategy.** Don't recompute the same result repeatedly —
   compute once, cache it, serve the cached result fast on subsequent
   requests.
3. **Async processing for heavy operations.** Never make a user wait on the
   main request/response cycle for something slow (sending an email,
   generating a report, etc.) — queue it and process it in the background.
4. **Load testing before considering something done.** Don't just confirm
   "it works" against a handful of manual test cases — think through what
   happens under realistic simulated traffic/data volume, not just the
   happy-path local test.
5. **Comprehensive input validation/defense.** Never trust client input;
   validate and sanitize everything server-side.
6. **Database integrity.** Proper constraints, transactions where needed, no
   silent partial writes.
7. **Secrets management.** No hardcoded API keys/credentials anywhere in
   code — use proper environment/secret management.
8. **API resilience.** Handle timeouts, retries, and rate limits gracefully —
   external API failures shouldn't cascade into app-wide failures.

**Mandatory close-out gate (added 2026-08-03):** this list has existed since early in the
project but was never actually operationalized — a full audit of `RESULTS.md` found zero
entries that explicitly checked it, and zero evidence any real load testing has ever been
performed. A written standard nobody is required to check against doesn't guarantee
anything by itself. Going forward: **any phase that touches a database, a shared/remote
backend, or an external API is not done until its `RESULTS.md` entry explicitly answers
all 8 items above** — satisfied / deferred-with-reason / not applicable, one line each.
This is a required part of that entry, not a general reminder to keep in mind.

**CloudKit-specific resilience (added 2026-08-03, relevant starting with the Groups/social
initiative's Phase F — this app's first real shared/multi-user backend):** item 8 above
means, concretely for CloudKit: back off using `CKError.retryAfterSeconds` rather than a
fixed retry interval, handle partial failures in a `CKModifyRecordsOperation` batch
per-record (not all-or-nothing), and design around CloudKit's eventual consistency and
per-user/per-zone quotas rather than assuming a traditional server's request/response
guarantees. Verify current CloudKit error-handling APIs before coding — don't assume this
note's specifics are still exactly right by the time that phase starts.

**Production monitoring (added 2026-08-03):** this project currently has zero crash
reporting, performance telemetry, or analytics of any kind (confirmed by grep — no
MetricKit, no third-party SDK, nothing) — meaning a real scaling or stability problem after
release would only surface if a user manually reports it. Add **`MetricKit`** (Apple's own
built-in, privacy-respecting crash/hang/performance-report framework — no third-party SDK,
no extra privacy-policy disclosure burden beyond what's already true) as the minimum viable
baseline before or shortly after the TestFlight launch. This is a real, currently-open gap,
not yet scheduled under any phase above — flag it for its own small task rather than letting
it stay silently missing.

## Build & Run

```bash
# Expo Go — ALWAYS use --clear. Plain `npx expo start` serves a stale cached bundle
# and the Reanimated babel plugin will not take effect, crashing DraggableFlatList.
npx expo start --clear

# Development build (required for Apple auth, HealthKit write, any new native module)
npx expo run:ios
```

### iOS build failure recipes

**ReactCodegen "Build input file cannot be found" (rnworklets, rnscreens, rnsvg, safeareacontext)**
Caused by stale `.mm` artifacts from a previous failed codegen run. Fix:
```bash
rm -rf ios/build
rm -rf ~/Library/Developer/Xcode/DerivedData/Forge-*
cd ios && pod install
npx expo run:ios
```

**SwiftUICore linker error ("cannot link directly with SwiftUICore")**
Already patched in `ios/Podfile` post_install with `-Wl,-weak_framework,SwiftUICore`.
If Podfile is ever regenerated, re-apply that patch and run `pod install`.

**DraggableFlatList crash: `TypeError: undefined is not a function` at import**
Cause: Metro served a cached bundle that was transformed before `react-native-reanimated/plugin`
was added to `babel.config.js`. Fix: stop the server, run `npx expo start --clear`.
This error will also appear (harmlessly as a warning, not a crash) in a dev build if
the babel plugin is missing — always confirm it is the last entry in `babel.config.js`.

**ExpoAppleAuthentication "Unable to get the view config" warning**
Expected in Expo Go — Apple sign-in requires a dev build. The warning does not crash the app.

## Key Architectural Rules

### Stores
All Zustand stores use a manual `_persist()` pattern (not middleware):
```ts
_persist: async (patch) => {
  await AsyncStorage.setItem(KEY, JSON.stringify(patch));
}
```
Every action calls `_persist()` after mutating state. New stores must follow this same pattern.

### i18n
- Add ALL new keys to all 3 languages (`en`, `ar`, `tr`) in `src/i18n/translations.ts`
- Keys not found return the key string itself — TypeScript won't catch missing keys
- `resolveTitle(id, fallback)` pattern: calls `t('habit.template.' + id)`, falls back to `fallback`
- Section labels use `labelKey` stored in data, resolved at render via `t(section.labelKey)`

### TypeScript / flatMap
`flatMap` on arrays returning mixed union types confuses TypeScript inference. Use explicit `for...of` loops pushing to a typed `result` array instead.

### Expo Router typed routes
New screen files won't appear in `.expo/types/router.d.ts` until the dev server regenerates it. When adding a new route file, manually add it to all three union types in that file to keep `router.push()` fully typed.

### Reanimated
`react-native-reanimated/plugin` **must** be the last entry in `babel.config.js` plugins. Without it, any module importing Reanimated crashes at runtime with `TypeError: undefined is not a function`.

### react-native-draggable-flatlist is REMOVED
`react-native-draggable-flatlist` v4.0.3 is **incompatible with Reanimated 4.x** (Expo SDK 56 ships 4.4.1). It calls internal Reanimated 3 APIs that no longer exist, crashing at import with `TypeError: undefined is not a function` — even with `--clear` and the babel plugin. Do **not** add it back.

`app/edit-templates.tsx` uses ↑/↓ move buttons instead. `react-native-draggable-flatlist` is still listed in `package.json` but is no longer imported anywhere — leave it or remove it from dependencies, but do not import it.

### Native-only features in Expo Go
- `expo-apple-authentication` — warns in Expo Go, requires dev build to actually sign in
- `react-native-health` — Expo Go only; full HealthKit requires dev build

## Removed Features

### Groups — completely removed
There was never a `group`/`groupId` field on the `Habit` model. Groups was a stub UI only. All references (Settings row, `settings-groups.tsx` screen, translation keys `settings.groups` / `form.noGroup`) have been deleted.

### Manual Type picker — replaced by auto-inference
`HabitType` (`'good' | 'bad' | 'track' | 'todo'`) is now inferred from the category instead of being manually chosen:
```ts
function categoryToHabitType(category: string): HabitType {
  if (category === 'bad') return 'bad';
  if (category === 'todo') return 'todo';
  if (category === 'health') return 'track';
  return 'good';
}
```
The type picker UI (4-button row) has been removed from `edit-section/[id].tsx` and `app/habit/new.tsx`. Every caller now passes `habitType` via params. The standalone "+ New" button in `habits.tsx` defaults to `'good'`. Translation key `editSection.habitType` has been removed.

## Reusable UI Patterns

### "Forge animation" — native large-title header + iOS 26 scroll-edge effect

Reproduces Apple's own native large-title-to-small-title navigation bar behavior
(Settings, Mail, Messages), including the iOS 26 "Liquid Glass" scroll-edge blur.
Any future request of the form "do the Forge animation on screen X" means: apply
this exact configuration to that screen.

**This is achieved with 100% true native fidelity — not a JS/Reanimated
approximation.** Confirmed by reading this project's actual installed
dependencies, not assumed:
- `headerLargeTitleEnabled` (+ `headerLargeStyle`, `headerLargeTitleStyle`,
  `headerLargeTitleShadowVisible`) are real options on `expo-router`'s
  `Stack.Screen`, which is backed by `react-native-screens`' native-stack —
  i.e. the actual `UINavigationBar` large-title API, not a custom header
  component. Title collapse/expand is driven directly by the native scroll
  offset (1:1 during manual drag; a native low-bounce spring only for
  programmatic transitions like tap-to-scroll-to-top) because it *is* the OS
  doing it, and it's Dynamic-Type-aware for the same reason.
- `scrollEdgeEffects: { top: 'soft' }` is a real `Stack.Screen` option that
  maps directly to Apple's actual iOS 26 `UIScrollEdgeEffect` API (confirmed
  in `react-native-screens`' native enum `RNSScrollEdgeEffect` —
  `automatic`/`hard`/`soft`/`hidden`, matching `UIScrollEdgeEffect`'s own
  `style` values exactly). `'soft'` is the progressive, diffused, fade-to-clear
  edge treatment (vs. `'hard'`'s sharp dividing line) — this is the spec's
  required style.
- Do **not** also set `headerBlurEffect` alongside `scrollEdgeEffects` —
  react-native-screens' own docs warn the two can overlap/conflict.

**iOS version caveat**: `scrollEdgeEffects` is iOS 26+ only (degrades
gracefully to nothing extra on older iOS — you still get the classic native
large-title blur-on-scroll that's existed since iOS 11, just not the new
soft-gradient treatment). `headerLargeTitleEnabled` itself works back to iOS
11, well within this project's iOS 16.4 deployment target.

**Requirements for a screen to use this pattern:**
1. The screen's root scrollable content must be a `ScrollView` or `FlatList`
   with `contentInsetAdjustmentBehavior="automatic"` set.
2. The screen must be a `Stack.Screen` (native-stack) — **not** a `Tabs.Screen`.
   Expo Router's `Tabs` is built on a JS-rendered bottom-tabs fork
   (`react-navigation/bottom-tabs`-style), which has no large-title support at
   all (that's fundamentally a `UINavigationBar`/native-stack feature). A tab
   screen that wants this pattern needs its own nested single-screen `Stack`
   (e.g. `app/(tabs)/profile/_layout.tsx` wrapping `app/(tabs)/profile/index.tsx`).
3. Any existing custom/static header component on the screen (a hand-rolled
   title `View`, `ScreenHeader`, etc.) must be removed — it would otherwise
   render underneath or alongside the real native header, not collapse with
   it. Header-right buttons move to the native `headerRight` option.
4. Native large titles have no subtitle slot — if the screen's old custom
   header had a subtitle line, decide per-screen whether to drop it or move
   it into the scrolled content as a first row.

**Shared implementation**: `src/theme/forgeAnimationHeaderOptions.ts` exports
`forgeAnimationHeaderOptions(theme)`, returning the standard options fragment
(`headerLargeTitleEnabled`, `headerLargeStyle`, `headerLargeTitleStyle`,
`scrollEdgeEffects`) to spread into any `Stack.Screen options`. There's
deliberately no wrapper *component* — native-stack headers are configured via
options, not children, so a shared options function is the correct level of
reuse.

## Project Structure

```
app/                        Expo Router screens
  (tabs)/                   Tab bar screens
  edit-templates.tsx        Section reorder/hide/create (↑/↓ buttons)
  edit-section/[id].tsx     Custom section habit editor
  habit/[id].tsx            Habit editor
  templates.tsx             Browse templates

src/
  store/
    useHabitStore.ts        Habit CRUD + AsyncStorage
    useSettingsStore.ts     App settings
    useMoodStore.ts         Mood log
    useTemplateSectionStore.ts  Section order/visibility/custom sections
    useAuthStore.ts         Supabase session + Apple sign-in
  services/
    supabaseClient.ts       Supabase client (AsyncStorage session, AppState refresh)
    templateSectionSync.ts  Login sync + debounced push-to-remote
    HealthKitService.ts
  i18n/
    translations.ts         en / ar / tr strings
    LanguageContext.tsx
  templates/                Seed data for built-in sections
  theme/ThemeContext.tsx

supabase/
  schema.sql                Run once in Supabase SQL Editor to create all tables
```

## Supabase Tables
| Table | Purpose |
|---|---|
| `user_template_settings` | Per-user section order + hidden IDs per category |
| `custom_sections` | User-created sections (ID = client `cs_xxx` string) |
| `shared_sections` | Sections shared via `forge://section/<code>` deep link (not yet implemented — no route handler exists for this yet) |
| `official_sections` | Curated sections managed by admins in Supabase UI |

RLS is enabled on all tables. Credentials live in `.env` (`EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY`).

## Sync Flow
1. App starts → `useAuthStore._initListener()` restores session from AsyncStorage
2. Session found → `syncOnLogin(userId)`: pulls remote, merges into local (remote wins per category), or pushes local if remote is empty
3. Any store mutation → 2-second debounced `pushToRemote(userId)`
4. Custom section deleted → immediate Supabase `DELETE` (no debounce)
5. Sign out → stops sync subscription, clears session

## iOS App Info
- Bundle ID: `com.bilalhammad.forge`
- Scheme: `forge` (the old pre-rename `momentum` scheme was removed entirely; any previously-shared `momentum://` links no longer open the app)
- Entitlements: HealthKit + Sign in with Apple (`com.apple.developer.applesignin`)
- Deployment target: iOS 16.4

## Swift Rewrite (ForgeNative)

The native SwiftUI rewrite lives in a separate Xcode project (`ForgeNative/`,
bundle ID `com.bilalhammad.forge.native`) — everything above this section
describes the original Expo/RN app. The Production Scaling Standards section
near the top of this file applies to the Swift rewrite too, not just the RN
codebase.

**`APP_REDESIGN_SPEC.md` (repo root) is the living source of truth for
design decisions in the Swift rewrite.** Read the relevant section before
touching a screen rather than re-deriving decisions from scratch — e.g.
Section 1 covers the Home weekly strip specifically (the rings→bars
redesign, day-selection behavior, read-only-on-past-day rules). Any future
session touching Home, the weekly strip, or day-selection should read that
section first.

### Home weekly strip — current architecture (§1)

- Three continuous per-category bars (Good/Bad/To-Do) under a day-letter
  header — no text labels, no dots. This replaced two earlier designs in
  sequence: the original concentric-rings-per-day strip, then a
  dots-joined-by-connecting-lines version. `StreakLinesStripView` is the
  per-week renderer; `WeeklyRingsPagerView` owns week-to-week paging (real
  `TabView(.page)`), the date label, and per-week completion data
  fetch/cache (with a prefetch radius so paging doesn't stall on-device).
- `HomeView.selectedDate` drives the *existing* habit list inline — there is
  **no separate day-detail screen**. An earlier `DayDetailView` sheet
  approach was built and then deliberately removed in favor of this.
- Selecting a non-today day makes the list fully read-only: tap-to-toggle,
  tap-to-increment, swipe actions (Edit/Archive/Delete), and the "+" Add
  Habit button are all disabled/hidden outright, not just visually dimmed —
  nothing should be mutable while viewing a day that isn't today.

### Home weekly strip — tap-to-select-day (RESOLVED)

Fixed by rewriting `StreakLinesStripView` so each day is exactly one
`Button`/`ZStack` owning its full content (no separate content-view vs.
tap-target view tree kept in sync only by convention) — confirmed fixed
on real device. Two reusable environment lessons from this investigation:
**`xcodebuild` can silently skip a rebuild** if source changed within the
same mtime second as the last build (`touch` the file first, confirm
`SwiftCompile`/`Ld` actually ran in the log before trusting `BUILD
SUCCEEDED`; Debug runs from `Forge.app/Forge.debug.dylib`, check that);
**Simulator cannot synthesize a tap into `TabView(.page)` content** via
`cliclick`/mouse-drag (30+ attempts, zero success) — only real touch
injection (device or XCUITest) proves a gesture works, a build success +
static screenshot is not evidence. Full investigation: `INVESTIGATION_LOG.md`.

### SwiftData store — Application Support directory race on fresh launch (investigated, not a live bug)

`ForgeApp.init()` proactively creates the Application Support directory
before building the `ModelContainer`, avoiding a harmless-but-noisy
Core-Data-flavored sandbox-denied log line on fresh install (SwiftData's
default store is Core-Data-backed — grepping for `NSPersistentContainer`
finds nothing here, but the log lines look like it). Verified with real
`os_log` timestamps that this race can never actually reach
`HomeView.reload()` — `ModelContainer`'s init is synchronous and already
fully recovered by the time it returns, 3.4 seconds before `reload()`
even starts — so a historical `visibleHabits.count=0` symptom seen during
other investigations was unrelated to this race, most likely just a
genuinely-empty test dataset at the time. Full timestamps: `INVESTIGATION_LOG.md`.

### Home habit list — render cascade on day/week switch (RESOLVED)

Bounce/pulse tap-feedback animations in `HabitCardRow` were re-firing on
every day/week switch, not just on real taps, because they watched
`isComplete`/`count` directly via `.onChange` — which also change when the
row's underlying day changes, indistinguishable from a real tap at that
level (measured: a single day switch fired 2-3 rounds of `body`
re-evaluation across half the visible rows). **Fix**: `InteractionToken`
(`HomeView.swift`) — a value set only by a genuine tap, threaded down so
the bounce/pulse animations gate on "was this row actually tapped," never
directly on the data they're celebrating; the base crossfade (background
color, icon shape) is deliberately left watching the real data, since that
one *should* animate on a day switch. Reusable pattern for any future
per-tap visual feedback. Full measurements: `INVESTIGATION_LOG.md`.

### Home tap-to-complete — synchronous blocking on MilestoneEngine + unconditional HealthKit call (RESOLVED)

Root-caused and fixed. Two real regressions: (1) `MilestoneEngine
.afterCompletionLogged(habit:)` was awaited inline in `HomeView.handleTap`/
`handleLongPress`, adding **870–1080ms** of actor-hop/scheduling overhead
per tap for work with no user-visible urgency (fixed via
`dispatchMilestoneCheck(for:)`, a detached fire-and-forget `Task` — the
origin of Engineering Standard #3 below); (2) an unconditional HealthKit
actor-hop (`HKHealthStore.isHealthDataAvailable()`) fired on every
completing tap even for non-HealthKit habits, costing ~650–700ms, now
gated behind `habit.isHealthKitTracked` at the call site. Measured
before/after: 870–1541ms → 4.69–74.33ms (median ~6ms), a 50–100×
improvement. Methodological note worth keeping: scattered concurrent log
lines can look like a real timing gap that isn't — consolidate into one
atomic log line per event before trusting a measured gap. Full
investigation: `INVESTIGATION_LOG.md`.

### Home weekly strip prefetch — actor-hop overhead investigated; one real fix shipped, one real problem still open (PARTIALLY RESOLVED)

Real, still-notable finding: `Thread.isMainThread` reported `true` even
inside a genuinely `Task.detached` call in this Simulator environment —
**don't trust that check as a signal here** without corroborating
evidence. Also found: repeated identical actor-isolated queries in one
session got progressively slower without recovering on a pause (485ms →
1635ms → 1585ms → 1397ms across 4 calls), suggesting SwiftData
`ModelContext` state accumulation inside the long-lived `@ModelActor` —
real, but not root-caused; a real-device retest was recommended, not done.
Shipped regardless: `fetchCategoryCompletionRates` moves day/category
aggregation into the repository (smaller actor-boundary payload, SQL-side
filtering) — a real improvement, though it did not turn out to fix the
compounding-slowdown symptom. Full data/tables: `INVESTIGATION_LOG.md`.

### Home weekly strip freeze — root cause found: MainActor continuation-resumption latency, not query time (PARTIALLY RESOLVED)

Real finding: the slow part was never the query (2.6ms actor-internal) but
Swift Concurrency's delay resuming the suspended caller after it (up to
~2366ms observed caller-side) — a `ForEach` ranging over 5201 elements
(`minWeekOffset = -5200`, ~100 years back) measurably inflated this by
forcing SwiftUI to reconcile that many identities on every state change,
even though the range's content closure never actually evaluated them
(confirmed by a direct before/after test: shrinking the range to `-8` cut
the gap ~6×, reverted immediately after — don't ship `-8`, it caps history
at 8 weeks). **This is the origin of Engineering Standard #1's bounded-
range rule below.** A residual, still-unidentified baseline gap remained
even at a small range size — `Thread.isMainThread` reported `true` for
every one of 456 captured events this round despite proven real
suspensions, confirming (again) it's unreliable as a signal in this
Simulator environment. Untested on real device — flagged, Simulator-only,
no fix shipped this round (pure measurement pass). Full trace data and
tables: `INVESTIGATION_LOG.md`.

### Home weekly strip — "both directions rubber-band, nothing pages" bug report (RESOLVED — not a code bug)

Turned out to be correct native behavior, not a pager regression: the
device's real data at the time had only one non-archived habit whose
`startDate` fell in the current week, so `minWeekOffset` computed to `0`
and the `TabView(.page)` genuinely had exactly one page to swipe to —
confirmed by dumping the real accessibility hierarchy (`"Vertical scroll
bar, 1 page"`). With a seeded 8-week-back habit, the identical strip
correctly reported "2 pages" and swiped both directions. If a future
"swipe does nothing" report comes in, check `minWeekOffset`/earliest
active habit `startDate` before assuming a regression.

Confirmed via a new `ForgeUITests` XCUITest target — this project's first
successful **real gesture-injection testing** (Simulator mouse-drag never
registers on `TabView(.page)` content, see the tap-to-select-day lesson
above; XCUITest's `swipeLeft()`/`swipeRight()` use real touch injection
and worked immediately). **Kept permanently**: the `ForgeUITests` target,
`ForgeUITests/WeeklyPagerSwipeTests.swift`
(`testSwipeBackwardThenForwardRoundTrips`), a `-uiTesting` launch-arg path
in `ForgeApp.init()` (in-memory store + a seeded 8-week-back habit, never
touches the real on-device store), and two accessibility identifiers
(`weeklyStrip.dateLabel`/`.tabView`) — the only reliable way found so far
to test swipe/drag behavior in this environment without a physical
device, reused by every gesture feature since (Engineering Standard #5).
Run it with:
```
xcodebuild test -project Forge.xcodeproj -scheme Forge \
  -destination "id=<simulator-udid>" \
  -only-testing:ForgeUITests/WeeklyPagerSwipeTests
```
Full investigation: `INVESTIGATION_LOG.md`.

### Progress page redesign (§6) + daily mood check-in (§13) — built, not yet StoreKit-wired

Two features built together in one pass. Both real screenshots (a rich,
isolated demo dataset — see below) confirmed on-Simulator; ForgeUITests
grew a second real regression test (`MoodCheckInTests`) alongside
`WeeklyPagerSwipeTests`.

**Progress page**: `RingsView` is gone — this app has no circular
Apple-Activity-Ring-style visual left anywhere, matching the Home strip's
own earlier rings→bars move. New card order: `ConsistencyHeatmapCard`
(new — 3 stacked per-category GitHub-style grids, 140-day window matching
`HabitDetailView`'s existing per-habit heatmap precedent) → Streak (now a
*real* number — the largest of the three categories' current streaks,
computed the same way `MilestoneEngine.checkCategoryStreak` does, so it
always agrees with what a Milestone badge would award) → Category
Breakdown (now a real weekly proportional **stacked bar**, deliberately
not a donut/pie — a donut is still visually a ring) →
`BestDayTimeStreakDistributionCard` (**new, premium-gated**: day-of-week
completion rate, a time-of-day histogram of `Completion.loggedAt`, and a
streak-length histogram bucketed at the same 7/30/100 thresholds
Milestones already uses — all three sharing one scope picker, All/
category/individual habit) → Recent Activity → Milestones → Habit Trends
→ the pre-existing habits list (kept, not one of the spec's named cards
but independently useful).

**New architecture, both reused for future premium/observational
features, not just this pass**:
- `EntitlementService` (`Core/Entitlements/`) — the centralized
  premium-gating boundary §10 asked for. `StubEntitlementService` always
  returns `false`; real StoreKit 2 `Transaction`/`Product` wiring is still
  Phase 4+, unstarted. §10's *existing* premium-suggested-sections gate
  (`SuggestedSectionTier`) does **not** yet read through this boundary —
  consolidating it here is a reasonable follow-up, not done this pass.
- `MoodRepository` (protocol + `SwiftDataMoodRepository` +
  `InMemoryMoodRepository`, same shape as `HabitRepository`) —
  `MoodEntryModel.date` is `@Attribute(.unique)` (real DB-level one-per-day
  integrity, stronger than `CompletionModel`'s repository-only
  discipline, since mood has no second scoping key the way a completion
  has `habitID`). `fetchEntries(from:to:)` is deliberately shaped to join
  against `HabitRepository.fetchCompletions(from:to:)`/
  `fetchCategoryCompletionRates` later for §13's "mood vs. habit-
  completion correlation" card — not built this pass, no real data yet to
  make it meaningful.

**Mood check-in** (`MoodCheckInCard`, top of Home's list content, directly
below the pinned weekly strip): 5-point `great/good/okay/low/rough` scale
— a judgment call on exact visual identity (spec named the 5-point scale,
not colors/icons): a green→red scale reusing `HabitCategory`'s existing
green/red rather than Apple's purple/blue/orange, paired with a
*weather*-metaphor SF Symbol per level (`sun.max.fill` → `cloud.bolt.rain
.fill`) instead of face/emoji glyphs, specifically to avoid reading as
"just another emoji mood picker." Never touches `PointsLedger` or any
streak math — the card's only repository call is `MoodRepository`.
Tapping the optional daily reminder (`MoodNotificationScheduler`, its own
independent `SettingsView` toggle — not folded into the habit-
notifications master switch) routes to the Home tab via
`MoodCheckInRouter` (`@Observable`, `@MainActor`) and
`MoodNotificationDelegate` (`ForgeApp`'s only
`UNUserNotificationCenterDelegate`) — "opens straight to the card" was
interpreted as "switch tabs," since there's no separate mood screen to
navigate to; the card is already immediately visible at Home's top.

**Screenshot methodology, reusable for future feature-build passes**: real
on-device data was too sparse to screenshot meaningfully, so a temporary
`-demoScreenshots` launch flag (removed after use, unlike `ForgeUITests`/
`-uiTesting` which are kept as ongoing regression infrastructure) seeded a
rich in-memory dataset and used log-marker-triggered capture rather than
guessed timing. Full method and the timing pitfall it avoided:
`INVESTIGATION_LOG.md`.

**Explicit judgment calls from this pass, not fully specified by
APP_REDESIGN_SPEC.md §6/§13**: heatmap laid out as 3 per-category grids
rather than 1 blended grid; 140-day heatmap window rather than a literal
GitHub year; Category Breakdown as a stacked bar rather than a donut;
Best-Day/Time's "time you tend to fall off" is really "time you tend to
log a completion" (a miss has no timestamp — day-of-week is what actually
answers "when do you fall off"); the premium card's day-of-week/time-of-
day/streak-distribution all share one bounded 90-day lookback rather than
an unbounded per-habit fetch (a real, flagged accuracy tradeoff for older
streaks); mood's exact 5-color/5-icon set; mood card placement (top of
Home's list content vs. inside the pinned strip's own safeAreaInset); and
interpreting "opens straight to the card" as a tab switch, not a sheet/
scroll-to.

### Timer-based interaction for time-unit habits (§ new — no spec section number yet)

Any habit whose `unit` is `.minutes` or `.hours` (`HabitUnit.isTimeBased`,
gated purely on that enum case, not on any specific habit/template) now
uses a native, self-updating countdown timer instead of tap-to-increment.
Tapping starts the timer (persisted as `Completion.startedAt`); a second
tap while running cancels it; long-press still instantly force-completes
without ever touching the timer, unchanged from before. On reaching goal,
`CompletionFeedback.complete()` fires exactly once, the real elapsed
duration (not a hardcoded `goal`) is logged via the repository, and — if
the habit is also a HealthKit write-back type — fed into
`HealthKitService.writeManualEntry`.

**Timer Live Activity — confirmed circular exception.** The running
timer's ring (`HabitTimerRingView` in the main app; `HabitTimerLiveActivity`
in the new `ForgeWidgets` extension, both for the in-app row and the Live
Activity/Dynamic Island presentation) is circular, matching Apple's own
Clock/Timer app — a deliberate, user-confirmed exception to this project's
otherwise-consistent anti-Apple-copy visual rule (Home's weekly strip:
rings → bars; Progress: rings removed entirely, §6; Milestones: squircle
tiles, not Apple's hexagon/circle/banner, §11). Confirmed directly with the
user when this feature was scoped, specifically because a circular
depleting ring is the immediately recognizable "a timer is running"
affordance — this is the one place in the app deliberately reusing Apple's
own visual language rather than differentiating from it.

**Real, empirically-confirmed finding worth remembering for future
timer/Live-Activity work**: `ProgressView(timerInterval:).progressViewStyle
(.circular)` — the literal API this feature was originally scoped
around — does **not** render as a depleting ring on this SDK. Screenshot-
verified, not assumed: it renders as the plain system activity-spinner
glyph (a pinwheel of static spokes), visually unrelated to how much time
remains, even though `Text(timerInterval:)` right next to it correctly
ticks down. In the main app's in-list `HabitTimerRingView`, this was fixed
by using `Gauge(value:in:).gaugeStyle(.accessoryCircularCapacity)` (the
same circular-capacity ring API Apple uses for Watch complications) with
its `value` recomputed each tick inside a `TimelineView(.periodic(from:
by:))` — SwiftUI's own native declarative mechanism for date-driven
periodic UI updates, not a manual `Timer`/`DispatchSourceTimer` instance,
and still always correct-from-real-dates on every tick rather than an
accumulated/drifting counter. The `ForgeWidgets` Live Activity view
deliberately keeps the plain `ProgressView(timerInterval:).circular` API
despite the spinner-glyph look, rather than switching to the same
`Gauge`/`TimelineView` hybrid: a `TimelineView` needs its hosting process
alive to re-fire, which the main app can assume (the row is only ever
visible while Forge itself is running) but a Live Activity's entire
purpose is staying accurate while the app/extension process is fully
suspended — `Text`/`ProgressView`'s `timerInterval` initializers are
Apple's specific, documented-safe views for that (the system repaints
them, not the extension process), so correctness-under-suspension won out
over exact visual match there. See `HabitTimerRingView`'s and
`HabitTimerLiveActivity`'s own doc comments for the full reasoning.

**New `ForgeWidgets` app-extension target** (`project.yml`) exists solely
for this Live Activity — no home-screen widgets configured, just the one
`ActivityConfiguration`. `HabitTimerAttributes.swift` and `HabitColor.swift`
are compiled directly into both the `Forge` and `ForgeWidgets` targets
(listed in both targets' `sources` in `project.yml`) rather than factored
into a shared framework — matches this project's existing preference for
direct multi-target file references over a framework boundary for
something this small. `NSSupportsLiveActivities: YES` was added to the
main app's Info.plist keys; no App Group/shared container exists or is
needed, since the extension only ever renders from the `Activity`'s own
`ContentState`, never reads app-side storage directly.

**PAUSE/RESUME NOW EXISTS — the "no pause concept" decision below was
reversed (2026-07-30)** when the Live Activity was redesigned to match
Apple's Workout Live Activity (icon / countdown / pause-resume pill,
Lock-Screen scope). A genuine pause (not a cancel-and-lose-progress) now
backs that UI, via an **accumulated-elapsed model** on `Completion`:
`startedAt` is the *running segment's* start (nil while paused), and a new
`accumulatedElapsed: TimeInterval` banks time from previous segments —
total elapsed is `accumulatedElapsed + (now - startedAt)` while running,
just `accumulatedElapsed` while paused (`Completion.elapsed(asOf:)`). The
naive `now - startedAt` was abandoned because it keeps advancing while
paused. Pause/resume is driven from the Live Activity's button
(`ToggleTimerPauseIntent`, a `LiveActivityIntent` that updates the
`Activity` in-process and signals the app via `SharedTimerPauseSignal`,
same App-Group mechanism as the old stop signal). The Live Activity's
`ContentState` gained `isPaused` (+ `effectiveStartDate`/`endDate`/
`pausedRemaining`): running renders a ticking `Text(timerInterval:)`,
paused renders a *static* text — a `timerInterval` view keeps ticking
regardless of app pause state, so it must not be used while paused. The
old Stop button was removed from the Live Activity (cancel still lives
in-app: a second tap on a running row, or the in-app row's own stop
button → `HomeView.cancelTimer`, independent of the Live Activity — the
`timerStatus.stopButton` regression test still passes). **In-app-row
caveat**: the in-app row still shows a *paused* timer as idle (its
paused-state visual redesign is an explicitly-separate future round) —
but resuming (via the LA or an in-app tap) preserves banked time, which
is the load-bearing correctness property. See RESULTS.md (2026-07-30) for
the full build.

**Judgment calls made, not fully specified by the original request**:
- (SUPERSEDED — see the pause/resume reversal above; original decision and
  reasoning kept in `INVESTIGATION_LOG.md` for history.) The current
  behavior is pause/resume from the Live Activity plus in-app
  start/resume-or-cancel.
- Tapping an already-complete time-unit habit is a no-op, matching how a
  further tap on an at-goal quantity habit already behaves — no
  "uncomplete via tap" gesture exists for this habit type.
- The in-row ring's exact size (44×44, up from the 34×34 used for a
  regular quantity habit's ring) — chosen to fit the countdown digits
  legibly, since a duration timer has more to display than a bare count.
- Catch-up correctness (`HomeView.checkTimerCompletions`) is driven purely
  by persisted `Completion.startedAt` plus `habit.goal`/`habit.unit` — the
  in-process one-shot completion (`HabitTimerCoordinator.scheduleCompletion`)
  is a nice-to-have for instant feedback while foregrounded, never the
  source of correctness. Same self-healing shape as
  `MilestoneEngine.runCatchUp()` elsewhere in this app.

## Autonomous operation policy

Added per explicit instruction (2026-07-25) to let a session pick up work
continuously across the project without stopping for routine implementation
decisions. Applies to this project going forward, not just the pass that
introduced it.

**At the start of every session:**
1. Read `TASKS.md` (repo root) first, before touching code. It's the
   priority-ordered work queue — foundational items before polish, spec
   deviations flagged explicitly, everything audited against the actual
   codebase rather than trusted from a prior summary.
2. Work through unchecked items in order. Prefer P0/P1 (blocking / genuinely
   missing) over P2 (deliberately deferred) over polish — but use judgment
   if a later item is trivially quick and unblocks nothing to skip ahead for.
3. **Before starting any individual item, verify it isn't already implemented
   by checking the actual relevant files/code — never start work based on the
   checklist's checkbox state alone.** `TASKS.md` is generated and updated by
   the same kind of session doing this work, and has been caught drifting
   from reality before: a 2026-07-25 re-audit found a P3 entry describing
   `HabitFormView.swift`'s field order and delete-confirmation location
   inaccurately, and a P2 entry suggesting nonexistent Supabase groundwork in
   this codebase (see TASKS.md's own "Correction" notes on those entries for
   the specifics) — both stale claims that would have sent a future session
   either redoing already-working code or chasing a lead that didn't exist.
   A one-line `grep`/`Read` against the specific file(s) the item names is
   normally enough — this isn't a full spec re-audit before every single
   item, just a sanity check that the checkbox still matches the code before
   spending real work on it. If a task turns out to already be done: mark it
   done in `TASKS.md`, log the correction in `RESULTS.md`, commit, and move
   on — don't redo working code.
4. Full permission is granted for this project to make routine implementation
   decisions autonomously — which SwiftUI modifier, which internal function
   shape, which file to put something in, minor naming, etc. Document
   non-obvious judgment calls in the commit message and/or a code comment as
   they're made (the pattern already used throughout this file and the
   codebase's own doc comments) — not in a side conversation, since the code
   and commit history are what a future session actually reads.

**Only stop and wait for explicit direction on:**
- A genuine product/design decision the spec doesn't resolve (tone, exact
  visual treatment where §-level guidance runs out, monetization specifics,
  anything a reasonable engineer couldn't infer from the spec + existing
  app conventions).
- A confirmed hard blocker — something tried multiple genuinely different
  ways, root-caused as far as possible, and still not resolvable from this
  environment (the real-device-vs-Simulator HealthKit consent-sheet
  investigation is the reference example: multiple angles tried, the actual
  mechanism identified precisely, only then reported as blocked rather than
  guessed at after one attempt).
- Anything destructive/hard-to-reverse outside normal commit/push flow (force
  push, deleting user data, changing shared infrastructure) — normal
  commit-and-push of this project's own code is pre-authorized by this
  policy; the things flagged as needing confirmation elsewhere in this
  project's own conventions (see root `CLAUDE.md`'s general safety guidance
  it inherits) still apply beyond that.

**After each completed task, in order:**
1. Check it off in `TASKS.md`.
2. Append an entry to `RESULTS.md` (repo root) — what was done, judgment
   calls made, what was verified and exactly how (screenshot / real test /
   manual check — be specific, "looks right" is not verification), anything
   still open about that specific task. Never overwrite prior entries.
3. Commit the code change and the `TASKS.md`/`RESULTS.md` updates together.
4. Push.
5. **If "Bilal iPhone" is connected, install the freshly-built app onto it**
   (see "Install to real device on close-out" below) so Bilal always has the
   latest build in hand without plugging in and building himself. If the
   device isn't connected, skip this and carry on — it's an extra step when
   the device is available, never a blocker.
6. Move to the next item immediately — don't idle waiting for acknowledgment
   on routine progress.

**Install to real device on close-out** (standing rule, added per explicit
instruction 2026-07-30 — do this automatically, don't wait to be asked):
whenever a fix/feature round is being closed out and the iPhone is connected,
install the build onto the real device as part of closing out that task.
- Verify the device is actually connected first, live —
  `xcrun devicectl list devices` should show "Bilal iPhone" as `connected`
  (UDID `62AB4A14-06B4-5C28-ADB2-2F1D53B414C5`, transport `wired`). Don't
  assume from a previous check; the phone gets unplugged.
- Build for the device and install:
  ```
  xcodebuild -project Forge.xcodeproj -scheme Forge \
    -destination "id=62AB4A14-06B4-5C28-ADB2-2F1D53B414C5" -configuration Debug build
  xcrun devicectl device install app --device 62AB4A14-06B4-5C28-ADB2-2F1D53B414C5 \
    <DerivedData>/Build/Products/Debug-iphoneos/Forge.app
  ```
- Confirm the install concretely, not from a zero exit code:
  `xcrun devicectl device info apps --device 62AB4A14-06B4-5C28-ADB2-2F1D53B414C5`
  and check `com.bilalhammad.forge.native`'s version/build matches what was
  just built (bump/compare `CFBundleVersion`, or at minimum confirm the app
  is present and freshly dated).
- Real-device XCUITest automation is frequently blocked in this environment
  (see the delete-animation rounds' history); a plain `install` does **not**
  need automation mode, so this step works even when device *testing*
  doesn't. Don't conflate the two.

## Engineering standards

Standing bar for all work in this project (Swift rewrite and, where it still
applies, the original RN app) — not a one-time checklist. Complements the
"Production Scaling Standards" near the top of this file; that section is
about backend/external-API scale, this one is about client-side correctness
and craft.

1. **No unbounded collection/loop/query scaling with total historical data.**
   Always page/window/bound. This is not a hypothetical — it's the exact,
   previously-shipped bug documented above under "Home weekly strip freeze":
   a `ForEach` over `minWeekOffset...0` (5201 elements, ~100 years back)
   measurably delayed MainActor's return to unrelated pending work elsewhere
   in the app. The fix (windowed/recentering pager, §-pattern used
   throughout this codebase) is the standing model: a small constant window
   around whatever "now" is, not a range sized to the data's full history.
   Same principle applies to queries — `fetchCompletions(from:to:)` takes an
   explicit bounded range everywhere it's called, never "fetch everything
   and filter in Swift."
2. **All data access goes through the existing repository pattern.** Never
   read/write SwiftData models directly from a View or from business logic
   outside a `*Repository` implementation. New data needs get a new
   repository method (or a new repository entirely, matching
   `HabitRepository`/`MoodRepository`/etc.'s existing shape: protocol +
   `SwiftData*` implementation + `InMemory*` implementation for previews/
   tests), not a bypass.
3. **Correct async/await and actor isolation throughout; nothing expensive
   on the main thread.** SwiftData repositories are `@ModelActor`-isolated
   for exactly this reason. A tap handler that needs to do real work (a
   milestone check, a HealthKit call) dispatches it rather than awaiting it
   inline if the result isn't needed before the UI can respond — see the
   "Home tap-to-complete" investigation above for the measured cost of
   getting this wrong (a synchronous milestone-engine await added
   870-1080ms to every single tap).
4. **Every destructive action requires an explicit confirmation alert, no
   exceptions.** Matches §12's own resolved decision for habit deletion,
   generalized: any irreversible data loss (delete habit, delete custom
   section, reset a category's sections to default, etc.) gets a real
   `.alert` with a named destructive action before it fires — never a bare
   single tap.
5. **Every gesture/interaction feature gets a real XCUITest regression test
   before being considered done.** Simulator mouse-drag does not reliably
   register as a swipe/drag gesture in this environment (confirmed
   repeatedly, multiple investigations, see the weekly-pager history above)
   — `ForgeUITests` (kept permanently for exactly this reason) using real
   touch injection is the only way found so far to verify gesture-driven
   behavior actually works, not just that the code compiles and "looks
   right" in a static screenshot. Real system UI (HealthKit's consent
   sheet, and likely other system permission prompts) is its own further
   wrinkle — see the HealthKit real-device investigation below for what's
   confirmed about that boundary specifically.
6. **Match Apple's HIG/terminology by default unless a documented reason
   says otherwise.** Field names, interaction patterns, and platform
   conventions should read as genuinely native unless this project has an
   explicit, on-the-record reason to diverge — and when it does diverge,
   that reason should be written down at the point of divergence (matching
   how §1's rings-avoidance and §13's mood-check-in-vs-Apple's-slider
   decisions are already documented in `APP_REDESIGN_SPEC.md`): both are
   deliberate original-design choices for a paid app's legal/differentiation
   concerns, not arbitrary departures from HIG. New deviations need the same
   kind of explicit reasoning, not a silent choice.
