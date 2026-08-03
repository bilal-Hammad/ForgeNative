# INVESTIGATION_LOG.md — Detailed historical investigations

Full, verbatim write-ups of resolved/partially-resolved investigations that were
originally in `CLAUDE.md`. Moved here on 2026-08-03 to keep `CLAUDE.md` (which is
loaded in full as standing instructions on every session) focused on active
rules and durable, reusable lessons rather than one-time measurement logs.

Every durable lesson from each investigation below still has a short pointer
left in `CLAUDE.md` at the section it came from — this file is the full
detail behind those pointers, not a separate source of truth. Nothing below
is still an open bug unless explicitly marked as such.

---

## Home weekly strip — tap-to-select-day (RESOLVED)

Tapping a day cell to change `selectedDate` went through a multi-round
real-device investigation before landing on a fix. **Root cause**: the
strip's original architecture split each day's visual content (letter +
bar segments, drawn once per row across the whole week) from its tap
target (a separate per-day `Button` underneath, aligned only by both
sides independently computing the same `columnWidth`) — two independently
constructed view trees kept in sync purely by convention, never by shared
identity. An unselected day's button, filled with `Color.clear` to stay
invisible, intermittently failed real-device hit-testing even with a
correctly-ordered `.contentShape(Rectangle())`, while the one opaque
(selected) cell always worked. (A separate timezone-normalization bug in
`weekStart`/`weekDates` construction — fixed by forcing every day-`Date`
through `Calendar.startOfDay` — was real but secondary to the hit-testing
issue.)

**Fix**: rewrote `StreakLinesStripView` so each day is exactly one
`Button`/`ZStack` owning its full content (selection background + letter
+ all 3 bar segments — see `dayCell(date:columnWidth:isFirst:isLast:)`),
with `.frame()` → `.contentShape(Rectangle())` applied once to that single
view. Selected vs. unselected now differ *only* in fill color, never in
which views get constructed, so there's no longer a second view tree for
the interactive one to silently disagree with. **Confirmed fixed on real
device**: tapping an unselected day correctly moves the highlight. All
temporary debug instrumentation from this investigation (print
checkpoints, the on-tap red flash, the "DEBUG: select yesterday" trigger
button) has been removed from the codebase.

Two general lessons from this investigation, kept because they're
reusable beyond this specific bug:
- **`xcodebuild` can silently skip a rebuild.** It doesn't always pick up
  source edits made by an external tool within the same second as the
  last build (a build-description/mtime-granularity cache issue) — it
  reports `BUILD SUCCEEDED` while silently skipping `SwiftCompile`/`Ld`
  entirely, so the installed app keeps running the previous binary. This
  project's Debug configuration also runs code from
  `Forge.app/Forge.debug.dylib`, not the thin `Forge` executable — check
  the dylib when verifying a change actually shipped. Fix: `touch` the
  changed file immediately before rebuilding, and confirm `SwiftCompile`
  and `Ld` actually appear in the build log before trusting
  `BUILD SUCCEEDED`.
- **Simulator can't synthesize taps into a `TabView(.page)`.** No
  `cliclick`/mouse-driven synthetic tap ever registered on a button
  hosted inside a `.page`-style `TabView` in this environment (30+
  attempts, full coordinate sweep, multiple sessions) — `xcrun simctl` has
  no real touch-injection API, and `TabView(.page)`'s own pan gesture
  recognizer appears to claim synthetic touches before a child button's
  recognizer resolves. More generally: build success and a Simulator
  screenshot of default/untapped state are not evidence that a
  tap/gesture-driven feature works. Real-device testing (or an XCUITest
  target using `XCUIApplication().tap()`, which goes through real touch
  injection) is the only reliable way to verify anything gesture-driven on
  this control.

---

## SwiftData store — Application Support directory race on fresh launch

`ForgeApp.swift`'s `init()` builds a `ModelContainer` (this project uses
**SwiftData**, not raw Core Data — but SwiftData's default store is
Core-Data-backed, which is why failures surface with Core-Data-flavored
log lines like `Failed to stat path '.../Application Support/
default.store', Sandbox access to file-write-create denied`; grepping for
`NSPersistentContainer` will find nothing in this codebase). On a fresh
install, that log line appeared before SwiftData's own internal recovery
path kicked in and the store loaded successfully — the `Application
Support` directory isn't guaranteed to exist yet at that point, and
nothing in the app was creating it proactively (confirmed: no
`FileManager.createDirectory` call existed anywhere in `Forge/` before
this fix).

