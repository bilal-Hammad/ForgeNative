# Forge — Current-State Feature Inventory (Phase 0, Swift Rewrite Planning)

**Scope note:** this document reflects only what exists in the codebase *right now*, verified against actual file contents as of this writing — not git history. Anything built and later removed is intentionally absent. Ambiguous or dead-looking code is flagged explicitly rather than silently included or excluded.

---

## 1. Screens / Routes

| Route | File | Type | Description |
|---|---|---|---|
| `/` | `app/(tabs)/index.tsx` | Tab screen | "Today" screen — day strip, sorted habit list, mood selector, counter/track/timer logging modals. Reads `useHabitStore`, `useMoodStore`, `useSettingsStore`; HealthKit sync via `useHealthKitSync`. |
| `/progress` | `app/(tabs)/progress/index.tsx` | Tab screen (nested Stack) | Stats cards, weekly completion grid, 7-day bar chart, per-habit streaks. |
| `/profile` | `app/(tabs)/profile/index.tsx` | Tab screen (nested Stack) | Brand header, "Manage Habits" / "Edit Templates" links, Apple Sign-In/out, version row. |
| `/templates` | `app/templates.tsx` | Stack screen | Main habit-template browser (category chips, search, custom sections), includes its own inline HealthKit permission flow. Pushes to `/habit/new`. |
| `/habit/new` | `app/habit/new.tsx` | Stack screen | Full habit-creation form (icon/color, goal/unit, repeat mode, dates, reminders/Calendar/Reminders toggles). Accepts template params via search params. |
| `/habit/[id]` | `app/habit/[id].tsx` | Stack screen, **modal presentation** | Edit/delete an existing habit; mirrors `new.tsx` fields. |
| `/habits` | `app/habits.tsx` | Stack screen | "Manage Habits" list, streak/points meta, delete-confirm, "+ New" button. |
| `/edit-templates` | `app/edit-templates.tsx` | Stack screen (route exists, no explicit `Stack.Screen` entry in root layout) | Reorder/hide/restore built-in sections, create/delete custom sections. |
| `/edit-section/[id]` | `app/edit-section/[id].tsx` | Stack screen (same: implicit route) | Edit one custom section's name/icon/habit list. |
| `/settings` | `app/settings.tsx` | Stack screen | Appearance, general, sounds, notifications, data (links below), export/reset/delete, support. |
| `/settings-theme` | `app/settings-theme.tsx` | Stack screen | Mode, accent color, custom gradient background + live preview. |
| `/settings-archived` | `app/settings-archived.tsx` | Stack screen | Archived habits list, unarchive action. |
| `/settings-vacations` | `app/settings-vacations.tsx` | Stack screen | Placeholder ("Coming Soon"). |
| `/settings-achievements` | `app/settings-achievements.tsx` | Stack screen | Placeholder ("Coming Soon"). |
| `/settings-stub` | `app/settings-stub.tsx` | Stack screen (registered in root Stack) | Generic placeholder. **Orphaned — see §9.** |
| `/health-templates` | `app/health-templates.tsx` | Stack screen (implicit route, no `Stack.Screen` entry) | Standalone Apple Health template picker. **Orphaned — see §9.** |

## 2. Navigation Structure

```
app/_layout.tsx  (root Stack; hydrates all stores on mount, AppState reconciliation,
                  notification-action listener, animated splash, optional gradient bg)
 └─ (tabs)/_layout.tsx  — Tabs with tabBar={() => null}; <BottomNav/> rendered as an
    │                     absolutely-positioned sibling overlay, NOT part of the Tabs tree
    ├─ index.tsx                       → "/"
    ├─ progress/_layout.tsx (Stack) →  progress/index.tsx  → "/progress"
    └─ profile/_layout.tsx  (Stack) →  profile/index.tsx   → "/profile"
 ├─ templates.tsx, habit/new.tsx, habits.tsx, habit/[id].tsx (modal)
 ├─ settings.tsx, settings-theme.tsx, settings-archived.tsx,
 │  settings-vacations.tsx, settings-achievements.tsx, settings-stub.tsx
 └─ edit-templates.tsx, edit-section/[id].tsx, health-templates.tsx  (implicit routes)
```

