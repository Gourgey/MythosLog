# Mythos Log — Audit & Overhaul Execution Plan (Remaining Modules)

Written 2026-07-13. This document is self-contained: an AI agent with no prior
context can execute any module below. Read this entire header before starting
any module.

---

## 1. Engagement rules (apply to EVERY module)

The user is running a Principal-Engineer-level, module-by-module audit/overhaul
of this app. **The user picks which module runs next — do not chain modules
without being asked.** Each module's report MUST use this exact 4-section
format, in this order:

1. **🔍 Critical Issues & Bugs** — real defects with concrete failure scenarios.
2. **⚡ Performance & Clean Code** — perf problems, dead code, duplication, naming.
3. **✨ Mythos Log themed feature ideas** — RPG/"training arc" flavored product ideas that fit this module.
4. **🛠️ Full overhaul code** — complete rewritten file(s). **No placeholders, no
   `// ... rest unchanged ...`, no elisions.** Every rewritten file must be
   paste-ready in full. If a file is too large for one message, finish it in
   the next message — never truncate.

Fixes are applied to the working tree (section 4 is not hypothetical — actually
edit the files), then verified, then left uncommitted for the user to review
unless the user says to commit.

### Verification recipe (run after every module's fix pass)

```bash
xcodebuild -project MythosLog.xcodeproj -scheme MythosLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Swift Testing suite; **79 tests, all must stay green**. A plain build check is
`xcodebuild ... build` with the same destination. Expect the test run to take
a few minutes.

### Hard constraints & gotchas

- **CloudKit**: the app syncs via CloudKit container
  `iCloud.studio.curateddesign.MythosLog`. SwiftData models therefore **cannot
  use `@Attribute(.unique)` or any unique constraint**, all properties need
  defaults or optionality, and all relationships must be optional.
  Deduplication is done in code (`TrainingStore+Sync.swift` reconciliation).
- **pbxproj**: classic project format (`objectVersion = 54`, no
  `PBXFileSystemSynchronizedRootGroup`). **New/renamed/deleted files that are
  in a target require manual `project.pbxproj` edits** (PBXBuildFile +
  PBXFileReference + group + Sources phase entries). Prefer overhauls that keep
  existing file paths. Files listed as "dead" below have ZERO pbxproj entries,
  so deleting them needs no pbxproj change.
- **Targets**: exactly three — `MythosLog` (app), `MythosLogTests` (unit tests),
  `MythosLogWidgets` (widget extension). There is **no UI test target** (see
  Module 4).
- **App group**: `group.studio.curateddesign.mythoslog` (widgets ↔ app share
  `UserDefaults` + a snapshot JSON file). Registered URL scheme:
  `trainingarc://` only (Info.plist) — see Module 5 finding.
- **Naming history**: the app was renamed ArcLog → Mythos Log, and before that
  the internal brand was "Training Arc". Leftovers: `TrainingArc*` type names,
  `training.arc.*` UserDefaults keys (those keys are LOAD-BEARING — changing
  them silently orphans persisted data; migrate carefully or leave), and dead
  `ArcLog*` file copies.
- Forced light mode: `AppRootView` sets `.preferredColorScheme(.light)` and
  `TrainingTheme` is a light-only palette. Treat as intentional design unless
  the user says otherwise.
- Xcode 26 toolchain.

### Commit conventions (when the user asks to commit)

One or two commits per module, message style used so far:
`Module N (x/y): <short description>` — e.g. `Module 2 (1/2): split
TrainingStore.swift into focused files (pure move)`. Structural moves and
behavioral fixes go in SEPARATE commits.

---

## 2. State of play (as of 2026-07-13)

### Completed & committed
| Module | Scope | Commits |
|---|---|---|
| 1 | `Models/TrainingModels.swift` | `8da2bf0` |
| 2 | `TrainingStore.swift` split into `TrainingStore+{Progression,Goals,Insights,Snapshots,Sync,Transfer}.swift` + `HealthImportService.swift` carve-out, then fix pass | `424e60f`, `c280d8b` |

### Completed but UNCOMMITTED (working tree right now)
**Module 3 fix pass** — 5 modified files awaiting user review:
`Domain/NotificationService.swift`, `Domain/ProgressionEngine.swift`,
`Domain/StreakService.swift`, `Domain/TrainingArcConfig.swift`,
`Domain/TrainingStore+Progression.swift`.