**Fix**: `ForgeApp.swift`, in `init()`, before `ModelConfiguration` is
built — resolve `FileManager.default.urls(for: .applicationSupportDirectory,
in: .userDomainMask).first` and `try? FileManager.default.createDirectory
(at:withIntermediateDirectories: true)` on it. Best-effort (`try?`): if it
fails for some other reason, `ModelContainer`'s existing `fatalError` path
is still the real error handler, unchanged.

**Resolved — verified with real timestamps, not assumed: this race never
had any way to reach `reload()`, so it does NOT explain the historical
`visibleHabits.count=0` symptom.** `ModelContainer(for:configurations:)`
is a synchronous, throwing initializer — it does not return until the
store has fully finished loading, including whatever internal recovery
CoreData does for the missing-directory case. Confirmed with `os_log`
timestamps around a deliberately-reverted copy of the fix, on a genuinely
fresh install:

| Time | Event |
|---|---|
| T+0ms | `ModelContainer` init starts |
| T+34–52ms | `Failed to stat path` / `Sandbox access denied` cascade — entirely **inside** the init call |
| T+80ms | `ModelContainer` init **returns successfully** |
| T+3,518ms | `HomeView.reload()` starts |
| T+3,749ms | `fetchAll()` succeeds, count=0 |

`reload()` doesn't start until **3.4 seconds after** the store finished
initializing — `HomeView` can't even be constructed until
`ForgeApp.init()` returns, so by the time any view code runs, the race is
already over. The `count=0` in that log is the *correct* result for a
genuinely empty fresh install, not a swallowed failure. The directory fix
above is still worth keeping (it avoids the error-level log spam and the
internal recovery round-trip), but the empty-list symptom throughout the
tap-investigation sessions was something else — most likely just a
genuinely-empty test dataset at the time, not a store-readiness race.
`reload()`'s silent `try?` (and the same pattern elsewhere in
`HomeView.swift`) is still worth hardening on general principle, but it's
no longer a live suspect for this specific symptom.

---

## Home habit list — render cascade on day/week switch (RESOLVED)

**Symptom**: switching the selected day (or week) felt noticeably slower
after the completion-feedback work (`HabitCardRow`'s colored-card
animation, bounce/pulse effects, progress ring) landed. Investigated with
real measurements, not guesses: `xcrun xctrace record` (both `--attach`
and `--launch` modes) hung/failed to render in this environment across
multiple attempts, so verification used `os_log`-based timing instead —
temporary `Logger.fault(...)` calls at `HomeView.body`,
`HabitCardRow.body`, and around `reloadSelectedDayCompletions()`, captured
via `log stream` (the same technique already proven reliable earlier in
this file's history) — against a temporarily-seeded realistic dataset (18
habits, 60 days of varied history each, generated through the real
`habitRepository` APIs, not raw SQL).

**Two separate findings, only one of them a real regression:**

1. **SwiftData query cost is not the problem.** With clicks spaced widely
   enough to rule out actor-queueing artifacts, `fetchCompletions(for:)`
   consistently took 1–6ms per day switch once the store was warm — only
   the very first query after a fresh launch was slow (~2s, matching the
   `ModelContainer` cold-start cost above). The query is properly indexed
   and scoped; this candidate is ruled out.
2. **The real bottleneck: `HabitCardRow`'s bounce/pulse animations were
   firing on every day switch, not just on genuine taps.** They were
   originally driven by `.onChange(of: isComplete)` / `.onChange(of:
   count)` — correct-looking, since those "only" change on a real
   completion. But they *also* change on a day switch, which swaps in a
   different day's `completion` entirely — indistinguishable from a real
   tap at that level. Measured effect: a single day switch was firing 2-3
   rounds of `body` re-evaluation across roughly half the visible rows,
   spaced ~600ms apart (chained `withAnimation` grow/delay/settle calls
   multiplying across every row whose data happened to differ on the new
   day) — not just one clean pass.

**Fix**: added `InteractionToken` (`HomeView.swift`) — a fresh value set
by `handleTap` only on a genuine tap, threaded down to `HabitCardRow` as a
new `interactionToken` prop. The bounce/pulse `onChange` handlers now
watch `interactionToken` (comparing `habitID`) instead of `isComplete`/
`count` directly, so they only ever fire for the one row actually tapped
— a day/week switch never touches this value, for any row. The base
`cardAnimation` crossfade (background color, icon shape) is deliberately
unaffected — that one *should* animate on a day switch, showing the new
day's state; only the extra bounce layer needed to stop reacting to
incidental data changes.