- **Tab bar is fully custom**, not Expo Router's built-in `Tabs` bar (which is explicitly suppressed via `tabBar={() => null}`). See §6 for the native-bridge detail.
- **profile/** and **progress/** each get their own single-screen nested `Stack` purely to obtain a native large-title header — Expo Router's `Tabs` has no native large-title support at all.
- **No `<Link>` usage anywhere** — all navigation is imperative via `useRouter()`'s `.push`/`.navigate`/`.replace`/`.back()`.
- Template selection flow: `templates.tsx` / `health-templates.tsx` → `router.push('/habit/new', { params: {...} })` carrying `templateId`, `title`, `icon`, `color`, `habitType`, `unit`, `goal`, `healthKitType`, `step`, `repeatMode`, `scheduleDays`, `weeklyTarget`, `intervalDays`.
- `EmptyState.tsx` (generic `actionHref` prop) and `AddHabitRow.tsx` both point at `/templates`.
- `BottomNav.tsx` navigates via `router.navigate(path)` for `/`, `/progress`, `/profile`.

## 3. Native Integrations

### Calendar & Reminders (EventKit)
- **File:** `src/services/calendarService.ts` (sole importer of `expo-calendar`), lazy-`require`'d to avoid crashing in Expo Go.
- Maintains one dedicated "Forge Habits" **calendar** (Events) and one dedicated "Forge Habits" **reminder list**, each found-or-created once and cached in AsyncStorage (`@forge/forgeCalendarId`, `@forge/forgeReminderListId`).
- One recurring calendar event and/or one recurring reminder per habit, built from the habit's own repeat schedule (weekly-target / every-X-days / specific-days / daily), with a documented EventKit-vs-dayjs weekday-offset conversion.
- Contains defensive logic (heavily logged) to correctly pick the Reminders-capable "iCloud" `EKSource` when two same-named sources exist (only one is Reminders-capable) — a real bug fixed earlier in this project's history, now load-bearing logic.
- Permission requests: `requestCalendarPermission()`, `requestRemindersPermission()` — called from `habit/new.tsx` and `habit/[id].tsx` toggle handlers.
- Reconciliation: `src/data/reminderReconciliation.ts` re-syncs when a habit's "smart" reminder time drifts.

### Notifications
- **File:** `src/notifications/reminders.ts` (sole importer of `expo-notifications`), also lazy-loaded.
- Interactive category `forge-counting-habit` with three actions (Mark Completed / +1 / Skip), applied only to counting habits.
- Fixed daily/weekly reminders (branches per repeat mode) **and** frequency-mode reminders (evenly-spaced or fixed-interval slots for the rest of today, counting habits only).
- Self-imposed 60-notification budget (iOS caps at 64).
- Action taps handled in `app/_layout.tsx`, dispatching to `useHabitStore`'s `logCount`/`skipHabit`.
- Permission requested at launch (`app/_layout.tsx`) if enabled in settings, and from the Settings toggle.

### HealthKit
- **Library:** `@kingstinct/react-native-healthkit` (not `react-native-health`).
- **File:** `src/services/HealthKitService.ts` — **read-only**: steps, active energy, flights climbed, water, caffeine, body mass/lean mass/fat %/height, blood glucose (presence-only), sleep, mindful minutes, stand hours, handwashing, blood pressure (presence-only), 10 workout types. Dietary alcohol is unsupported by the library version and hardcoded to 0.
- Consumed by `src/hooks/useHealthKit.ts` (`useHealthKitSync` — polls on mount/date-change/foreground/60s interval; throttled and de-duplicates authorization requests to avoid a documented real bug) and by the template-selection flow in `templates.tsx`/`health-templates.tsx`.
- **Flag:** `NSHealthUpdateUsageDescription` (write) and the `healthkit.background-delivery` entitlement are both present, but **no write code or background-delivery/observer-query code exists anywhere** — the app only ever reads, via polling. Carry this mismatch into rewrite planning rather than assuming background HealthKit sync exists today.

### Apple Sign-In
- **Files:** `src/store/useAuthStore.ts`, `app/(tabs)/profile/index.tsx`.
- `AppleAuthentication.signInAsync()` → identity token handed to **Supabase** (`supabase.auth.signInWithIdToken({provider:'apple', ...})`) — Apple Sign-In is the credential source only; Supabase is the actual session/auth backend. A Swift rewrite needs a Supabase-compatible (or replacement) session layer, not just `ASAuthorizationAppleIDProvider`.

### Live Activities (ActivityKit)
- **Files:** `src/widgets/HabitTimerActivity.ios.tsx` (SwiftUI layout via `@expo/ui/swift-ui`, native OS-ticking countdown via `Text(timerInterval:...)`), Android/other stub at `HabitTimerActivity.tsx`, types in `HabitTimerActivity.types.ts`, thin re-export `src/modules/HabitLiveActivity.ts`.
- Backed by the `expo-widgets` package (ActivityKit bridging) — **no hand-authored native Swift/ActivityKit source exists in this repo**; the widget extension's only Swift file (`ios/ExpoWidgetsTarget/index.swift`) is a 10-line generated entry point deferring to the internal `ExpoWidgets` package. A Swift rewrite will need to author `Activity`/`ActivityAttributes`/Widget code from scratch, using the JS layout/props files as the functional spec.
- Session state (start/pause/resume/end) persisted to AsyncStorage (`@forge/activeTimerSession`); `app/_layout.tsx` reconciles/finalizes a completion if the Live Activity's countdown finished while the app was closed.
- Uses an App Group (`group.com.bilalhammad.forge`) to share data with the widget extension.

### `@expo/ui/swift-ui` — Bottom Tab Bar ("Forge glass")
- **File:** `src/components/BottomNav.tsx` — the app's fully custom tab bar, real native iOS 26+ Liquid Glass rendering (not an approximation) via `Host`, `GlassEffectContainer`, `Capsule`, `Namespace`, `HStack`, `ZStack`, `RNHostView`, and the `glassEffect`/`glassEffectId`/`frame`/`opacity` modifiers.
- Two native glass layers: the bar's own background capsule, and a per-tab resting-capsule (currently 'regular'/'clear' variants respectively, tuned iteratively on-device — see recent history for exact rationale, since these specific variant choices have flipped more than once based on real-device visual feedback).
- Touch handling is **entirely custom, on the RN side**, via a single `PanResponder` (not React Navigation, not native `onTapGesture`) — deliberately unified after discovering that a native SwiftUI gesture recognizer stacked alongside an RN one caused touch-ownership conflicts. Recognizes plain taps vs. a press-and-drag "lens" gesture (an enlarged floating glass bubble that follows the finger and switches tabs on release over a different zone), positioned using RN-owned absolute layout after an earlier SwiftUI-coordinate-space bug was found and fixed.
- **Important for the rewrite:** `@expo/ui` is a real, load-bearing runtime dependency of this component (and of the Live Activity's SwiftUI layout) but does **not appear in `package.json`** at all — it's only present transitively (pinned in `package-lock.json` via another Expo package). A native rewrite obviously replaces this with real SwiftUI directly, but it's worth noting for anyone tracking "what's actually installed" that the manifest alone understates what's in use.

### Other Apple-framework-adjacent items
- `expo-haptics` — tab bar gestures, template selection, main list interactions.
- React Native's built-in `Linking` (not `expo-linking`, which is unused) — `mailto:` support link, `openSettings()` deep-link after permission denials.
- App Groups + `NSSupportsLiveActivities` / `NSSupportsLiveActivitiesFrequentUpdates` (frequent updates explicitly off) — see entitlements table below.
- `expo-glass-effect` package: **not used** — don't conflate with `@expo/ui/swift-ui`, which is what actually implements the glass tab bar.

## 4. Permissions & Entitlements

**`ios/Forge/Info.plist`:**

| Key | Feature |
|---|---|
| `NSCalendarsFullAccessUsageDescription` / `NSCalendarsUsageDescription` | `calendarService.ts` events |
| `NSRemindersFullAccessUsageDescription` / `NSRemindersUsageDescription` | `calendarService.ts` reminders |
| `NSHealthShareUsageDescription` | HealthKit reads |
| `NSHealthUpdateUsageDescription` | **No corresponding write code exists** — flag |
| `NSSupportsLiveActivities` = true / `NSSupportsLiveActivitiesFrequentUpdates` = false | Habit Timer Live Activity |
| `ExpoWidgetsAppGroupIdentifier`, `ExpoWidgets_EnablePushNotifications` = false | Widget/Live Activity plumbing |
| `CFBundleURLTypes` (schemes `forge`, `com.bilalhammad.forge`) | Deep linking / expo-router |

No camera, microphone, location, contacts, Face ID, motion, photo library, or Bluetooth keys exist — confirms none of those features exist anywhere in the app today.

**`ios/Forge/Forge.entitlements`:**

| Key | Value | Feature / flag |
|---|---|---|
| `aps-environment` | `development` | **No remote-push code exists anywhere** — flag |
| `com.apple.developer.applesignin` | `[Default]` | Apple Sign-In |
| `com.apple.developer.healthkit` | `true` | HealthKit |
| `com.apple.developer.healthkit.access` | `[]` | No clinical record types declared |
| `com.apple.developer.healthkit.background-delivery` | `true` | **No background-delivery/observer-query code exists** — app polls instead — flag |
| `com.apple.security.application-groups` | `[group.com.bilalhammad.forge]` | Widget/Live Activity shared storage |

**`ios/ExpoWidgetsTarget/ExpoWidgetsTarget.entitlements`:** same App Group only.

## 5. Third-Party Dependencies

**Confirmed used** (with primary call sites): `@kingstinct/react-native-healthkit`, `@react-native-async-storage/async-storage`, `@react-native-community/datetimepicker`, `@supabase/supabase-js`, `dayjs`, `expo` (framework), `expo-apple-authentication`, `expo-calendar`, `expo-device`, `expo-haptics`, `expo-notifications`, `expo-router`, `expo-splash-screen`, `expo-widgets`, `react`, `react-native-safe-area-context`, `react-native-screens`, `react-native-svg`, `zustand`.

**Confirmed unused (zero references, safe to drop from a rewrite dependency list):**
- `expo-blur` — explicitly superseded by `@expo/ui/swift-ui`'s real glass material (a code comment in `BottomNav.tsx` documents the replacement).
- `expo-status-bar` — no `<StatusBar>` usage anywhere.
- `react-native-draggable-flatlist` — already documented in `CLAUDE.md` as intentionally removed/incompatible; still listed in `package.json` but must not be reintroduced.

**Implicit/transitive use (not directly imported, but not "dead" either):**
- `expo-asset`, `react-native-web`, `react-dom` — support Expo's asset pipeline and the web target (`app.json`'s `web.bundler`), not directly imported in app code.

**Load-bearing but undeclared:**
- `@expo/ui` — see §3 above. Actively used by both `BottomNav.tsx` and `HabitTimerActivity.ios.tsx`, but absent from `package.json`'s dependency list entirely (present only via transitive resolution).

## 6. Data Layer

Five Zustand stores in `src/store/`, no middleware — this project uses a manual persist convention (see `CLAUDE.md`), though not perfectly uniformly (flagged below).

| Store | Manages | Persistence | Backend |
|---|---|---|---|
| `useHabitStore` | `Habit[]`, `Completion[]` | Via a **repository abstraction** (`src/data/asyncStorageRepository.ts` implementing `HabitRepository`) — the one store that doesn't use the plain `_persist()` convention directly. Keys: `@forge/habits`, `@forge/completions` (+ legacy `@momentum/*`, migrated once). | None — local-only |
| `useSettingsStore` | Accent color, custom gradient bg, week-start, day-start offset, future-dates toggle, badges/sounds, notifications-enabled | Manual `AsyncStorage.setItem`, key `@forge/settings` (+ legacy, migrated) | None — local-only |
| `useMoodStore` | `MoodEntry[]` (bucketed or 0–100 numeric) | Manual `AsyncStorage.setItem`, key `@forge/moods` (+ legacy, migrated) | None — local-only |
| `useTemplateSectionStore` | Section order/hidden IDs per category, custom sections | Textbook `_persist(patch)`, key `@template_sections_v1` (**no legacy-key migration**, unlike the other four) | **Yes** — only store synced to Supabase |
| `useAuthStore` | Supabase `Session`/`User`, Apple Sign-In flow | None of its own — delegated to Supabase client's own AsyncStorage-backed session storage | Directly wraps `supabase.auth` |

**Supabase sync** (`templateSectionSync.ts` + `supabaseClient.ts`): login pulls remote state (remote wins per category on conflict, ID-collision-aware union for custom sections) or pushes local state up if remote is empty; every subsequent local mutation debounces a push by 2s; custom-section deletion pushes an immediate `DELETE`; sign-out unsubscribes.

**`supabase/schema.sql` tables:**
1. `user_template_settings` — consumed, per-user/category.
2. `custom_sections` — consumed, client-generated `cs_xxx` IDs.
3. `shared_sections` — **defined with full RLS but zero consuming code anywhere in `app/`/`src/`** (confirmed by grep, matching `CLAUDE.md`'s own note that no route handler exists yet). Its header comment still says `momentum://section/<code>` — a stale scheme reference from before the `forge` rename.
4. `official_sections` — **also zero consuming code anywhere.** Decide explicitly whether to carry either of these into the rewrite or drop them; they are schema-only today.

## 7. State Management

Only two `createContext` usages in the whole app:

- **`LanguageContext`** (`src/i18n/LanguageContext.tsx`) — current language, RTL flag, `t()` translator. Persists to `@app_language` (no legacy migration). Drives a real native effect: `I18nManager.allowRTL`/`forceRTL`. Independent of all stores.
- **`ThemeContext`** (`src/theme/ThemeContext.tsx`) — resolved color/spacing/radius tokens, dark-mode resolution (OS or explicit), custom background. Persists only its `mode` field (`@forge/theme_mode` + legacy). **Directly reads `useSettingsStore`** for accent color and custom-background fields — the one clear cross-boundary coupling between the context layer and the store layer.

Auth has no context wrapper at all — it's a plain Zustand store (`useAuthStore`) read directly by `app/_layout.tsx` and the profile screen. Auth state changes are what start/stop `useTemplateSectionStore`'s Supabase sync subscription — the one place two otherwise-independent stores are linked.

## 8. Consolidated Flags for Rewrite Planning

1. **`/health-templates`** and **`/settings-stub`** routes exist but are unreachable from any navigation call anywhere in the app (confirmed by grep — only a code *comment* references health-templates, and settings-stub is registered in the root Stack but never pushed to). Both read as dead screens left over from earlier iterations; decide explicitly whether to port them.
2. **HealthKit write capability and background delivery are declared (Info.plist + entitlements) but not implemented** — the app is read-only, polling-based today, despite the manifest suggesting otherwise.
3. **Push notification entitlement (`aps-environment`) is present with zero remote-push code** — all current notifications are local-only via `expo-notifications`.
4. **`@expo/ui` is a real, load-bearing dependency absent from `package.json`** — don't assume the manifest is a complete picture of what's in use.
5. **`expo-blur`, `expo-status-bar`, `react-native-draggable-flatlist`** are installed but unused — safe to leave out of rewrite planning.
6. **`shared_sections` and `official_sections`** Supabase tables are fully defined (with RLS) but have no consuming code anywhere — schema-only, unimplemented features requiring an explicit include/drop decision.
7. **`useHabitStore`'s persistence uses a repository-abstraction pattern**, inconsistent with the other four stores' direct `_persist()` convention — worth a deliberate decision (normalize or preserve) rather than assuming uniformity.
8. **Two different legacy-AsyncStorage-key migration behaviors** exist: four stores + one context have a documented `@momentum/*` → `@forge/*` one-time migration; `useTemplateSectionStore` and `LanguageContext` have no legacy key at all. Not a bug, just an inconsistency to be aware of when planning a from-scratch Swift data layer (no legacy keys to migrate at all, presumably, unless continuity with existing installs matters).
9. **The bottom tab bar's exact glass-variant/gesture-tuning choices have been revised multiple times based on real-device visual feedback** (documented in inline comments) — treat the current state as the latest iteration, not a stable final spec, when using it as a functional reference for the Swift rewrite's own native tab bar.