What it did: wired `settings.enableDecay` into `ProgressionEngine` (was dead);
StreakService now reuses one `Calendar` with DST-robust day-gap math;
NotificationService's 5 near-identical scheduling blocks collapsed into one
private `schedule()` helper; TrainingArcConfig dead code removed
(`progressionBridgeUnits`, locked-level sets, a `(.focus,2)`→Strength
placeholder-art bug). 79/79 tests green at time of writing.

**First task for the next agent: re-run the verification recipe, then ask the
user to review/commit this diff before starting a new module** (suggested:
`Module 3: domain services fix pass`).

### Known-good facts a new agent should NOT re-litigate
- `ChargeMath` (in `Models/TrainingModels.swift`) is the single source of charge
  math; `DashboardChargeDots` in `Views/Components/StatCard.swift` is a thin
  presentation wrapper delegating to it. This migration is DONE.
- `Domain/WeekMath.swift` was audited in Module 3 and is clean — leave it.
- The test suite is 79 `@Test` funcs in one `struct MythosLogTests`
  (`MythosLogTests/MythosLogTests.swift`).

---

## 3. Open product decisions (need the USER, not an agent)

Surface these when relevant; do not decide unilaterally.

1. **`decaySensitivity` is inert** (HEADLINE unresolved finding from Module 3).
   `AppSettings.decaySensitivity` (0.7/1.0/1.3 from ProgressionStrictness
   Forgiving/Balanced/Strict) is stored, exported/imported
   (`TrainingStore+Transfer.swift:113,272`), and documented at
   `TrainingModels.swift:766` as driving the engine — but `ProgressionEngine`
   never reads it. It cannot be wired cleanly into the ±4 integer charge meter
   without fractional accumulation. Options: (a) discrete rule variants per
   strictness, (b) fractional charge accumulator persisted per stat,
   (c) remove the setting and the false doc. **Product decision required.**
2. **Custom skills architecture**: `StatKey` enum hard-codes 9 skills while
   `isCustom` scaffolding exists on `StatDomain`. Also ~20 hard-coded per-skill
   intents exist (`OpenStrengthIntent`, `StrengthWeeklyTargetIntent`, …, in
   `Intents/TrainingArcIntents.swift:300-528`). Going truly dynamic is a large
   change touching intents, quick actions, and deep links.
3. **Five widgets were dropped in the ArcLog→MythosLog rename.** Dead
   `MythosLogWidgets/ArcLogWidgets.swift` (746 lines, not compiled) contains
   `TrainingArcMotivationWidget`, `TrainTodayWidget`, `WeakestStatWidget`,
   `GoalAtRiskWidget`, `ReviewReadyWidget`; the live
   `MythosLogWidgets.swift` (421 lines) kept only `TrainingArcStatusWidget` and
   `QuickLogWidget`, yet `WidgetSnapshot.swift` still computes all the fields
   the dropped widgets need (motivation copy, trainToday*, goalsAtRisk*,
   weakestStat, pendingWeeklyReview). Restore them, or delete the dead fields?
4. **URL scheme**: only `trainingarc://` is registered, but
   `Domain/ExternalEventService.swift:6-8` documents `mythoslog://` examples
   that DO NOT WORK. Register `mythoslog` as a second scheme (keeping
   `trainingarc` for compat) or fix the docs?
5. **View file names lie** (`HabitsView.swift` contains `SkillDetailView`,
   `CharacterSheetView.swift` contains `MoreView`, `HabitDetailView.swift`
   contains `HabitDetailView`+`LogEntrySheetView`). Renaming files requires
   pbxproj surgery — worth it, or document and live with it?
6. **UI tests**: `MythosLogUITests/` exists on disk but no UI test target
   exists in the project. Create a target or delete the folder?

---

## 4. Module 4 — Dead code & rename-hygiene sweep (small, do first)

**Goal**: delete confirmed-dead files and fix stale references so later modules
work in a clean tree. Low risk, no pbxproj edits needed for the deletions.