**Measured before/after** (same test: fresh launch + 3 widely-spaced day
switches, 18 habits): `HabitCardRow.body` evaluation count dropped from
**71 to 44** across the 4 render triggers (18 initial + 3 switches) — 44
is exactly 4× 11 (the number of rows visible without scrolling), meaning
every trigger now produces exactly one clean pass with zero duplicate
re-evaluations, confirmed by timestamp (no more ~600ms-separated second
wave). Re-verified a genuine tap (toggling a habit off) still animates and
fires haptics/sound correctly after the change.

All temporary instrumentation (the `Logger`-based timing calls, the
18-habit/60-day seed generator) has been removed from `HomeView.swift`
after this investigation — none of it should be present in the current
code.

---

## Home tap-to-complete — synchronous blocking on MilestoneEngine + unconditional HealthKit call (RESOLVED)

**Symptom**: after the render-cascade fix above, day/week switching was
fast again, but ordinary actions — completing a habit, adding a habit,
general interaction — still felt slow. Investigated the same way:
`os_log`-based timing via `log stream` (xctrace/Instruments still doesn't
work in this environment; confirmed unusable again this round, not
re-litigated). The user's three suspects going in — `AudioServicesPlaySystemSound`
blocking main, `HabitCardRow`'s two-layer background/`deepCardTint()`
recomputing expensively, `InteractionToken`'s gating adding overhead — were
all directly measured and **ruled out**: `deepCardTint()` costs
0.002–0.037ms per call (negligible), haptics + sound together cost
20–50ms, and `InteractionToken`'s own overhead wasn't separately
measurable at all. The real causes were two, both real regressions
introduced by code adjacent to (but not literally inside) the
`CompletionFeedback`/`HabitCardRow` rewrite:

1. **`MilestoneEngine.afterCompletionLogged(habit:)` was awaited inline in
   `HomeView.handleTap`/`handleLongPress`.** Its three sub-checks
   (`checkHabitStreak` + `checkCategoryStreak` + `catchUpPointsAndChallenges`,
   each independently calling `fetchAll()` and looping day-by-day over the
   habit's/category's history) only add up to ~270ms of genuine work
   against 18 habits / 60 days — but the synchronous `await` chain, which
   bounces across two separate `@ModelActor`s (`habitRepository`,
   `milestoneRepository`), measured at **870–1080ms total**, several
   hundred ms of pure actor-hop/scheduling overhead on top of the real
   work — every single time, not a one-time cost (confirmed by tapping a
   second, different habit right after: still ~1070ms). None of this has
   any user-visible urgency in the Home list — the habit's completion
   state and the card's own visual state are already saved/updated before
   this even starts; milestones/streaks/points only ever surface on
   Progress/Milestones, which already call `MilestoneEngine.runCatchUp()`
   on appearing specifically so they self-heal independent of exactly when
   (or whether) a given tap's own check finishes.
   **Fix**: `dispatchMilestoneCheck(for:)` fires it in its own detached
   `Task { await milestoneEngine.afterCompletionLogged(habit: habit) } }`
   instead — `handleTap`/`handleLongPress` no longer wait on it at all.
   Matches CLAUDE.md's own Production Scaling Standard #3.
2. **`healthKitService.writeManualEntry(...)` was called whenever
   `healthKitDelta > 0`, with no check for `habit.isHealthKitTracked`
   first** — relying entirely on the function's own internal guard
   (`HealthKitTypeMapping.mapping(for: habit) != nil`) to no-op for a
   non-tracked habit. That guard is correct about *whether to write*, but
   getting to it still requires hopping onto `actor HealthKitService` and
   evaluating `HKHealthStore.isHealthDataAvailable()` — measured at a
   **consistent ~650–700ms** in this environment, on *every single
   completing tap*, for every one of the 18 seeded habits despite none of
   them being HealthKit-tracked. (This is very likely Simulator-specific
   HealthKit-daemon latency rather than a number that reproduces
   identically on-device, but the fix is free either way — it's dead work
   for the common case regardless of environment.) **Fix**: added
   `&& habit.isHealthKitTracked` at both call sites (`handleTap`,
   `handleLongPress`), skipping the actor hop entirely unless the habit
   actually maps to HealthKit.