**Confirmed dead (0 mentions in project.pbxproj, safe to `git rm`):**
- `MythosLog/ArcLogApp.swift` (147 lines — pre-rename copy of MythosLogApp)
- `MythosLogTests/ArcLogTests.swift` (1587 lines — pre-rename copy)
- `MythosLogUITests/ArcLogUITests.swift`, `MythosLogUITests/ArcLogUITestsLaunchTests.swift`
- `MythosLogWidgets/ArcLogWidgets.swift` (746) and `MythosLogWidgets/ArcLogWidgetsBundle.swift`
  — ⚠️ **only after the user answers open decision #3** (these hold the only
  copy of the 5 dropped widgets). Everything else can go immediately.
- `MythosLogUITests/MythosLogUITests.swift`, `MythosLogUITests/MythosLogUITestsLaunchTests.swift`
  — also orphaned (no UI test target); delete or keep per open decision #6.

**Also in scope:**
- `MythosLog/ContentView.swift` is a 17-line passthrough to `AppRootView`,
  referenced only by `MythosLogApp.swift:116`. Either inline `AppRootView()`
  into `MythosLogApp` and delete ContentView (this one IS in pbxproj — needs
  pbxproj edits) or leave with a comment. Recommend: leave it in Module 4,
  fold into Module 5's overhaul of MythosLogApp only if renaming anyway.
- Stale doc comment `Models/TrainingModels.swift:251` still describes
  `DashboardChargeDots` as owning rendering math — update to name `ChargeMath`
  as source of truth.
- Get user's answer to open decision #4 and either fix
  `ExternalEventService.swift` docs or add the `mythoslog` scheme to
  `MythosLog/Info.plist` (`CFBundleURLTypes` → add to `CFBundleURLSchemes`
  array; keep `trainingarc`).