**A methodological note worth keeping**: an early pass at isolating this
produced an apparent ~600–900ms "mystery gap" that didn't correspond to
any real code path — traced to *separate* `diagLog.fault(...)` calls
scattered across `handleTap` appearing out of chronological order in
`log stream` under heavy concurrent logging (multiple actors/threads all
logging at once). Switching to **one consolidated log line per tap**,
built from local `Date()` timestamps captured throughout the function and
printed atomically at the end, resolved the ambiguity and is what
actually surfaced both real findings above cleanly. If a future session
sees a timing gap that doesn't map to any specific code, suspect the
logging technique itself before the app.

**Measured before/after** (`handleTap`, real tap-to-complete, 18 seeded
habits, both fixes applied): a batch of 6 consecutive taps (2s apart) all
landed at **4.69–74.33ms** (median ~6ms), with `healthKit=0.00ms` on
every single one — versus **870–1541ms** before, with an additional
~650–700ms spike specifically on completing (not un-completing) taps pre-fix.
Roughly a **50–100× improvement**, consistent across repeated taps, not a
one-off warm-cache fluke.

**Add-habit flow**: not independently broken. Checked via code review
rather than fighting further UI automation — `HomeView.reload()` (called
after the add-habit sheet dismisses) only calls `fetchAll()` and
`fetchCompletions(for:)`, both already confirmed fast (1–6ms warm) in the
prior round's investigation, and doesn't touch `milestoneEngine` or
`healthKitService` at all. `HabitFormView.save()`'s own HealthKit calls
(`isConnected`, `requestAuthorization`) are already correctly gated behind
`healthKitMapping != nil` / `isNewHealthKitHabit` — they only ever fire
for a habit actually being set up as HealthKit-tracked. The perceived
slowness on "adding a habit" was the same two systemic causes above
surfacing on whatever completion-adjacent action followed, not a separate
bug in the add-habit path itself.

All temporary instrumentation (the `Logger`-based timing in `HomeView.swift`,
`CompletionFeedback.swift`, and `MilestoneEngine.swift`) has been removed
after this investigation.

**Not touched, on purpose**: 9 pre-existing build warnings (deprecated
`HKWorkout` initializer, two unnecessary `nonisolated(unsafe)`, four
unused `try?` results in `MilestoneEngine`, plus a missing-orientation-
support warning) are unrelated to this investigation — confirmed by
timing data, not assumed — and were left alone per explicit instruction to
treat that as a separate, lower-priority cleanup pass.

---

## Home weekly strip prefetch — actor-hop overhead investigated; one real fix shipped, one real problem still open (PARTIALLY RESOLVED)

**Symptom reported**: freezing specifically *during* the week-swipe/day-
selection gesture itself, 1-2 seconds — a precise enough symptom to
suggest a synchronous main-thread query. Investigated with `os_log`
timing plus an explicit `Thread.isMainThread`/`Thread.current` check
placed directly inside the `@ModelActor`-isolated fetch call (not just
around it), on both trigger points (`onChange(of: weekOffset)` →
`prefetch(around:)`, `onChange(of: selectedDate)` →
`reloadSelectedDayCompletions()`).

**What this ruled out:**
- Both `onChange` handlers already wrapped their query in `Task { await
  ... }` and returned in single-digit milliseconds — there's no literal
  "the onChange closure blocks" bug.
- `Thread.isMainThread` reported `true` inside the `@ModelActor` call on
  every single measurement — **including when the call was made via
  `Task.detached(priority: .userInitiated) { await self.prefetch(...) }`**,
  which by definition cannot inherit the caller's actor context. A
  genuinely detached task reporting `mainThread=true` means this specific
  check is **not a reliable signal in this Simulator environment** — don't
  trust it at face value in a future session without corroborating
  evidence. This was the single most surprising finding of this round.
- Neither `Task.detached` nor `Task(priority: .userInitiated)` changed the
  measured timing at all (day-select: 43-49ms either way; week-range
  query: 452-500ms either way) — ruled out as fixes, reverted back to
  plain `Task { }`.
- Payload size crossing the actor boundary: `fetchCompletions(from:to:)`
  returning 594 raw `Completion` rows showed the same ~450-500ms overhead
  as a new `fetchCategoryCompletionRates(habits:from:to:)` method (added
  this round) that aggregates *inside* the actor and returns only ~35
  compact day-rate tuples. Reducing the returned payload by ~17× did not
  reduce the overhead — this was genuinely surprising and contradicted the
  working hypothesis at the time.

**What's real and still unexplained**: calling the same range-query
repeatedly within one session gets **progressively slower, and does not
recover with a pause**. Measured back-to-back calls to
`fetchCategoryCompletionRates` in the same session: call 1 ~485ms, call 2
~1635ms, call 3 ~1585ms, call 4 (issued after an explicit 1-second
`Task.sleep`) ~1397ms. Confirmed this isn't an artifact of the diagnostic
logging itself — `syncPrepMs` (pure synchronous prep time, no actor call,
measured immediately before each query) stayed flat at 0.12-1.43ms across
all four calls, so whatever is slowing down is genuinely inside the
`@ModelActor` call, not in surrounding instrumentation. `ModelContext`
has no `.reset()` in this SwiftData version (only `rollback()` and
`processPendingChanges()`, neither of which is documented to clear a
tracked-object registry) — attempted and reverted, since it didn't even
compile. **This looks like accumulating state inside the long-lived
`@ModelActor`'s single `ModelContext` across repeated fetches — a
known general class of SwiftData issue — but the exact mechanism and a
verified fix were not found within this session's scope.**

**Fix shipped**: `HabitRepository.fetchCategoryCompletionRates(habits:
from:to:)` (implemented in both `SwiftDataHabitRepository` and
`InMemoryHabitRepository`) moves the day/category rate aggregation that
`WeeklyRingsPagerView.prefetch` used to do itself into the repository,
returning a small `[Date: (good: Double, bad: Double, todo: Double)]`
instead of every raw `Completion` row in range. This is a real
improvement in its own right (smaller actor-boundary payload, an
additional `isComplete == true` predicate filter pushed into SQL rather
than filtered in Swift after fetching) even though it did **not** turn
out to be the fix for the specific compounding-slowdown symptom above —
worth keeping regardless, but don't mistake it for having closed out this
investigation.