**Definition of done**: project builds, 79/79 tests pass, `find . -name
"ArcLog*"` returns nothing (or only the widget file if decision #3 pending).

---

## 5. Module 5 — App entry & Support plumbing (~1,300 lines)

**Files:**
- `MythosLog/MythosLogApp.swift` (147) + `MythosLog/ContentView.swift` (17)
- `MythosLog/App/AppRootView.swift` (346), `App/AppRouter.swift` (29), `App/AppIdentity.swift` (12)
- `MythosLog/Support/TrainingRoute.swift` (115), `Support/DeepLink.swift` (71),
  `Support/WidgetSnapshot.swift` (186), `Support/QuickLogQueue.swift` (35),
  `Support/Formatting.swift` (18), `Support/TrainingExportDocument.swift` (26)
- `MythosLog/Theme/TrainingTheme.swift` (25)
- `MythosLog/Domain/HapticsService.swift` (53), `Domain/ExternalEventService.swift` (40)
  (small Domain leftovers never audited in Module 3)

**Findings already identified (verify, then fix in the overhaul):**
- **`AppRootView.goalsAtRiskCount` (AppRootView.swift:76-82) runs
  `TrainingStore.goalProgress(for:context:)` for every active goal on EVERY
  body evaluation** — a database-walking computation inside a computed property
  of the root view, re-run on each render, purely to badge the Goals tab.
  Cache it (recompute on `.task`, on goal mutations, on foreground) or reuse
  the widget snapshot's `goalsAtRiskCount`.
- `AppRootView.swift:116-118` subscribes to `UserDefaults.didChangeNotification`
  (fires for EVERY defaults write process-wide, and on every foreground) just
  to drain the pending-destination queue. Replace with the explicit
  `PendingDestinationStore.didQueueNotification` (already also observed at
  line 119-121) — the UserDefaults observer is redundant noise; verify the
  cross-process case (widget → app) still works via the scenePhase path.
- `AppRootView.swift:113` change-detection hack: `.onChange(of:
  settingsRecords.map { "\($0.id)|\($0.hasCompletedOnboarding)|\($0.updatedAt...)" })`
  — string-concat fingerprint of a @Query. Replace with an `Equatable` struct
  fingerprint or observe the specific fields.
- Duplicated startup work: `MythosLogApp` `.task` + `.onChange(scenePhase)`
  and `AppRootView` `.task` all run health sync / refresh / shortcut updates.
  Map out exactly what runs on cold launch vs foreground, deduplicate, and make
  ordering explicit (reconcile → drain queue → refresh progress → snapshot).
- `PendingDestinationStore` (TrainingRoute.swift:61-115): `static var`
  mutable state with no actor isolation (`inProcessDestination`,
  `inProcessGoalID`, `inProcessNewGoalStatKey`) — annotate `@MainActor` (all
  call sites are main-actor) rather than leaving data races to luck. Note
  `queueGoal`/`queueNewGoal` are in-process only (never hit UserDefaults) while
  `queue()` persists — document or unify.
- `HomeScreenQuickActionService` (MythosLogApp.swift:40-103): silently caps at
  4 shortcuts (`prefix(4)` — iOS limit, fine, but comment it); skips stats with
  nil `statKey` meaning custom skills never get quick actions (ties to open
  decision #2).
- `DeepLinkRouter.parse` (DeepLink.swift): no clamping of `value` on external
  log events (a URL can inject `value=1e12`); `ISO8601DateFormatter` allocated
  per parse (trivial, but hoist into a static); goal/skill parsing duplicates
  `URLComponents` boilerplate — extract a query helper.
- `MetricFormatting.weekday` (Formatting.swift:13-17) allocates a
  `DateFormatter` per call and ignores locale template formatting — make it a
  cached static formatter; check callers for per-row usage in lists.
- `ExternalEventService.ingest` silently drops events with no matching habit —
  consider routing to an "unmatched" surface like health imports, or at least
  a debug log. Fix the scheme docs (decision #4).
- `WidgetSnapshot.swift`: hand-written `init(from:)`/CodingKeys exist only to
  default new fields — verify each is still needed; dual-write to both file
  and defaults with silent `try?` failures — fine for widgets, but document
  the fallback order contract with the widget extension.

**Audit checklist beyond the above**: launch-path ordering race between
`HomeScreenQuickActionService.consumePendingShortcutIfNeeded` (never called?
grep it) vs `consumePendingDestinationIfNeeded`; `AppRouter.open` clearing
`rootPath` unconditionally (loses navigation depth on tab re-tap — intended?);
`TrainingRouteLink.url` force-unwrap.

**Definition of done**: 4-section report; overhauled files compile; 79/79
green; badge count behavior unchanged (manually reason through goal states);
deep links `trainingarc://dashboard`, `.../skill?key=...&log=1`,
`.../log?stat=...&value=...`, `.../goal?id=...` all still parse (add unit
tests for `DeepLinkRouter.parse` in the module — they don't exist).

---

## 6. Module 6 — HealthImportService deep audit (721 lines)

**File:** `MythosLog/Domain/HealthImportService.swift`. Carved out of
TrainingStore in Module 2 as a pure move + light fixes; **never deeply
audited**. This is the highest-risk un-audited domain file: HealthKit anchored
queries, observer lifecycle, year-backfill, duplicate detection, and CloudKit
interplay.

**Structure** (line numbers from current file): `HealthAuthorizationState`
(11), `HealthSyncSummary` (28), `SupportedWorkoutType` + category mapping
(58-135), `HealthImportService` (141+) with `startWorkoutObserverIfEnabled`
(197), `syncIfEnabled` (231), `syncNow` (250), `performSync` (285),
candidate/dedupe helpers (429-676), anchored fetch (680+).

**Audit checklist:**
- **Observer lifecycle**: `workoutObserverQuery` is a `static var` — check for
  double-registration on repeated foregrounds (`MythosLogApp` calls
  `startWorkoutObserverIfEnabled()` in `.task` AND on every scenePhase
  activation), missing `HKHealthStore` retention, and whether
  `stopWorkoutObserver` is ever called on disable-toggle in Settings.
- **Anchor persistence** (`training.arc.health.anchor` in app-group defaults,
  `AppIdentity.healthWorkoutAnchorKey`): what happens on iCloud restore to a
  new device (stale anchor, missed workouts)? On `shouldRunYearBackfill`
  (595) — how is the flag persisted, can backfill re-run and duplicate?
- **Dedupe correctness** (`isDuplicate`/`overlaps`, 607-676): three overloads —
  are the tolerance windows consistent? CloudKit sync can deliver the same
  workout imported on two devices; `normalizeExistingHealthImports` (521)
  merges — is it O(n²) over all records on every sync?
- **Concurrency**: which methods are MainActor vs background? `performSync`
  takes a `ModelContext` — created where, and is it used across awaits?
- **Silent failure**: `syncIfEnabled` swallows errors; user-visible sync status
  exists in Settings (`CloudSyncStatusService`) — should health sync errors
  surface similarly?
- `purgeDeprecatedAutoMappings` (578) — still needed, or one-shot migration
  that can be scheduled for deletion?
- `matchHabit(in:workoutDisplayName:)` (481) — fuzzy name matching rules;
  interaction with `UnmatchedWorkoutSheet` flow.

**Definition of done**: 4-section report; overhaul applied; 79/79 green; add
Swift Testing coverage for the pure parts (dedupe/overlap/backfill-window
logic) — these are currently untested.

---

## 7. Module 7 — Views I: Dashboard cluster (~4,200 lines)

**Files:**
- `Views/Dashboard/DashboardView.swift` (1749) — includes grid reorder
  drag-drop, custom `CenteredDashboardGridLayout`, insight sheet
- `Views/Dashboard/RankChangesReviewView.swift` (141)
- `Views/Components/StatCard.swift` (732 — also `DashboardChargeDots`,
  `SignedChargeMeter`, `DirectionalChargeMeter`, `DashboardGridTile`)
- `Views/Components/SurfaceCard.swift` (16), `AuraView.swift` (39),
  `ParticleBurstView.swift` (135), `RankArtworkView.swift` (451),
  `V4Style.swift` (210), `HabitQuickLogRow.swift` (106)

**Known context:** Dashboard is the root tab; `DashboardView.swift:1428` and
`HabitsView.swift:1526` consume `DashboardChargeDots.summaryLabel`. 14 `try?`
sites in DashboardView swallow store errors.

**Audit checklist:** body size and recomputation (what does the 1749-line view
recompute per render — look for `TrainingStore.*(context:)` calls inside
computed vars like AppRootView's badge bug); drag-reorder correctness
(`DashboardGridReorderDropDelegate`, `setSkillOrderPersistsCustomDashboardOrder`
test exists); custom `Layout` conformance perf (cache sizes?); particle/aura
animation timers still running when off-screen; `RankArtworkView` asset
lookups vs `TrainingArcConfig` roster (Module 3 fixed a placeholder-art bug —
verify view side); accessibility labels (some exist, e.g. line 1428 — make
consistent); error-swallowing `try?` pattern — route through a single
error-banner mechanism if one exists or propose one.

**Definition of done**: 4-section report; overhauled files; 79/79 green; no
change to persisted data shapes.

---

## 8. Module 8 — Views II: Skill detail cluster (~2,850 lines)

**Files:**
- `Views/Habits/HabitsView.swift` (1848) — **actually `SkillDetailView`** plus
  sticky log button, help sheet, week-day summary, log rows,
  `HealthAttributionView`, flow-chip layout, history sheet,
  `RankChangeRevealView`, `SkillGoalRow`, `SkillCalibrationSheet`
- `Views/Habits/HabitDetailView.swift` (463) + `LogEntrySheetView`
- `Views/Habits/HabitEditorView.swift` (128)
- `Views/Habits/UnmatchedWorkoutSheet.swift` (252)
- `Views/Skills/ManageSkillsView.swift` (146)

**Known context:** `SkillDetailView` is pushed from dashboard navigation and
from deep links/quick actions (`AppRootView` → `SkillDetailDestinationView`),
with `opensLogSheetOnAppear` plumbed through. The rank-change reveal
(`RankChangeRevealView`, line 1304) pairs with pending-rank-change domain logic
tested in `completedStrongWeeksCreatePendingRankChangeUntilAcknowledged`.

**Audit checklist:** 1848-line file decomposition (extract sheets/rows into
files ONLY with pbxproj entries, or into extensions in-file — prefer in-file
`// MARK:` extensions to avoid pbxproj churn unless user approves renames per
open decision #5); `FlexibleChipLayout` custom Layout correctness; scroll
offset preference-key handling (`SkillDetailScrollOffsetPreferenceKey`) —
known SwiftUI perf trap if it invalidates per-frame; log sheet double-submit
protection; `UnmatchedWorkoutSheet` ↔ HealthImportService contract (matches
Module 6); 10 `try?` swallowed errors.

**Definition of done**: 4-section report; overhaul; 79/79 green; log →
progress-refresh flow manually traced (log from sheet, from quick-log row,
from widget queue drain — all should call the batched
`refreshProgressAfterSave` path added in Module 2).

---

## 9. Module 9 — Views III: Goals, Weekly Review, History (~2,320 lines)

**Files:**
- `Views/Goals/GoalsView.swift` (572) — includes `GoalCardView`,
  `GoalEditorView`, `GoalEditorSeed`
- `Views/WeeklyReview/WeeklyReviewView.swift` (783) — includes history +
  explainer sheet
- `Views/WeeklyReview/WeeklyReviewDetailView.swift` (501) — includes
  `HealthWeekSummary`
- `Views/History/HistoryView.swift` (464) + `HistoryRange`

**Known context:** Goals tab badge count comes from AppRootView (Module 5
fixes the recompute); `PendingDestinationStore.queueGoal/consumeGoal` +
`didQueueGoalNotification` deep-link plumbing lands here — verify GoalsView
actually observes `didQueueGoalNotification` and `didQueueNewGoalNotification`
(if not, deep-linked goals silently no-op — likely bug). Goal pace logic
(`goalProgress`, `paceStatus`) was hardened in Module 2's batch inputs work.

**Audit checklist:** per-card `goalProgress` recomputation (same N×DB pattern
as the badge — batch via the Module 2 batch-inputs API); WeeklyReview
generation timing vs `WeekMath` week boundaries (DST-sensitive; StreakService
got this fix in Module 3 — reviews may have the same class of bug);
`HistoryRange` date filtering off-by-one at range edges; Calendar.current
usage (2 sites each in History/WeeklyReview files) — should use the shared
calendar/week helpers; empty-state and first-week UX.

**Definition of done**: 4-section report; overhaul; 79/79 green; goal deep
link (`trainingarc://goal?id=...`) manually traced end-to-end.

---

## 10. Module 10 — Views IV: More/Character, Settings, Onboarding (~1,640 lines)

**Files:**
- `Views/Character/CharacterSheetView.swift` (614) — **actually `MoreView`**
  plus `SkillCharacterRosterView` + `CharacterRosterCarousel`
- `Views/Settings/SettingsView.swift` (504) — includes `CloudSyncState`,
  `CloudSyncStatusService`, `SyncDiagnosticsSnapshot`
- `Views/Onboarding/OnboardingFlowView.swift` (520)

**Known context:** `MoreView` is the 4th tab (AppRootView `moreStack`), takes a
`reloadSettings` callback. Onboarding completion drives
`settings.hasCompletedOnboarding`, which gates quick actions, widgets
(`HomeScreenQuickActionService.refresh` clears shortcuts pre-onboarding), and
`AppRootView.showOnboarding`. `CloudSyncStatusService` lives in a VIEW file —
it's domain logic (CloudKit event monitoring) and should migrate to `Domain/`
(pbxproj-free if moved into an existing Domain file, or get user approval for
a new file).

**Audit checklist:** settings writes → `settings.updatedAt` touch → CloudKit
reconciliation (`reconcileSyncedDataKeepsNewestSettingsRecord` test covers
domain side — check the view actually bumps `updatedAt`); onboarding
mid-flight kill/resume state; baseline quiz → `onboardingBaselineAssignsStartingRankAndCurrentBaseline`
consistency; strictness picker writes `decaySensitivity` (inert — open
decision #1: DO NOT ship UI promising behavior the engine ignores; at minimum
flag copy); export/import round-trip via `TrainingExportDocument` +
`TrainingStore+Transfer` (13 `try?` sites in SettingsView — import failures
must not be silent); notification permission + scheduling toggles ↔
`NotificationService` (Module 3 refactored scheduling — verify Settings
toggles hit the new `schedule()` helper correctly).

**Definition of done**: 4-section report; overhaul; 79/79 green; onboarding →
dashboard hand-off and export→import round-trip traced.

---

## 11. Module 11 — Widgets & App Intents (~1,100 lines + decision #3 scope)

**Files:**
- `MythosLogWidgets/MythosLogWidgets.swift` (421), `MythosLogWidgetsBundle.swift` (10),
  `QuickLogIntent.swift` (34), `MythosLogWidgets/Info.plist`
- `MythosLog/Intents/TrainingArcIntents.swift` (528),
  `Intents/TrainingArcAppShortcuts.swift` (106)
- Shared plumbing already audited in Module 5: `WidgetSnapshot.swift`, `QuickLogQueue.swift`

**Known context:** Only `TrainingArcStatusWidget` + `QuickLogWidget` are live;
timeline is a single entry with `.after(refresh)` policy
(MythosLogWidgets.swift:19-22 — check the refresh interval; app pushes via
`WidgetCenter.shared.reloadAllTimelines()` from `TrainingStore+Snapshots.swift:655`).
`QuickLogIntent` enqueues into `QuickLogQueue` (app-group defaults); the app
drains on launch/foreground (`AppRootView.task` → `drainQuickLogQueue`).
If the user restores the 5 dropped widgets (decision #3), port them from dead
`ArcLogWidgets.swift` — the snapshot already carries all needed fields.

**Audit checklist:** widget reads snapshot fresh per timeline call (file →
defaults → empty fallback — verify extension has app-group entitlement);
QuickLog pending-amount display vs drain race (tap widget, open app, does the
widget refresh after drain? — drain should trigger `reloadAllTimelines`);
`QuickLogIntent.perform` error path; intents in `TrainingArcIntents.swift`:
`SkillEntityQuery` hitting SwiftData from intent context (container access,
MainActor), the ~20 hard-coded per-skill intents (decision #2 — at minimum
dedupe via a generic parameterized intent while keeping the old ones as
deprecated shims for existing user shortcuts), `TrainingArcAppShortcuts`
phrase quality (App Shortcuts have a 10-shortcut limit — count them);
`updateAppShortcutParameters` called on every foreground (MythosLogApp) —
needed, or only on skill catalog change?

**Definition of done**: 4-section report; overhaul; 79/79 green; both widget
targets build (`-scheme MythosLog build` covers the extension); quick-log
round-trip traced in code.

---

## 12. Module 12 — Test suite overhaul (1,587 lines, LAST)

**File:** `MythosLogTests/MythosLogTests.swift` — one `struct MythosLogTests`
(line 64) holding all 79 `@Test` funcs, zero `@Suite` structure, shared
fixture helpers at top (`isoDate`, `makeStrengthFixture`, `addSessionLogs`).

**Goal:** restructure into named `@Suite` groups (in the SAME file to avoid
pbxproj churn, or new files with pbxproj entries if user approves): Config,
ChargeMath/Progression, Sync/Reconciliation, Snapshots/Widgets, Streaks,
Goals, Transfer, Insights. Then close coverage gaps created by the audit:

- `DeepLinkRouter.parse` (none today — added in Module 5, verify)
- `HealthImportService` pure logic (added in Module 6, verify)
- `NotificationService.schedule()` helper (Module 3 refactor — no tests)
- `ProgressionEngine` decay on/off paths (Module 3 wired `enableDecay` — add
  explicit both-paths tests)
- StreakService DST boundary (Module 3 fix — add a spring-forward fixture)
- Goal pace batching (Module 2) — edge: goal with zero target, archived skill
- Whatever `decaySensitivity` decision #1 produced

Keep every existing test's behavioral assertion intact — renames/regrouping
must not weaken assertions. Target: all green, count strictly > 79.

**Definition of done**: 4-section report (sections 1-2 cover test-quality
issues: duplicated fixtures, over-broad tests, missing negative cases);
restructured suite; every module's new coverage present.

---

## 13. Suggested execution order & effort

| Order | Module | Size | Why this order |
|---|---|---|---|
| 0 | Commit Module 3 (user review) | — | Unblocks clean diffs |
| 1 | 4 — Dead code sweep | XS | Clean tree for everything after |
| 2 | 5 — App/Support | M | Root-view perf bug; plumbing contracts used by all view modules |
| 3 | 6 — HealthImportService | M | Highest-risk unaudited domain code |
| 4 | 7 — Dashboard views | L | Biggest user surface |
| 5 | 8 — Skill detail views | L | Second-biggest; depends on 6's contracts |
| 6 | 9 — Goals/Review/History | M | Depends on 5 (badge) + 2's batch APIs |
| 7 | 10 — More/Settings/Onboarding | M | Depends on decisions #1; moves CloudSyncStatusService |
| 8 | 11 — Widgets/Intents | M | Depends on decision #3; after Support audit |
| 9 | 12 — Tests | M | Last, locks in everything |

The user picks the actual order — this table is only a recommendation.