**Recommended next step, explicitly not done this session**: test on a
**real device**, not Simulator. Two separate findings this round
(`Thread.isMainThread` lying for genuinely detached work; a repeated-call
slowdown that a 1-second pause doesn't fix) are exactly the kind of thing
that can be Simulator-specific SwiftData/Concurrency behavior rather than
something that reproduces identically on-device — this project's own
history (the tap-to-select-day investigation above) already has one
precedent for Simulator-only behavior that didn't hold on real hardware.
If the 1-2 second freeze reproduces on-device with the same
"gets worse on repeated calls, a pause doesn't help" signature, the next
angle worth trying is recreating the `ModelContext` (or the whole actor)
periodically rather than keeping one single long-lived context for the
app's entire session — but that's a real architectural change and should
be evidence-driven from on-device measurements, not spec'd from Simulator
data alone.

All temporary instrumentation (the `os_log` timing and thread-identity
checks in `WeeklyRingsPagerView.swift`, `HomeView.swift`, and
`SwiftDataHabitRepository.swift`) has been removed after this
investigation. The `fetchCategoryCompletionRates` fix remains.

---

## Home weekly strip freeze — root cause found: MainActor continuation-resumption latency, not query time (PARTIALLY RESOLVED)

**This round's instruction was to build a full execution-timeline trace of
one week-swipe** (every function, call order, timestamp, duration, thread,
actor, invocation count), specifically checking whether the two `onChange`
handlers block synchronously on the main thread. Two hard blockers changed
what could actually be tested:

1. **No physical device was reachable.** Both paired iPhones showed
   `unavailable`/offline via `devicectl`/`xctrace` — not connected/unlocked
   at the time. Per explicit instruction, Simulator was used only after
   flagging this and getting confirmation to proceed anyway; every number
   below is Simulator-only and unconfirmed on hardware.
2. **A literal finger-swipe could not be synthesized in Simulator at
   all**, extending (not just repeating) the tap-to-select-day
   investigation's existing finding. Three distinct `cliclick` drag styles
   were tried (fast/coarse, slow/granular, held-then-drag) targeting the
   strip's real on-screen coordinates — coordinate accuracy was
   independently verified by a plain tap that correctly navigated to the
   Progress tab. All three drags produced zero effect: `weekOffset` never
   changed, no `onChange` fired. **Mouse-drag synthetic input does not
   register as a page-swipe gesture in this Simulator environment**, on
   top of the prior finding about taps on `TabView(.page)` content. An
   XCUITest target (real touch injection, the one thing previously
   confirmed to work for gesture-driven interaction here) was considered
   but not built this round — it requires adding a new target to
   `Forge.xcodeproj`, a persisting project change, and was deferred
   pending user direction.

**Given that, the trace instead captured the *identical* code path a swipe
triggers** — `prefetch(around:)` → `fetchCategoryCompletionRates`, and
`reloadSelectedDayCompletions` → `fetchCompletions(for:)` — fired via
`.task` at app launch instead of via `.onChange(of: weekOffset)` from a
gesture. Instrumentation logged an atomic one-line-per-event record (global
monotonic sequence number, `DispatchTime.now().uptimeNanoseconds`,
`Thread.isMainThread`, raw kernel thread id via `pthread_mach_thread_np`,
and a log-free in-memory counter for high-frequency call sites) on both
sides of every `await` boundary — inside the `@ModelActor` method itself
*and* in the calling `Task` right before/after the `await` — which is what
finally made the real mechanism visible.

**The finding**: the query was never slow. What's slow is Swift
Concurrency resuming the suspended caller after the actor call finishes.
Measured on a clean relaunch (9 real habits, no other test data
confound — see caveat below):

| Call | Actor-internal time | Caller-observed time | Gap (pure resumption latency) |
|---|---|---|---|
| `fetchCompletions(for:)` | **2.6ms** | **2368.7ms** | ~2366ms (99.9% of observed time) |
| `fetchCategoryCompletionRates` | **95.7ms** (incl. 91.8ms real SQLite fetch) | **902.8ms** | ~807ms (89.4% of observed time) |

This directly reconciles every prior round's confusion: measuring only
from the caller's side (before-`await` to after-`await`) — which is what
every previous round did — necessarily conflates real actor work with this
resumption gap, making a 2.6ms query look like a 2368ms one. It also
explains why `Task.detached`/priority elevation never helped (tested two
rounds ago): the delay isn't in how the query's `Task` is scheduled, it's
in how long the MainActor takes to get back around to resuming it.

**A direct, falsifiable test of one contributing cause**: the two
resumption gaps captured above both occurred with *zero* other
instrumented code executing in between — ruling out "other visible SwiftUI
work is hogging the actor" as the full explanation, and pointing instead
at uninstrumented work happening after `WeeklyRingsPagerView.body` returns
(SwiftUI's own internal diff/commit/layout pass over the returned view
tree, which is not bounded by the `body` *property's* own measured
runtime). The prime suspect: `ForEach(Self.minWeekOffset...0, id: \.self)`
ranges over **5201 elements** (`minWeekOffset = -5200`, ~100 years back).
Confirmed `pageView`'s content closure is called **zero times** inside
`body`'s own measured window across 69 captured passes — so the ForEach
isn't literally evaluating 5201 view bodies synchronously — but SwiftUI
still has to diff/reconcile that many identities against the previous
tree on every state change, and that reconciliation isn't bounded by the
`body` getter's own timer.

Tested directly by temporarily changing `minWeekOffset` to `-8`, rebuilding,
and re-running the identical launch trace:

| Call | Gap at `minWeekOffset = -5200` | Gap at `minWeekOffset = -8` | Reduction |
|---|---|---|---|
| `fetchCompletions(for:)` | ~2366ms | ~389ms | ~6× |
| `fetchCategoryCompletionRates` | ~807ms | ~240–495ms (2 samples) | ~2–3× |

**This is a real, causal, reproducible contributing factor — confirmed,
not guessed — but not the whole story.** Even at a 9-page range, a
~240–490ms resumption gap remained. So there are (at least) two stacked
causes: (1) `ForEach` range size measurably inflates post-body SwiftUI
reconciliation cost, which delays MainActor's return to pending
continuations — proven by the direct before/after test above; and (2) a
residual baseline MainActor-resumption latency independent of range size,
whose exact mechanism is still unidentified. `minWeekOffset` was reverted
to `-5200` immediately after this test — do not ship `-8`, it caps history
browsing at 8 weeks.

**Data-integrity note, unrelated to the investigation itself**: when this
round's session first attached to the already-booted Simulator, a "Delete
Habit? 'Limit Screen Time'" confirmation was already on-screen, and the
habit count dropped from 18 to 9 over the following ~97 seconds with zero
input from this session — then one more real habit ("Stretch") disappeared
after a clean relaunch, again without this session touching the habit
list (only the strip and tab bar were tapped, confirmed by screen
coordinates). Grepped the codebase: deletion only happens via the
explicit alert's Delete button (`HomeView.swift`, `delete(_:)`) — nothing
autonomous exists. This looks like concurrent, unrelated activity on the
same Simulator (possibly manual testing) that predated this session, not
something this investigation did — flagged to the user directly, not
confirmed resolved.

**Recommended next steps, not done this session**:
1. **Real device test** is still the most important unblock — everything
   above is Simulator-only, and this project has one prior precedent
   (tap-to-select-day) of Simulator-only behavior that didn't hold on
   hardware. The MainActor-resumption-latency finding, in particular,
   needs on-device confirmation before treating it as production-real
   rather than a Simulator/Debug-build artifact.
2. **A minimal XCUITest target** would allow genuine synthetic touch
   injection for a literal captured swipe in Simulator (still not
   hardware, but real touch events rather than a mouse-drag translation
   that's now confirmed not to register at all). Not built this round —
   requires adding a target to `Forge.xcodeproj`, a persisting project
   change, deferred pending direction.
3. **The residual ~240–490ms resumption gap** (present even with a
   9-element `ForEach`) still needs its own root cause — not yet
   identified. `Thread.isMainThread` reported `true` for literally every
   one of 456 captured events this round, including ones now proven (via
   the actor-vs-caller timestamp gap) to span a real suspension — treat
   it as confirmed unreliable in this environment, not just suspected.

All temporary instrumentation (the atomic-event tracer and every call site
referencing it in `WeeklyRingsPagerView.swift`, `HomeView.swift`, and
`SwiftDataHabitRepository.swift`) has been removed after this
investigation; `minWeekOffset` is back to `-5200`. No fix was shipped this
round — this was a pure measurement/diagnosis pass, per explicit
instruction not to optimize.

---

## Home weekly strip — "both directions rubber-band, nothing pages" bug report (RESOLVED — not a code bug)

A follow-up bug report claimed the windowed-pager rewrite (the
`centerWeekOffset`/`pageSelection` design) broke paging in **both**
directions — smooth swipe motion, but always snapping back to the current
week, with three specific hypotheses to check: (1) `onChange(of: habits)`
re-clamping `centerWeekOffset` back before a recenter's effect registers,
(2) the recenter transaction not actually committing, (3)
`visibleRelativeOffsets` not recomputing after a `centerWeekOffset` change.

**This finally got real gesture testing working in Simulator.** Every
prior round in this file gave up on synthesizing a swipe (`cliclick`
mouse-drag never registers on `TabView(.page)` content here). This round
built a minimal `ForgeUITests` XCUITest target (`project.yml` +
`xcodegen generate`) instead — XCUITest's `XCUIElement.swipeLeft()` /
`.swipeRight()` go through the real accessibility/touch-injection path,
not a synthesized mouse event, and this **worked** on the first real
attempt. Two accessibility identifiers were added permanently for this:
`weeklyStrip.dateLabel` (the date `Text`) and `weeklyStrip.tabView` (the
`TabView` itself — note it surfaces to the accessibility tree as a
`CollectionView`, not `Other`; querying `app.otherElements[...]` silently
finds nothing). `ForgeApp.init()` also permanently gained a `-uiTesting`
launch-argument path: it switches `ModelConfiguration` to
`isStoredInMemoryOnly: true` and synchronously seeds one habit with
`startDate` 8 weeks back via a direct `ModelContext` insert (not the async
repository — avoids a race against `HomeView`'s own `.task { reload() }`).
This never touches the real on-device store.

**Root cause: not a code bug at all.** The device's actual data at the
time of the report had exactly one non-archived habit ("Less Social
Media"), with `startDate` one day before "today" — both fall in the same
calendar week regardless of locale's first-weekday setting, so
`minWeekOffset` (derived from the earliest `habit.startDate`) computed to
`0`, identical to `centerWeekOffset`. `visibleRelativeOffsets` therefore
only ever contained `[0]` — the `TabView(.page)` genuinely had exactly one
page. Confirmed directly (not inferred) by dumping the real, unmodified
app's accessibility hierarchy via a UI test with no `-uiTesting` flag: the
strip's scroll bar reported `"Vertical scroll bar, 1 page"`, and a real
injected `swipeRight` left the date label unchanged (`24 Jul 2026` → `24
Jul 2026`) — genuine native rubber-banding with nowhere to go,
indistinguishable from a bug without checking the underlying data.

With the `-uiTesting` seed (8 weeks of real history, so `minWeekOffset`
was comfortably negative), the identical strip reported `"2 pages"`, and
an automated 4-swipe round trip (back → back → forward → forward, each
step asserting the date label read the exact expected day) passed cleanly
using real touch injection — confirming all three of the report's
hypotheses were wrong: `habits` never changes during a swipe (only
`HomeView.reload()` mutates it, called from `.task`/add-edit-delete sheet
dismissals — nothing on the swipe path), the recenter transaction commits
and holds, and `visibleRelativeOffsets` recomputes correctly on both
boundaries. The already-in-place `DispatchQueue.main.async`-deferred
recenter is correct and was not touched.

**Fix**: none needed to the pager logic itself. The `PagerDebugLog`
diagnostic logging left over from that prior round (marked "delete once
confirmed working," never actually removed) was deleted along with both
its call sites, now that it's genuinely confirmed. If a future session
sees "swipe does nothing" again, check `minWeekOffset` / the earliest
active habit's `startDate` before assuming a recenter regression.

**Kept permanently, by explicit user choice**: the `ForgeUITests` target,
`ForgeUITests/WeeklyPagerSwipeTests.swift`
(`testSwipeBackwardThenForwardRoundTrips`), the `-uiTesting` seed path in
`ForgeApp.swift`, and the two accessibility identifiers — this project's
first real gesture-regression test, and the only reliable way found so
far to verify swipe/drag behavior in this environment without a connected
physical device. Run it with:
```
xcodebuild test -project Forge.xcodeproj -scheme Forge \
  -destination "id=<simulator-udid>" \
  -only-testing:ForgeUITests/WeeklyPagerSwipeTests
```

---

## Progress page / mood check-in — screenshot methodology detail

Full detail behind the short pointer left in `CLAUDE.md`'s "Progress page
redesign (§6) + daily mood check-in (§13)" section, which otherwise stays
in `CLAUDE.md` as still-relevant architecture documentation (not moved
here, since it explains current, still-true design decisions):

The real on-device Simulator data at the time (one habit, ~1 day of
history) would've rendered every new card as empty/degenerate. Rather
than screenshot that, or touch real device data, a temporary
`-demoScreenshots` launch-arg flag (mirroring `-uiTesting`'s existing
in-memory-store pattern) seeded 6 habits across all 3 categories with 90
days of weekday-biased, gap-containing history plus 30 days of varied
mood entries — enough for every new chart to render meaningfully.
Confirmed real Simulator screenshots at three scroll checkpoints, using
precise log-marker-triggered capture (`print()` a named checkpoint right
before a long `sleep()`, then block an external `simctl io screenshot`
call on that log line appearing, rather than guessing timing) — blind
duration-based timing was tried first and mis-fired twice (one capture
accidentally landed on the Home Screen because `app.swipeUp()` on the
whole `XCUIApplication` — rather than on the specific scroll view —
triggered the system swipe-up-for-Home-Screen gesture instead of an
in-app scroll). `DemoScreenshotSeedData.swift` and the `-demoScreenshots`
flag were removed after the screenshots were captured — they were a
one-off demo tool, not kept the way `ForgeUITests`/`-uiTesting` was (that
one earns its keep as an ongoing regression test; this one doesn't).

---

## Timer pause/resume — superseded "no pause concept" original decision

Full detail behind the short pointer left in `CLAUDE.md`'s timer section
(the current, active model is the accumulated-elapsed pause/resume design
described there — this entry is purely the superseded prior decision,
kept for history only):

The timer originally had no pause concept: a second tap while running
cancelled it (cleared `startedAt`), only start/cancel/instant-complete
existed. This was reversed on 2026-07-30 when the Live Activity was
redesigned to match Apple's Workout Live Activity (icon / countdown /
pause-resume pill, Lock-Screen scope) — seed genuine pause/resume, banking
elapsed time in `Completion.accumulatedElapsed` rather than losing
progress on a second tap. The current behavior (in `CLAUDE.md`) is
pause/resume from the Live Activity plus in-app start/resume-or-cancel.
