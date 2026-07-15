# UI_FIX_PLAN.md — Mythos Log UI/UX Fix Plan (2026-07-14)

Self-contained implementation plan for the UI/UX defects found in the 2026-07-14
screenshot audit (25 screenshots in `Screenshots/`, cross-verified against source).
Written for an implementing agent with **no prior conversation context**. Read this
whole file before touching code.

> **STATUS**: Phase 1 (WS1–WS9) is ✅ COMPLETE — every workstream below carries its
> commit hash. **Phase 2 (WS10–WS17), appended at the bottom of this file, is the
> active work.** It comes from a fresh 2026-07-15 screenshot design review (15
> screenshots in `Screenshots/`). Phase 1 sections remain as context and as the
> source of the ground rules; do not redo them.

---

## 0. Project context & ground rules

- **App**: Mythos Log — SwiftUI + SwiftData habit/skill tracker, iOS, single scheme
  `MythosLog`, plus a widget extension target `MythosLogWidgets`. Xcode 26,
  **classic pbxproj** — any NEW file must be manually registered in
  `MythosLog.xcodeproj/project.pbxproj` (build file entry, file ref, group child,
  Sources phase). Strongly prefer editing existing files over creating new ones.
- **Tests**: 96 Swift Testing tests, all green, organized into 11 `@Suite` structs in
  `MythosLogTests/`. They MUST stay green. Some suites (e.g. `InsightsTests`)
  assert on generated copy strings — when you change user-facing strings built in
  `MythosLog/Domain/*`, grep the tests for the old string and update assertions
  deliberately (never weaken an assertion to `contains("")`).
- **Verification recipe** (known-good):
  `xcodebuild -project MythosLog.xcodeproj -scheme MythosLog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
  Also build the widget target after any shared-file change:
  `xcodebuild -project MythosLog.xcodeproj -scheme MythosLog -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- **CloudKit**: the store syncs via CloudKit (`iCloud.studio.curateddesign.MythosLog`)
  — no SwiftData unique constraints; do not add any.
- **Reproducing the screenshot states**: run a Debug build; Settings → Debug Tools
  has `Seed New User`, `Seed Streaking`, `Seed Stagnating`, `Seed Level-Up Week`,
  `Seed Sample Goals`. The audit screenshots correspond to a **Seed Stagnating**-like
  state (everything behind, one pending rank-down on Emotional). Use these seeds for
  before/after QA on every workstream.
- **Design system**: colors/tokens live in `TrainingTheme` and `TrainingArcConfig`
  (per-skill accent `TrainingArcConfig.color(for:)`, icons, charge config).
  Serif display components are `V4SerifTitle`, `V4Card`, `V4StatTile`, `V4Style`
  (grep `struct V4` for the file). Match these; don't introduce ad-hoc styles.
- **Commit strategy**: one commit per workstream (WS1, WS2, …), message style:
  `WS<N> (<short name>): <headline fix>` — mirroring the module-audit history.
  Run the full test suite before each commit.
- **Do not**: redesign screens wholesale, add dependencies, generate artwork,
  change domain/progression math (except items explicitly listed in WS4), or touch
  `ProgressionEngine` charge rules (WS9 is investigate-and-report only).

### Key files (paths relative to repo root)

| Area | File |
|---|---|
| Root chrome / tab bar | `MythosLog/App/AppRootView.swift` (`CompactRootTabBar` at ~line 225, root `safeAreaInset` at ~line 99) |
| Dashboard (all 3 layouts) | `MythosLog/Views/Dashboard/DashboardView.swift` (1758 lines; game grid ~761–995, `GameDashboardTile` ~1296) |
| Rank ceremonies / review | `MythosLog/Views/Dashboard/RankChangesReviewView.swift` |
| Skill detail | `MythosLog/Views/Habits/SkillDetailView.swift` (sticky button inset ~193, `StickyLogButton` ~922) |
| Habit detail | `MythosLog/Views/Habits/HabitDetailView.swift` |
| Rank artwork + placeholders | `MythosLog/Views/Components/RankArtworkView.swift` |
| Charge meters, stat cards | `MythosLog/Views/Components/StatCard.swift` (`DirectionalChargeMeter` at ~107) |
| Review tab | `MythosLog/Views/WeeklyReview/WeeklyReviewView.swift` (bucket counts ~99–161) |
| Weekly detail | `MythosLog/Views/WeeklyReview/WeeklyReviewDetailView.swift` |
| Goals | `MythosLog/Views/Goals/GoalsView.swift` |
| More tab | `MythosLog/Views/Character/MoreView.swift` (stat tiles ~155–160) |
| History | `MythosLog/Views/History/HistoryView.swift` (summary ~190–235) |
| Settings | `MythosLog/Views/Settings/SettingsView.swift` |
| Insight copy generation | `MythosLog/Domain/TrainingStore+Insights.swift` (lines ~510–530) |
| Skill/charge config | `MythosLog/Domain/TrainingArcConfig.swift` (or wherever `TrainingArcConfig` lives — grep) |

Line numbers are from the audit date — **re-grep before editing**, don't trust them blindly.

---

## WS1 — P0: Bottom chrome occlusion (the "Log Session button hidden behind tab bar" bug)

### 1A. Sticky Log button is fully occluded by the floating tab bar (headline bug)

✅ **DONE — commit `2f79d0f`** (2026-07-14). Implemented exactly per the recommended
Option 1: removed the root-level `.safeAreaInset` wrapping `tabContent` in
`AppRootView.body`, and attached `.safeAreaInset(edge: .bottom) { rootTabBar }`
to each tab's root content view instead (`DashboardView()`, `WeeklyReviewView()`,
`GoalsView()`, `MoreView`) via a shared `rootTabBar` computed property. Dropped
the now-dead `primaryHabit == nil ? 118 : 36` ternary in `SkillDetailView`
(line ~182) down to a flat `36`. Verified live on the iPhone 17 Pro simulator
(Seed Stagnating state): the Strength detail page's "+ Log Session" button is
now fully visible, sits cleanly above the home indicator, and opens the log
sheet on tap; the tab bar correctly disappears on every pushed screen
(Settings, Strength detail) and reappears correctly on all 4 tab roots.
96/96 tests still green; widget extension target still builds. 1B (status-bar
scroll collision) below is NOT yet done — separate, still open.

**Symptom (user-confirmed on device)**: on every skill detail page, the pinned
"Log Session" / "Log Progress" button renders *underneath* the floating tab bar and
cannot be seen or tapped. In screenshots its coral glow is visible bleeding around
the tab bar (`StickyLogButton` has `shadow(color: accent.opacity(0.28), radius: 16)`).

**Mechanism**: two competing bottom `safeAreaInset`s.
- `AppRootView.swift:99` wraps `tabContent` in
  `.safeAreaInset(edge: .bottom) { CompactRootTabBar(...) }` — **outside** the
  per-tab `NavigationStack`s.
- `SkillDetailView.swift:193` adds its own
  `.safeAreaInset(edge: .bottom) { StickyLogButton(...) }` on the pushed detail.
- A `safeAreaInset` applied **outside a NavigationStack is not propagated into
  pushed destinations** (long-standing SwiftUI behavior), so the pushed detail
  believes the bottom safe area is just the home indicator. Its button lands at the
  device bottom edge — exactly under the root tab bar, which draws on top.

**Fix (recommended — Option 1): move the tab bar inset inside each tab's root.**
1. In `AppRootView`, inspect `tabContent` (starts ~line 178). Each tab is (or should
   be) a `NavigationStack { <RootView> }`.
2. Remove the single root-level `.safeAreaInset` (line ~99).
3. Apply `.safeAreaInset(edge: .bottom, spacing: 0) { CompactRootTabBar(...) }` to
   the **root view inside each tab's NavigationStack** (Dashboard root, Review root,
   Goals root, More root) — NOT to the NavigationStack itself. Extract a small
   `private func withRootTabBar<V: View>(_ view: V) -> some View` helper in
   AppRootView so the four call sites stay in sync.
4. Result: tab roots keep the bar; **pushed views (SkillDetailView, HabitDetailView,
   ManageSkillsView, HistoryView, SettingsView, WeeklyReviewDetailView) no longer
   show the tab bar at all** — which is the standard iOS pattern for leaf/detail
   screens — and SkillDetailView's own sticky-button inset now owns the bottom edge
   cleanly.
5. If the product intent is instead "tab bar visible everywhere", use Option 2:
   keep the root inset, delete SkillDetailView's inset, and render StickyLogButton
   via `.overlay(alignment: .bottom)` **on the AppRootView layer** driven by a
   PreferenceKey from the detail view. This is strictly more complex; only do it if
   the user explicitly wants the bar on detail screens. Default to Option 1.

**Also in this task:**
- `SkillDetailView.swift:182`: `.padding(.bottom, primaryHabit == nil ? 118 : 36)` —
  the `118` is a magic tab-bar-height guess that stops being needed under Option 1
  (no tab bar on detail). Replace with a single constant (e.g. `36`) once the inset
  chain is fixed. Grep the repo for other `118` paddings (`DashboardView.swift:167`
  has `.padding(.bottom, 118)`) and replace with clearance that derives from the
  real inset (after Option 1, the dashboard root's `safeAreaInset` handles it —
  reduce that padding to normal spacing, verify by scrolling to the bottom card).
- `HabitDetailView.swift` — check for the same nested-inset pattern (grep
  `safeAreaInset` / `StickyLog`); apply the same treatment if present.

**Acceptance criteria**:
- On Strength, Emotional, and a no-primary-habit skill: sticky button fully visible,
  fully tappable, sits above the home indicator, nothing occludes it.
- Dashboard/Review/Goals/More roots: tab bar unchanged, last content row can scroll
  fully clear of the bar (check "Rank changes to review" banner on Dashboard and the
  last per-skill card on Review).
- No screen shows BOTH the tab bar and a sticky action pinned at the same edge.
- All 96 tests green; widget target still builds.

### 1B. Content scrolls illegibly under the status bar / floating headers

✅ **DONE — commit `1900cfd`** (2026-07-15). Added an inert top gradient scrim to
Dashboard's custom scroll chrome so content fades before reaching the status bar,
and forced an opaque `TrainingTheme.background` navigation-bar background on
Review, weekly detail, Manage Skills, Settings, History, Goals, and More. Verified
the seeded Dashboard, Review, and More routes live on iPhone 17 Pro; the exact
source build also passed the widget-inclusive build and all 96 tests on a clean
iPhone 17 simulator (0 failures, 0 skips).

**Symptom**: mid-scroll, the status-bar clock renders directly over "TUESDAY 14 JUL"
(Dashboard); the centered "Review" / "6–12 Jul 2026" / "Manage Skills" titles float
over scrolled list content with no background separation.

**Fix**: give every scrolling screen a scroll-edge treatment at the top:
- For screens using the navigation bar (`Review` title etc. — they set
  `.toolbar` principal items): add `.toolbarBackground(.visible, for: .navigationBar)`
  with the app background color, or attach a `scrollEdgeEffect`-style material —
  match whichever pattern the codebase already uses (grep `toolbarBackground` first).
- For the Dashboard (custom in-scroll header card, no nav bar): add a top
  `safeAreaInset` (or overlay) with a `TrainingTheme.background` gradient/blur strip
  ~top-safe-area height so scrolled content fades under the status bar instead of
  colliding with the clock.
- Screens to cover: DashboardView, WeeklyReviewView, WeeklyReviewDetailView,
  ManageSkillsView, SettingsView, HistoryView, GoalsView, MoreView.

**Acceptance**: at any scroll offset, status-bar time and nav titles are readable;
no raw text-on-text collisions. Verify in Light mode (app forces light — see WS5-7).

---

## WS2 — P0: Honeycomb (game-grid) dashboard row collisions

✅ **DONE — commit `a8aa862`** (2026-07-15). Root cause confirmed precisely
(not just the row-height guess): the fixed `tileWidth+72` row box, read via
an inline `GeometryReader`, quietly fell short of the tile's real rendered
height; combined with the middle row's higher `zIndex` (needed for its
"focused" `scaleEffect`), that row started drawing (and painting over)
before the row above's charge meter had fully cleared — e.g. Focus's name
label rendering on top of Creativity/Emotional's charge dots. Fixed by
reading available width and each row's scale-anchor via `.background` +
two new `PreferenceKey`s (`HoneycombWidthPreferenceKey`,
`HoneycombRowMidYPreferenceKey`) instead of a size-dictating
`GeometryReader`, so rows size naturally from content — this can never run
short at any Dynamic Type size, so `zIndex` and the `honeycombRowHeight`/
`honeycombGridHeight` magic-number helpers were removed as dead weight.
Also reserved a fixed 26pt trailing gutter on the tile name label so the
rank-change badge (anchored top-trailing) stopped overlapping the last
letters of wide names ("Creativity", "Intellect") — confirmed via zoomed
screenshot before/after. Verified live on iPhone 17 Pro simulator (Seed
Stagnating, all 7 rank-down badges showing): zero collisions at default
text size AND at the maximum accessibility size (AX5/XXXL) — the exact
Dynamic Type stress test the acceptance criteria called for. Did NOT
re-verify the 6/8-skill `CenteredDashboardGridLayout` fallback path
in-app (code inspection confirmed it already uses real `Layout.sizeThatFits`
measurement, untouched by this bug/fix, but no live click-through was done
for that specific skill count). 96/96 tests green.

**Symptom**: on the default circular dashboard, the middle row's skill name labels
render on the same visual line as the top row's charge dots — reads as
"Focus ○○●● Intellect ○○○○ Strength". The Intellect tile's corner `AttentionDot`
overlaps a red charge dot from the row above; the Strength character art pokes into
the row above; the pulsing rank-change badge covers the "Emotional" label.

**Mechanism** (`DashboardView.swift`):
- `honeycombRowHeight(for:) = tileWidth + 72` (~196pt at max tile width 124) but
  `GameDashboardTile.tileContent` (line ~1341) is a VStack with
  `minHeight: 182` PLUS name label (≥15pt + 7 spacing) PLUS fraction row (~16pt + 7)
  PLUS charge meter (16pt + 7) around a `tileWidth`-tall circle → real height ≈
  tileWidth + ~90. Rows are therefore ~20pt too short and content bleeds across.
- The middle row additionally gets `scaleEffect(dashboardRowScale(...))` up to
  `gameGridFocusedScale` (>1) with `zIndex(1)` — `scaleEffect` doesn't affect layout,
  so the enlarged row overdraws its neighbors by design.
- The overlays (`AttentionDot`, rank badge at `.topTrailing` with `.padding(6)`)
  sit at the very tile edges, so any row overlap puts them on top of foreign content.

**Fix**:
1. Make row height honest: replace the `+72` fudge with a computed constant that
   accounts for every VStack element: `tileWidth + labelHeight + meterHeight +
   fractionRowHeight + 3*spacing` — in practice `tileWidth + 96` at default type
   sizes. Better: stop hardcoding — wrap each row's tiles in a `fixedSize`-measured
   container, or simply drop the outer `GeometryReader`-per-row and let the VStack
   size rows naturally (`honeycombGameGridDashboard` only needs GeometryReader for
   tile width — compute width once at the top, then use plain `HStack`s in a
   `VStack` so rows take intrinsic height). **Prefer the natural-layout rewrite**;
   it eliminates the whole class of bug.
2. Budget for the focus scale: either (a) reduce `gameGridFocusedScale` so max
   overdraw ≤ the row spacing, or (b) reserve `rowSpacing ≥ tileContentHeight *
   (focusedScale - 1)` between rows, or (c) drop the scale gimmick on this grid.
   (a)+(b) combined is the minimal-diff path; measure with the largest tile.
3. Keep `zIndex` only if scaling stays.
4. Badge containment: give `tileContent` enough top-trailing headroom that the
   rank badge and `AttentionDot` render **within** the tile's own bounds (e.g. move
   the name label down by the badge diameter, or inset the overlay padding to place
   the badge inside the circle's top-right quadrant). The badge must never cover a
   neighboring tile's label or its own tile's name.
5. Re-test the **non-7-skill fallback** (`CenteredDashboardGridLayout` branch of
   `gameGridDashboard`) — same tile, same overlays; ensure enabling an 8th skill
   (Manage Skills → Enable Curiosity) doesn't collide either.

**Acceptance**:
- 7-skill honeycomb: zero cross-row overlaps at Dynamic Type L and XL; labels,
  dots, badges each fully inside their own tile's bounds; middle-row focus scale (if
  kept) never touches adjacent rows.
- 6- and 8-skill grids: same guarantees.
- Scroll performance unchanged (no new per-frame GeometryReader work — the audit
  previously removed a scroll-driven query storm here; do not reintroduce one).

---

## WS3 — P0: "Placeholder" artwork shipping in ceremonies and tiles

✅ **DONE — commit `2d03b21`** (2026-07-15). Replaced the literal
"Placeholder"/"Placeholder Artwork" fallback (`.hero` and `.compact`
`RankArtworkView` styles — confirmed via call-site grep that `.compact` is
exactly what the rank-change ceremony uses) with a crest built from
`statFallbackIcon` + the skill's rank `title`, matching the pattern
`.dashboardBare` already used correctly on the game-grid tiles. Also
swapped `dashboardGlyphPlaceholder`'s bare-letter crest (used by
`.dashboardCompact`/`.dashboardTile` — detailed-cards dashboard + More-tab
roster) for the same icon, incidentally fixing the Cardio/Cooking/Creativity
same-letter-"C" ambiguity there too. Fixed the rank-badge/LV-pill overlap
on the ceremony (badge was `.overlay(alignment: .top)`, pill renders
`.topLeading` — moved badge to `.topTrailing`). Unified the two remaining
casing outliers ("Lv 4" ceremony FROM/TO pills, "L3" game-grid fraction
row) to "LV n". Did NOT extract a shared `RankPill` component — the
existing three renderers (`pill()`, `dashboardLevelPill`, `V4LevelBadge`)
were already consistent in spirit once the 2 outlier strings were fixed,
so a full component swap wasn't needed and would have touched more
surface than the casing fix required. `.tile`/`tileArtwork` style
confirmed dead code (zero call sites) — left untouched, out of scope.
Verified live: skill detail hero, Rank Drop Pending, Rank Reduced, and the
detailed-cards dashboard all show icon+title crests with legible,
non-overlapping "LV n" pills; grepped the codebase afterward to confirm
zero remaining literal "Placeholder" user-visible strings. 96/96 tests
green.

**Symptom**:
- The Rank Drop ceremony ("Rank Drop Pending" / "Rank Reduced" full-screen views)
  shows a card literally captioned **"Placeholder"** with a generic person icon —
  at the most emotionally loaded moment in the app.
- 5 of 7 skills have no art; their dashboard tiles fall back to a single letter
  (`E`, `F`, `I`, `C`, `C`) — Cardio and Cooking are both "C".
- The pulsing red badge covers the "LV" pill on the pending-drop card.
- Rank pill casing is inconsistent: `LV 3` (pills), `Lv 4` (FROM/TO boxes), `L3`
  (game grid).

**Fix** (`RankArtworkView.swift` + ceremony view in `RankChangesReviewView.swift`):
1. Kill the literal strings: `Text("Placeholder")` (~line 231) and
   `Text("Placeholder Artwork")` (~line 211). Replace every placeholder variant
   (`compactPlaceholderArtwork`, `tilePlaceholderArtwork`,
   `dashboardCompactPlaceholderArtwork`, `dashboardTilePlaceholderArtwork`,
   `barePlaceholderArtwork`, `dashboardGlyphPlaceholder`) with a **skill crest**:
   the skill's SF Symbol icon (the same one Manage Skills rows use — grep how
   `ManageSkillsView` gets its icon, it comes from `TrainingArcConfig`) inside an
   accent-tinted rounded square, with the **rank title** (e.g. "Reflecting") as the
   caption instead of "Placeholder"/the letter. Letter initials go away entirely —
   that fixes the C/C/C ambiguity for free.
2. Ceremony bottom label: caption should be the rank title ("Reflecting"), falling
   back to the skill name — never a dev word.
3. Badge/pill collision on the ceremony card: the red arrow badge currently overlaps
   the `LV` pill — offset the badge outside the card's top-right corner
   (negative-offset it off the crest like a notification badge) or move the pill to
   the bottom of the crest. Either way both must be fully legible.
4. Rank pill casing: create ONE small component (e.g. `RankPill(level:)` in
   `RankArtworkView.swift` or `StatCard.swift` — no new file) rendering `LV n`, and
   use it in: game grid fraction row (currently `Text("L\(...)")` in
   `GameDashboardTile`), detailed cards, skill detail, ceremony FROM/TO boxes
   (currently "Lv 4"/"Lv 3"), weekly review cards. Grep patterns: `"L\(`, `"Lv `,
   `"LV `.

**Acceptance**: the word "Placeholder" appears nowhere in the UI (grep the Views
folder); Cardio/Cooking/Creativity tiles are visually distinct without reading
labels; ceremony screens show skill-appropriate crest + legible pill + badge.

---

## WS4 — P1: Wrong numbers & mislabeled stats (all verified in code)

✅ **DONE — commit `fe3891e`** (2026-07-15). All 7 items fixed:
1. History "Weeks" now `Set(resolutionsInRange.map(\.weekStartDate)).count`.
2. MoreView's `resolvedThisWeekCount` renamed `resolvedLastWeekCount`, tile
   label → "Last week".
3. Review's behind/onPace/risk tiles now all derive from `reviewUrgency`'s
   single per-item classification (was: two independent, non-nested
   predicates — pacing-based vs charge-based — that could both be true or
   both false for the same skill). Verified live: "0 behind / 0 on pace /
   7 risk" now sums to exactly 7 (was "7/0/5" summing to 12).
4/5. Insight copy pluralized + unit-labeled.
6. **Found something the plan didn't anticipate**: fixing the Review-vs-
   This-Week-sheet predicate mismatch (`computeDashboardHighlights` was
   missing the `pendingRankChange direction == .down` check —
   `reviewUrgency` checks that FIRST, before charge, and a pending
   rank-down already resolves charge back to 0 as part of creating the
   resolution, before the ceremony is even viewed) exposed a SEPARATE
   pre-existing bug: the sheet's "Rank & Charge" list silently truncates
   to `highlights.prefix(4)` with no "+N more" indicator. Fixed both.
   Verified live: sheet now shows the same 4 skills + "+3 more" = 7,
   exactly matching Review's count — confirmed the predicates now agree
   and the only remaining gap was the truncation, not classification.
7. `weeklyUnitLabel(for:)`'s `.count` case: `"counts"` → `"times"` (one
   central function, propagates everywhere: Review rows, Next Moves,
   ceremony resolution card, skill detail calibration line, insights).
96/96 tests green; widget target builds.

Each item is a small, isolated diff. Keep them one commit together.

1. **History "Weeks" counts resolution rows, not weeks** —
   `HistoryView.swift:198`: `let weekCount = weeks.count` where `weeks =
   resolutionsInRange` (per-skill-per-week rows; showed "48 Weeks" inside a 3-month
   filter). Fix: `Set(resolutionsInRange.map(\.weekStartDate)).count`. Sanity: 3M
   window should show ≤ ~13.
2. **More tab "This week" tile shows last completed week** —
   `MoreView.swift:23–27` deliberately counts `lastCompletedWeek` resolutions (that
   logic is correct; resolutions only exist for completed weeks) but the tile label
   at line ~158 still says `"This week"`. Change label to `"Last week"`.
3. **Review header buckets double-count** — `WeeklyReviewView.swift:99–161`:
   `risk` (`urgency == .regressionRisk`) is a subset of `behind`
   (`pacingStatus == .behind`), yet the three `V4StatTile`s present them as parallel
   ("7 behind / 0 on pace / 5 risk" out of 7 skills). Fix: make tiles disjoint —
   `behindNotAtRisk = skillsBehindCount - skillsAtRegressionRiskCount`, labels
   `"behind"` / `"on pace"` / `"at risk"`. Acceptance: the three values sum to
   `currentReviewItems.count`. Check no test asserts the old counts.
4. **Pluralization** — `TrainingStore+Insights.swift:529`:
   `"\(rankUps.count) weekly rank-up checks converted into level gains this month."`
   → singular when count == 1 ("1 weekly rank-up check converted into a level gain
   this month."). Grep `InsightsTests` for the old string.
5. **Unitless month deltas** — `TrainingStore+Insights.swift:516`:
   `"\(item.stat.name): \(deltaLabel) compared with the previous month."` mixes
   minutes and sessions with no units ("Cardio: +171" vs "Emotional: +1"). Append
   the stat's unit word (the same unit strings the review cards use — "minutes",
   "pages", "sessions"; grep for where "0/180 minutes" is built, likely
   `MetricFormatting` or the snapshot). Result: "Cardio: +171 minutes compared with
   the previous month."
6. **Two contradictory risk lists** — Review tab tags 5 skills "Risk" (urgency
   predicate) while the Dashboard "This Week" sheet's "Rank & Charge" section lists
   only 4 "Losing momentum — close to ranking down" (its own predicate, and it
   excludes Emotional whose charge just reset to 0 post-drop). Find the sheet's
   list builder in `DashboardView.swift` (`weeklyStatusCard` / `statsSheet` /
   `DashboardWeeklyStatus`, ~lines 398–530 — grep "Losing momentum"). Make both
   surfaces derive from the SAME predicate on the shared snapshot (recommend: the
   Review tab's `urgency == .regressionRisk`). If the sheet caps its list (top-N),
   append a "+N more" row — no silent truncation.
7. **"counts" as a unit** — "0/2 counts · needs 2 more" (Review rows), "2 counts
   still needed" (Next Moves), "0 count this week" (Goal auto-title). Replace the
   display word for count-measured skills with "times" (or drop the unit entirely
   for counts: "0/2 · needs 2 more"). This is a display-formatting change only —
   find the unit-word mapping (grep `"counts"` / `"count"` in Views + Domain).

---

## WS5 — P1: Vocabulary & copy unification (mostly mechanical string edits)

✅ **DONE — commit `0217ce5`** (2026-07-15). Unified only labels that
describe the same underlying state: pacing shortfalls now read "Behind",
rank-down proximity reads "At risk", and named progression tiers read "Rank".
Deliberately preserved the detailed-card **FADING** badge because it is a
distinct, milder state (behind this week without an imminent rank-down), not a
synonym for At risk/Rank Drop. Also completed the ceremony rank/charge copy,
removed repeated insight-sheet headings and stale dashboard/settings language,
rewrote weekly resolution narratives, made goal placeholders unit-aware,
pluralized goal/session units, and explicitly connected log actions to each
skill's weekly baseline. Live QA confirmed "Rank Drop" and "Fading" remain
visually and semantically distinct; Strength shows "Baseline Sessions" and
"Behind". 96/96 tests green; widget-inclusive app build succeeds.

**The problem**: the same states carry ~7 different labels across surfaces.
Authoritative term sheet (apply everywhere; grep each banned term):

| Concept | Canonical term | Replaces / banned |
|---|---|---|
| Pacing shortfall this week | **Behind** | "Behind Pace" (keep as pill text "Behind" + context), "behind pace" |
| Close to rank-down | **At risk** | "Risk", "FADING", "Losing momentum — close to ranking down", "Recovery" (badge) |
| Named tier | **Rank** (title = "Practicing" etc.) | "form" ("see the new form"), "Standing" ("Overall Standing" → "Overall Rank") |
| Numeric tier pill | **LV n** via `RankPill` (WS3.4) | "L3", "Lv 4", "Level 3 / 10" (keep "Level 3 of 10" only in prose if needed) |
| The ± meter | **Charge** | "momentum" in any charge context |
| Weekly baseline shortfall (resolved weeks) | **Below baseline** | (already consistent — keep) |

Concrete edits (grep each string, fix all occurrences):
1. Detailed-card pill `FADING` → `AT RISK` (DashboardView detailed cards).
2. This Week sheet rows "Losing momentum — close to ranking down" → "At risk —
   close to ranking down"; section badge "Losing momentum" → "At risk".
3. Review header badge "Recovery" → "At risk" (or "Recovery week" if the verdict
   semantics matter — keep ONE of them everywhere).
4. Rank Drop Pending: body "Tap Reveal to see the new form." → "Tap Reveal to see
   the new rank."; button icon `cloud` → `eye.fill` or `sparkles` (grep the Label in
   the ceremony view); stat cell "FINAL CHARGE / Charge 0" → value just "0", and add
   one explanatory line: "Charge resets to 0 after a rank change." (that's why
   −3 earned ≠ final 0 — currently unexplained).
5. "Ranked down this week" pill in WeeklyReviewDetailView is amber like ordinary
   "Below baseline this week" pills → use `TrainingTheme.danger` red; it's a
   stronger event.
6. Weekly detail card narratives repeat the screen title 7×: "Week of 6–12 Jul
   2026: 0 against 2 added -2 charge." → drop the "Week of …:" prefix inside
   WeeklyReviewDetailView cards (the screen is titled with the week) and fix the
   robotic phrasing: "Logged 0 of 2 — charge -2." / for the drop card: "0 of 3
   logged — Emotional dropped to Level 3 after reaching -4 charge." These strings
   are built in the Domain layer (grep `"against"` in `MythosLog/Domain/`) — check
   `InsightsTests`/`ProgressionTests` for assertions on them.
7. Dashboard hint (detailed layout): "Tap a skill card to open the character
   sheet. Use the action tray when you want to log immediately." → "Tap a skill
   card to open its detail. Long-press a card to log instantly." (There is no
   "character sheet" or "action tray" anymore; verify what long-press actually does
   on each layout and describe that.)
8. Insight sheets duplicate their title ("What To Work On" as sheet h1 AND first
   card header; same for "Standard Day", "What Improved"). Find the sheet view
   (grep `DashboardInsightOption` / `presentedInsight` in DashboardView) and drop
   the duplicated card-level header, keep the icon.
9. Settings strictness description under "Balanced" reads "One step toward zero
   each completed week." — that's the decay rule and is FALSE when the separate
   "Enable decay" toggle is off. Fix: append the dependency to each strictness
   description ("…when decay is on.") or visually nest the strictness picker under
   the decay toggle. Copy-only fix is fine.
10. Settings row description says "Notifications, theme, exports…" but there is no
    theme setting and `AppRootView.swift:155` hard-forces `.preferredColorScheme(.light)`.
    Remove the word "theme" (MoreView row description). Do NOT implement dark mode
    in this pass.
11. Goal editor (`GoalsView.swift`, sheet at ~line 353+): the auto-title
    placeholder renders "0 count this week" before a target is entered. Fix: while
    `targetValue` is empty/0, placeholder = "e.g. 20 pages this week" (derived from
    the selected unit); once a target is typed, live-update to the real generated
    title. Also confirm Save stays disabled until target > 0.
12. Skill detail: hero shows "WEEKLY SESSIONS 0 / 2" (baseline) while the LOG
    ACTIONS card shows "Gym Sessions — 0 / 3 session this week" (habit target) with
    no bridge, plus a singular/plural bug ("0 / 3 session"). Fix plural
    ("sessions"), and add a one-line caption under the log action: "Counts toward
    your weekly baseline (2/week)." Also relabel hero to "BASELINE SESSIONS" if
    that's what it counts (verify which number `weeklyTargetFractionLabel` uses).

---

## WS6 — P1: One charge-meter visual language

✅ **DONE — commit `f56a216`** (2026-07-15). The game-grid-only
`DirectionalChargeMeter` now delegates to the same eight-socket, center-divided
`SignedChargeMeter` used by detailed cards, compact-grid cards, and skill detail.
The game-grid wrapper uses a compact 9pt/3pt configuration that fits its tile;
direction is now encoded by position relative to zero everywhere. Negative
charge uses `TrainingTheme.danger` red on every surface instead of mixing amber
and red. Live QA confirmed the detailed-card meter's new danger tint; 96/96
tests green.

**Problem**: three encodings of the same value.
- Game grid: `DirectionalChargeMeter` (`StatCard.swift:107`) = 4 sockets that mean
  EITHER negative (red, right-aligned fill) OR positive (green, left-aligned fill).
  ±2 look identical apart from color/side — indistinguishable at a glance and for
  color-blind users.
- Detailed cards + skill detail: 8-socket split meter with center divider (correct
  design), but detailed cards color negative AMBER while the game grid colors it RED.

**Fix**:
1. Locate the split meter used by the detailed card / skill detail CHARGE section
   (grep for the divider rendering — likely in `StatCard.swift` or SkillDetailView's
   `chargeSection`). Extract/reuse it as the ONE meter component with a
   `socketSize`/`spacing` API.
2. Replace `DirectionalChargeMeter`'s body with the split-meter rendering at small
   socket size (the game tile currently uses `socketSize: 15, spacing: 7` for 4
   sockets — the 8-socket version needs ~9pt sockets/4pt spacing to fit the same
   width; adjust `honeycomb` metrics from WS2 accordingly). Keep the type name and
   its `summaryLabel` accessibility label so call sites don't churn.
3. Pick ONE negative color (recommend `TrainingTheme.danger` red for negative,
   `TrainingTheme.positiveStrong` green for positive) and apply in all layouts.
   (If product prefers amber-for-mild/red-for-imminent, that's a per-value ramp —
   fine, but it must be the same ramp everywhere.)
4. Verify compact-grid tiles (`compactGridTile`, DashboardView ~1081) use the same
   component.

**Acceptance**: the same charge value renders pixel-identically (modulo size) on
game grid, compact grid, detailed cards, and skill detail; direction is encoded by
position relative to the divider, not color alone.

---

## WS7 — P2: Accessibility

✅ **DONE — commit `ffc63da`** (2026-07-15). Added default Open and named
Log/Update VoiceOver actions to both gesture-only dashboard tile styles. Detailed
cards no longer collapse their real child buttons into one inaccessible element;
their Open action now announces full state plus a meaningful improving/declining/
steady trend instead of exposing the decorative arrow/minus glyph. NEXT MOVES
buttons announce "Log/Update <skill>" and the decorative circular arrow is hidden
from accessibility. `textMuted` now measures 5.45:1 on cards and 4.65:1 on the
darker tertiary surface. XL and AX1 live smoke tests covered Dashboard detailed
cards, Strength detail, and Review; the AX1 pass also prompted responsive command-
strip/status layouts and fixed-size decorative corner badges to eliminate observed
collisions. WS2 had already verified the honeycomb at an even larger AX5 size.
96/96 tests green.

1. **Quick-log is invisible to VoiceOver** — `GameDashboardTile` (DashboardView
   ~1323–1338) uses `LongPressGesture(0.4).exclusively(before: TapGesture)` and
   collapses to one `.isButton` element. Add
   `.accessibilityAction(named: "Log session") { onQuickLog() }` (title from
   `quickLogTitle`). Do the same for any other gesture-only tile (compact grid tile
   — check).
2. **Unlabeled/ambiguous controls**: the grey "−" circle on detailed cards (grep in
   DashboardView detailed card builder — likely collapse/hide) needs an
   `accessibilityLabel` and ideally a clearer glyph (`chevron.up`/`minus.circle` with
   label). The orange circular-arrow button on Review's "NEXT MOVES" header needs a
   label (what is it? find the action; if it's "regenerate/refresh moves", label it
   so). The "Update" buttons in NEXT MOVES should read "Log Cardio" etc. —
   `accessibilityLabel` at minimum; consider renaming the visible text to "Log".
3. **Dynamic Type smoke test** (manual): dashboard honeycomb, detailed cards, skill
   detail, review — at XL and AX1 sizes nothing overlaps (WS2's natural layout
   should make the honeycomb resilient; verify).
4. **Contrast spot-check**: muted caption text (`TrainingTheme.textMuted`) on the
   pastel background in stat tiles ("behind / on pace / risk" labels) — verify ≥4.5:1;
   bump the token if not (one-line change, check it doesn't wash other screens).

---

## WS8 — P2: Insight-sheet content quality (small copy, after WS4/WS5)

✅ **DONE — commit `ed32abf`** (2026-07-15). Standard Day's canned
recommendations are honestly labeled "Tips"; monthly rank bullets now say
"<skill> gained a rank" (with correct multi-rank counts) instead of "Rank gains
landed in…"; and What To Work On rows are real Log/Update buttons that dismiss
the insight and reuse the dashboard's existing primary-habit log sheet. Active
skill matching is driven by one reactive query rather than a fetch per bullet.
96/96 tests green.

- "Standard Day" sheet mixes one data-driven line with three canned generic tips
  (blue bullets: "Protect a recurring 16:00 block…"). Label the canned section
  "Tips" instead of "Insights", or drop it when there's no data behind it.
- "What Improved" bullets: after WS4.5 they gain units. Also "Rank gains landed in
  Cardio." → "Cardio gained a rank." Keep it in the same generator function.
- "What To Work On" repeats Review's Next Moves content verbatim on a third
  surface — acceptable, but make the sheet's rows tappable to the same log/update
  action Review uses (parity, not new design). If out of scope, leave content
  as-is; do not build new navigation.

---

## WS9 — P2: Charge-penalty tuning — INVESTIGATE AND REPORT, DO NOT CHANGE

✅ **REPORT COMPLETE — no behavior/code change** (2026-07-15).

Screenshots show, for the same fully-missed week: Focus 0/10 → −1 charge,
Intellect 0/20 → −2, Cooking 0/2 → −2, while Cardio at 34% completion (61/180) →
−3. Mechanism confirmed in `ProgressionEngine.chargeDelta` (~line 188): delta =
`-floor(shortfall / negativeChargeStep(statKey, level))` — i.e. per-skill,
per-level step config in `TrainingArcConfig`, so a 0% miss on a low-step skill can
cost less than a 34% miss on a high-step skill. This may be intentional tuning, but
it *reads* arbitrary in the weekly review.

Deliverable: a short table (skill × level → negativeStep/positiveStep) dumped from
`TrainingArcConfig`, plus a recommendation, appended to this file under "WS9
findings". Options to present: (a) normalize steps so equal miss-*ratios* produce
equal deltas; (b) keep config but surface the math in the resolution sentence
("−2 charge · 1 per 10 pages missed"). **No code change without the user's
sign-off** — this alters progression outcomes.

### WS9 findings

`negativeChargeStep` is the gap from the current rank's weekly threshold to the
previous rank's threshold; `positiveChargeStep` is the gap to the next rank.
The table below is an exact dump of those derived values. Each cell is
**negative/positive** for that level (`—` means no adjacent rank in that
direction):

| Skill(s) | L1 | L2 | L3 | L4 | L5 | L6 | L7 | L8 | L9 | L10 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Creativity, Curiosity, Emotional, Strength, Cooking | —/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/— |
| Focus | —/9 | 9/10 | 10/10 | 10/10 | 10/20 | 20/20 | 20/20 | 20/20 | 20/30 | 30/— |
| Intellect | —/9 | 9/10 | 10/10 | 10/15 | 15/15 | 15/20 | 20/20 | 20/30 | 30/40 | 40/— |
| Cardio | —/14 | 14/15 | 15/15 | 15/15 | 15/30 | 30/30 | 30/30 | 30/30 | 30/60 | 60/— |
| Reading | —/29 | 29/30 | 30/30 | 30/30 | 30/60 | 60/60 | 60/60 | 60/60 | 60/120 | 120/— |

This reproduces the screenshots exactly: Focus level 2 uses a 9-minute negative
step (`floor(10/9) = 1`); Intellect level 3 uses 10 pages (`20/10 = 2`);
Cooking level 3 uses one session (`2/1 = 2`); and Cardio level 9 uses 30 minutes
(`floor((180 - 61)/30) = 3`). The system is measuring how many adjacent-rank
threshold gaps the shortfall spans, not how much of the target was missed.

**Options:** (a) calculate charge from a normalized completion/miss ratio so the
same percentage miss produces the same delta for every skill; or (b) preserve the
current rank-gap tuning and expose it in the resolution sentence, for example
“−2 charge · 1 per 10 pages missed.”

**Recommendation:** start with (b). The current values follow a coherent rank-band
model and changing to ratios would materially rebalance progression. Explaining
the unit step makes the result auditable without changing outcomes. If user
testing still finds cross-skill penalties unfair after that copy change, treat
ratio normalization as a separately specified and regression-tested domain change.

---

## QA script (run after each workstream, full pass at the end)

1. Debug build on simulator (iPhone 17 Pro) + a physical-device spot-check if
   available.
2. Settings → Debug Tools → **Seed Stagnating** (recreates the audit state: all
   behind, Emotional rank-drop pending).
3. Walk the 25-screenshot route and compare against the originals in `Screenshots/`:
   dashboard (all 3 layout modes via the layout menu), scroll mid-way (status bar),
   Strength detail top/mid/bottom (**sticky Log Session button visible**), Review
   top + scrolled + last-week detail top/mid/bottom, New Goal sheet, Goals list,
   More, Settings (progression + debug), Manage Skills scrolled, History 3M,
   Rank-drop ceremony both screens (via the "Rank changes to review" banner),
   all three insight sheets, This Week sheet.
4. Toggle an 8th skill (Enable Curiosity) → dashboard grids still collision-free.
5. Dynamic Type XL pass on Dashboard + Skill detail.
6. `xcodebuild … test` — 96/96 green; widget target builds.

## Definition of done

- WS1–WS3 (P0) complete = the app no longer has occluded controls, colliding rows,
  or the word "Placeholder" on screen.
- WS4–WS6 (P1) complete = every number/label on screen is true and every state word
  comes from the WS5 term sheet; one charge meter everywhere.
- WS7–WS8 (P2) complete = VoiceOver can do everything touch can; insight copy has
  units and honest labels.
- WS9 = report only, appended here.
- One commit per workstream, tests green at every commit, this file updated with a
  ✅ + commit hash per workstream as you land them.

---
---

# PHASE 2 — Design polish pass (2026-07-15 screenshot review)

Source: 15 fresh screenshots in `Screenshots/` (taken 2026-07-15, post-WS1–WS9)
reviewed with the user. This phase is **aesthetic/structural**, not defect-driven:
the Phase 1 bugs are fixed; the app now *works* but reads as visually clogged.
All Phase 1 ground rules apply unchanged (section 0 above): classic pbxproj (avoid
new files), 96 tests must stay green (grep tests before changing user-facing
strings), CloudKit constraints, seed via Settings → Debug Tools, one commit per
workstream (`WS<N> (<short name>): <headline fix>`), update this file with ✅ +
hash per workstream.

## User's design verdict (verbatim intent — this is the brief)

1. **"The traditional roman font is a bit too much on pages like the Review page,
   but works nicely on the More page."** → The serif face is over-deployed. It
   works at *display* scale (More page "Apprentice", skill detail "Novice") and
   fails at *row/data* scale (Review skill rows, list items, data values).
2. **"Make the information more attractive to view. It seems clogged on many
   pages, and prevents it from being more easily read."** → The density problem
   was diagnosed with the user as: (a) the same information rendered 2–3× per
   screen, (b) every section wrapped in a bordered card with a letterspaced
   uppercase header, (c) permanent inline explanatory prose, (d) status-pill
   fatigue (every row alarmed → nothing stands out).

These two decisions are **already made by the user** — do not re-litigate them,
and do not "compromise" by half-keeping serif rows.

## Phase 2 design rules (apply everywhere; each WS cites them)

- **R1 — Serif is for identity, sans is for information.** The serif face may
  appear on: page/hero titles (`V4SerifTitle`), rank titles ("Novice", "Steady
  Trainee", "Apprentice"), weekly verdict titles ("At Risk", "Held Form"), and
  onboarding display text. Everywhere else — list-row titles, card row labels,
  data values, dates, button labels — use the sans system font (semibold for row
  titles, `.monospacedDigit()` for numbers). `V4LevelBadge`'s small serif numeral
  and `V4StatTile`'s serif value are **kept** (signature elements, and the user
  approves the pages that lean on them — More, History overview, skill hero).
- **R2 — Say it once.** A fact (skill X is at risk / needs N more / will unlock Y)
  appears at most once per screen. Where two surfaces on one screen currently
  repeat it, keep the more actionable surface and delete the other.
- **R3 — Cards earn their border.** A bordered `V4Card` + uppercase header is for
  the 1–3 primary blocks of a screen. Secondary content (lists, link rows,
  captions) sits directly on the background or in a single flat group. Never nest
  a bordered card inside a bordered card.
- **R4 — Explanations are on-demand.** Persistent captions that explain mechanics
  ("Strength is measured in sessions. Edit this if…", "Off by default. When
  on…") move behind the existing `(?)`/help affordances or a `footer`-style
  single line. First-run copy is fine; permanent copy is not.
- **R5 — Alarm once, not per row.** When several rows share the same status, the
  status is expressed by grouping (one header per status group), not by repeating
  an identical pill on every row.

## Key files for Phase 2 (line numbers verified 2026-07-15 — re-grep before editing)

| Surface | File / anchor |
|---|---|
| Shared style kit | `MythosLog/Views/Components/V4Style.swift` (`V4SerifTitle` :199, `V4StatTile` :127, `V4Card` :151, `V4PageKicker` :19, `V4StatusPill` :95) |
| Review tab | `MythosLog/Views/WeeklyReview/WeeklyReviewView.swift` (summary card :158, NEXT MOVES card :184, skill rows :256 — serif row title :276, urgency enum :635) |
| Skill detail | `MythosLog/Views/Habits/SkillDetailView.swift` (hero :317, calibration :386 — caption :414, charge card :530 — serif value :552, next-rank card :566, goals empty state serif :508, log-action habit name serif :656) |
| Dashboard game grid | `MythosLog/Views/Dashboard/DashboardView.swift` (`GameDashboardTile` :1386 — serif tile name :1436; honeycomb :861; RANK & CHARGE highlights card :582 — serif row name :672; This Week sheet `statsSheet` :237, `weeklyStatusCardBody` :481) |
| History | `MythosLog/Views/History/HistoryView.swift` (double title :130–137, overall grid :197, serif strongest/neglected :245/:256, chart + resolved rows :360–410) |
| Goals | `MythosLog/Views/Goals/GoalsView.swift` (serif empty body :158, serif goal row title :207) |
| Manage Skills | `MythosLog/Views/Skills/ManageSkillsView.swift` (serif row :82) |
| Weekly detail | `MythosLog/Views/WeeklyReview/WeeklyReviewDetailView.swift` (serif :323, :366, :451, :494) |
| Habit detail | `MythosLog/Views/Habits/HabitDetailView.swift` (serif :97, :294, :339, :345) |
| Rank ceremony | `MythosLog/Views/Dashboard/RankChangesReviewView.swift` (serif :70) |
| Settings | `MythosLog/Views/Settings/SettingsView.swift` (Toggles :205–296) |

---

## WS10 — P0: Typography — demote the serif to display-only (rule R1)

✅ **DONE — commit `ac99cc3`** (2026-07-15). Converted all row/data-scale serif
call sites to sans (semibold row titles, `.monospacedDigit()` values) per the
line list below. Two judgment calls beyond the plan's explicit list: kept
`SkillDetailView.swift:837` (hero baseline/pace metric) and
`DashboardView.swift:425`/`:549` (the "Rank changes to review" banner title and
WEEKLY STANDING ahead/on-pace/behind counts) serif — all four are stat-tile-analog
readouts rendered once per screen, not repeated rows, so they fall under the same
carve-out as `V4StatTile`. Also overrode the plan's instruction for
`HistoryView.swift:369`: re-reading the code showed it renders
`stat.currentTierName` (e.g. "Practicing") next to a level badge — an actual rank
title, not a "resolved-week card title" as originally described — so it was kept
serif per the rank-title carve-out instead of converted. Also converted the
week-date navigator at `SkillDetailView.swift:755` (not in the original numbered
list but an italic serif date, squarely R1's "dates go sans" rule) and dropped
`.italic()` from the two editable text fields in `HabitDetailView.swift`
(:339/:345) since italic serif on a live-typing field reads oddly once the
field itself is sans. `grep -rn "design: .serif" MythosLog/Views` now returns
only `V4Style.swift`, the kept call sites above, `MoreView.swift` (untouched, the
page the user said works), and `OnboardingFlowView.swift`. 96/96 tests green;
widget-inclusive app build succeeds.

**What the user sees today**: serif skill names on every Review row, every RANK &
CHARGE row, every dashboard tile, Manage Skills rows, goal cards, habit-log card
titles, the "Charge +1" data readout, italic serif dates on History cards — the
"wine list" effect.

**Change** (mechanical; each bullet is a font-swap at the cited line, replacing
`.font(.system(.headline/.subheadline/…, design: .serif)…)` with the sans
equivalent — use `.font(.headline.weight(.semibold))` for row titles,
`.font(.subheadline.weight(.semibold))` for sub-rows, keep existing colors):

1. `WeeklyReviewView.swift:276` — Review skill-row name → sans semibold.
2. `DashboardView.swift:672` — RANK & CHARGE highlight row name → sans semibold.
3. `DashboardView.swift:1436` — `GameDashboardTile` name → `.subheadline` sans
   semibold (size ≈15 already; keep `minimumScaleFactor`).
4. `DashboardView.swift:425` and `:549` — grep these two serif uses (header-card
   greeting / insight titles); if they are row/data scale per R1, convert; if they
   are the screen's single hero, keep. Judge against R1, note the decision in the
   commit message.
5. `ManageSkillsView.swift:82` — skill row name → sans semibold.
6. `GoalsView.swift:207` — goal row title → sans semibold; `GoalsView.swift:158`
   — empty-state body copy → plain `.subheadline` sans (body copy was never a
   title).
7. `SkillDetailView.swift:508` — "No growth goal set…" body copy → sans
   `.subheadline`; `:656` — habit/log-action card name → sans semibold; `:552` —
   the "Charge +1" value → sans `.title3.weight(.semibold)` with
   `.monospacedDigit()` (it is a data readout); `:1039` — grep context, same rule.
8. `HistoryView.swift:245`, `:256` — STRONGEST / MOST NEGLECTED skill names →
   sans semibold (keep tint); `:369`, `:406` — resolved-week card titles/dates →
   sans semibold, drop any `.italic()`.
9. `WeeklyReviewDetailView.swift:323`, `:366`, `:451`, `:494` — per-skill card
   titles and narrative lines → sans (the verdict `V4SerifTitle` at :202 stays).
10. `HabitDetailView.swift:97`, `:294`, `:339`, `:345` — row-scale serif → sans
    (`V4SerifTitle` heroes at :43/:272 stay).
11. `RankChangesReviewView.swift:70` — grep context; ceremony *rank titles* stay
    serif, list-row text goes sans.
12. `SkillDetailView.swift:451` (calibration number cells) — **keep serif**
    (stat-tile parity with More, R1 carve-out). `V4LevelBadge`, `V4StatTile`,
    all `V4SerifTitle` call sites, and `OnboardingFlowView` — **keep**.

**Explicitly kept serif surfaces** (so the diff reviewer can check intent):
skill detail rank title (:330) and next-rank title (:604), More page (all
current uses — the user singled this page out as working), History `V4SerifTitle`
empty state, Review last-week verdict (:437), weekly-detail verdict (:202),
dashboard "No skills yet" / "Reorder Skills", onboarding.

**Acceptance**:
- `grep -rn "design: .serif" MythosLog/Views` returns ONLY: V4Style.swift
  (components), the kept call sites listed above, and OnboardingFlowView.
- Review page shows zero serif below the verdict title; dashboard tiles, Manage
  Skills, Goals rows all sans.
- No test asserts on fonts (they don't), but run the full suite anyway; build the
  widget target (it may share components).

---

## WS11 — P0: Review page consolidation (rules R2, R3, R5)

✅ **DONE — commit `8b5c729`** (2026-07-15). Implemented per the plan: deleted
the second kicker, replaced the bordered summary card with a flat strip (status
pill + inline "N behind · N on pace · N at risk" via concatenated `Text` +
`monospacedDigit()`, still derived from `reviewUrgency`'s disjoint buckets),
deleted the NEXT MOVES card and moved its log action onto at-risk/behind rows
(same accessibility label/hint preserved), regrouped the flat 7-row list into
AT RISK / BEHIND / ON PACE sections with group headers replacing the per-row
`V4StatusPill`, and slimmed the Last Week card (deleted the recovery chip strip,
made `verdict.description` conditional on `belowBaseline == 0` so the at-risk
copy isn't stated twice). Removed the now-dead `ReviewSkillUrgency.icon`/`.tint`/
`.label(for:)` members (only called by the deleted rows) and added a
`ReviewUrgencyGroup` enum for the grouping. 96/96 tests green; app builds clean.
Not yet done as part of this commit: a live simulator walkthrough — deferred to
the Phase 2 final QA pass (see bottom of this file) so it covers WS10-WS17 in
one sweep against the current `Screenshots/` set.

**What the user sees today** (top→bottom): kicker "WEEKLY DIAGNOSTIC" → second
kicker "THIS WEEK · LIVE" → summary card (3 stat tiles + narrative sentence) →
NEXT MOVES card (top-3 behind/at-risk skills with Update buttons) → full 7-row
skill list (same skills again, same "needs N more" copy, a pill on every row) →
LAST WEEK kicker → verdict card ("At Risk", "6 skills need recovery", narrative,
4 recovery chips + "+2 more" — the same skills a third time — and a big CTA) →
past-reviews link. The at-risk story is told **three times**.

**Target structure** (one screen, ~half the vertical space):

1. **One kicker**: keep `V4PageKicker(title: "Weekly Diagnostic")` (:79), delete
   the second kicker "This Week · Live" (:131) — two eyebrows on one screen is
   noise (R3).
2. **Summary strip, not a card**: replace `thisWeekSummaryCard` (:158) with a
   compact flat header: the `V4StatusPill` headline + the three counts rendered
   inline in sans (e.g. "3 behind · 0 on pace · 4 at risk" with tinted numbers) +
   the single `diagnosticSummaryText` sentence. No `V4Card` border, no
   letterspaced "THIS WEEK" header. Counts stay derived from `reviewUrgency`
   (WS4.3's disjoint-bucket fix — do not regress it; the three numbers must still
   sum to the skill count).
3. **Delete the NEXT MOVES card entirely** (`recoveryPlannerCard` :184 and
   `recoveryTaskRow` :214). Its content is a strict subset of the skill list. Its
   one unique feature — the direct log/Update action — **moves onto the list
   rows** (next point). Remove `recoveryItems` (:122) if now unused.
4. **One grouped skill list** replacing the flat 7-row card (:142–154), grouped
   by urgency with flat group headers (R5): "AT RISK (n)", "BEHIND (n)",
   "ON PACE (n)" (merge `.steady` + `.complete` into the last group; skip empty
   groups). Within a group, rows keep icon + name (sans, per WS10) + the
   `progressLine` metric, and **drop the per-row `V4StatusPill`** (:288) — the
   group header now carries the status. Rows in the AT RISK and BEHIND groups
   gain a trailing compact log button (reuse `logActionTitle(for:)` :359 and
   `openSkill(_:openLogSheet: true)` :363 — the exact behavior the deleted NEXT
   MOVES rows had, including their `accessibilityLabel`/`accessibilityHint`;
   WS7's VoiceOver guarantees must survive the move). Tapping the row body still
   opens the skill detail (openLogSheet: false).
5. **Slim the Last Week card** (`resolvedSummaryCard` :412): keep verdict
   `V4SerifTitle` + icon + the "n skills need recovery" line + the CTA button.
   **Delete the recovery chip strip** (`recoveryChipStrip` :491,
   `recoveryChip` :514, `recoveryMoreChip` :541) — third rendering of the same
   skills (R2); the CTA already goes to the full breakdown. Also delete the
   `verdict.description` sentence if the "n skills need recovery" line is present
   (two summaries of one fact).
6. Keep `pastReviewsLink`, the explainer sheet, and the empty states as-is.

**Acceptance**:
- Each skill name appears exactly **once** on the Review screen (excluding the
  summary sentence's single named skill).
- Zero `V4StatusPill` per-row instances in the skill list; group headers carry
  status. At-risk/behind rows have a working, VoiceOver-labeled log action.
- The three summary counts still sum to the active-skill count (Seed Stagnating:
  7).
- Grep the test suite for strings you delete (e.g. "still needed to protect") —
  `taskText(for:)` remains used by `diagnosticSummaryText`; keep it.

---

## WS12 — P1: Skill detail de-duplication (rules R2, R3, R4)

✅ **DONE — commit `30062dc`** (2026-07-15). Merged CHARGE + NEXT RANK into one
`progressionSection` (crest shown only when not at max rank, single
`nextRankStatusLabel` sentence, one help button). Collapsed the two help
topics into `.progression`, whose `helpBody` concatenates the live charge
explanation with the next-rank static copy so both stay reachable from one
(?) tap. Deleted calibration's permanent unit-explainer sentence (its
guidance now lives in the Recalibrate sheet's existing "Measurement Unit"
section footer) and deleted `calibrationStatusLabel`/its call entirely — it
restated the hero's baseline fraction + pace pill. `calibrationSection()`
dropped its now-unused `snapshot` parameter. Goals empty state is a flat
sentence instead of a bordered two-line card. The LOG ACTIONS baseline
caption now renders once above the list for multi-habit skills instead of
once per card (kept per-card for the single-habit case). 96/96 tests green;
app builds clean. Live-simulator confirmation deferred to the Phase 2 final
QA pass (bottom of this file), same as WS11.

**What the user sees today**: hero (rank art + baseline/pace) → week strip →
CALIBRATION card (permanent explainer sentence + 3 stat cells + status sentence)
→ CHARGE card ("Charge +1" + meter + `nextRankStatusLabel`) → NEXT RANK card
(crest + "LOCKED · LV 4" + title + **the same `nextRankStatusLabel` again**,
:558 and :605) → GOALS → LOG ACTIONS → history. Five bordered cards, the unlock
sentence twice, the baseline shortfall stated in both hero and calibration.

**Changes**:

1. **Merge CHARGE + NEXT RANK into one "PROGRESSION" card** (replaces
   `chargeSection` :530 and `nextRankSection` :566): next-rank crest
   (`RankArtworkView` .compact) on the left; on the right the charge value line
   (sans, per WS10), the charge meter (`chargeDots`, unchanged — WS6 component),
   and **one** `nextRankStatusLabel` line + "LOCKED · LV n — <nextTitle>" (the
   `V4SerifTitle(nextTitle)` stays, R1). One card, one (?) button (keep both help
   topics reachable: merge into a single help sheet or two stacked rows in it —
   `presentedHelpTopic` supports `.charge`/`.nextRank`; simplest is one button
   presenting `.nextRank` whose sheet also explains charge — check what
   `HelpTopic` renders and pick the lighter diff).
2. **Calibration slims down** (R4): delete the permanent explainer sentence
   (:414 "…Edit this if you want to track minutes, pages, or another unit.") —
   that guidance moves into the Recalibrate sheet itself (add it there as a
   footer if not already present). Keep the 3 stat cells (serif kept per WS10.12).
   **Delete the `calibrationStatusLabel` sentence** (:436, :460–477) — the same
   fact ("Below baseline — complete N…") is already the hero's pace pill +
   baseline fraction (R2). If product wants the actionable phrasing kept, put it
   in ONE place: as the pace pill's subtitle in the hero, not in a second card.
3. **Goals empty state** (:504–514): collapse to a single-line flat row ("No
   growth goal yet — Add one to push past your baseline.") without a bordered
   card (R3).
4. **LOG ACTIONS caption** (:664 "Counts toward your weekly baseline (2/week).")
   — keep (it earns its place, WS5.12 added it deliberately), but it appears per
   habit card; if more than one habit is linked show it once under the section
   header instead of inside every card.
5. Re-check the sticky Log Session button clearance after the page shortens
   (WS1's `.padding(.bottom, 36)` at :182 — unchanged, just verify).

**Acceptance**: `nextRankStatusLabel` rendered exactly once; "Below baseline…"
phrasing appears at most once on the screen; card count on Strength (Seed
Stagnating) drops from 5 bordered cards to ≤3 above the history section; both
help topics still reachable; 96 tests green (grep `InsightsTests`/copy tests for
deleted strings first).

---

## WS13 — P1: Dashboard game-grid readability

✅ **DONE — commit `0ad6e29`** (2026-07-15). `RankArtworkView.dashboardBareArtwork`
now fills whatever space the parent ring gives it and clips both the
character-image and icon-fallback branches to the same `Circle()` (confirmed
via grep that `.dashboardBare` is only used by the game-grid tile, so this
doesn't touch the compact/detailed layouts). The tile name label's gutter is
now symmetric (`.padding(.horizontal, 26)`, was trailing-only) so the
top-leading attention dot/unmatched badge and the top-trailing rank badge both
clear the name and it reads centered. The charge meter dims to 60% opacity at
charge 0 so charged tiles stand out. Did not fork or touch the WS6 shared
meter component itself, per the plan's guardrail. 96/96 tests green; app
builds clean. Live simulator confirmation (including the AX5 honeycomb
collision spot-check the plan calls for) deferred to the Phase 2 final QA
pass, same as WS11/WS12.

**What the user sees today**: two tiles have full illustrated characters
(Creativity, Strength) while five have flat SF-symbol crests at a visibly
different scale; the attention dot touches the first letter of the name
("●Creativity"); each tile stacks name + ring + fraction + LV + an 8-socket
meter — texture that can't be parsed at grid size.

**Changes** (all in `DashboardView.swift` / `RankArtworkView.swift`):

1. **Unify artwork treatment**: in `GameDashboardTile` (:1461,
   `style: .dashboardBare`), render BOTH cases inside the same circular
   container: character images get `.clipShape(Circle())` scaled to fill the ring
   interior (same diameter as the crest circle), crests keep their current
   look. No tile's art may overflow its ring (the Strength figure currently
   pokes above it). Do this in `RankArtworkView`'s `.dashboardBare` branch so
   compact grid inherits it.
2. **Attention-dot spacing**: find the dot rendered beside the tile name (grep
   `needsAttention` in `GameDashboardTile`/honeycomb) and give it 4–6pt spacing
   from the text (it currently kisses the glyph).
3. **Slim the tile metric stack**: keep name, ring, and the `fraction · LV n`
   line (:1474–1490). For the `DirectionalChargeMeter` row (:1492): keep the
   component (WS6 — do NOT fork the meter), but render it at 60% opacity when
   `charge == 0` so neutral tiles recede and charged tiles stand out. Do not
   remove it outright without user sign-off (it's the only at-a-glance charge
   signal on the dashboard).
4. **Label row balance**: tile names are top-aligned with a reserved 26pt badge
   gutter (WS2) which makes short names look off-center. Center the name and
   keep the badge overlay from colliding via the existing fixed gutter — verify
   with "Creativity" + a pending-rank badge (Seed Stagnating shows 7 badges).

**Acceptance**: all 7 tiles read as one family (same silhouette size, art clipped
to ring); no art overflows; dot has visible spacing; zero-charge meters visibly
quieter than charged ones; WS2's no-collision guarantees still hold at AX5 (spot
check).

---

## WS14 — P1: "This Week" sheet de-duplication (rules R2, R5)

✅ **DONE — commit `244354c`** (2026-07-15). Confirmed via the domain code
(`computeDashboardHighlights` in `TrainingStore+Insights.swift`) that the
highlight list genuinely mixes kinds, so implemented the plan's fallback:
grouped visible rows by kind with one header per group stating the shared
fact once, kept the per-row caption only for `.rankedUp` (its text varies per
skill), and removed the single top-right tagline pill (it could only reflect
one kind and became redundant/misleading once groups had their own headers).
The existing "prefix(4) + un-silenced +N more" truncation from WS4.6 is
unchanged. 96/96 tests green; app builds clean.

`DashboardView.swift` `statsSheet` :237 / `weeklyStatusCardBody` :481 /
`highlightsCard` :582.

1. The RANK & CHARGE list renders "At risk — close to ranking down" as the
   subtitle of every row (4× in the screenshots). Since WS4.6 the list derives
   from one predicate, so the subtitle is constant per group — replace per-row
   repeated subtitles with **one** line under the "RANK & CHARGE" header ("These
   skills are close to ranking down.") and keep rows to icon + name + LV badge +
   chevron (R5). If the highlight list can mix kinds (`rankedUp`, `nearRankUp`,
   `losingMomentum` — see `DashboardHighlight.Kind`), group rows by kind with a
   one-line subtitle per group instead.
2. Keep the WEEKLY STANDING bar + ahead/on-pace/behind counts (unique content).
3. GOALS strip stays (unique content), but verify its "1 At risk" tile agrees
   with the Goals tab (same predicate — spot-check, WS4 territory).

**Acceptance**: no sentence appears twice on the sheet; "+N more" truncation row
(WS4.6) still present when >4 highlights.

---

## WS15 — P2: History page polish

✅ **DONE — commit `396017c`** (2026-07-15). Dropped the in-scroll serif
"History" hero (kept the kicker), matching Review/Goals which have no
in-scroll hero above the nav title. **Deviated from the plan's chart
instruction after reading the actual code**: `statChart` already tints its
actual-value bars with the skill's accent via `.gradient` — the "flat dark
ink" the screenshot showed was the neutral baseline reference `LineMark`,
visible on its own only because that particular week's actual values were
all zero (invisible zero-height bars), not a missing tint. Retinting that
reference line would have made it indistinguishable from the accent-colored
bars it's meant to contrast against, so instead added a soft accent-tinted
`.chartPlotStyle` background wash behind the whole plot — keeps the skill's
identity present even in a zero-activity week without touching the
actual/baseline color distinction. Pure visual change. 96/96 tests green;
app builds clean.

`HistoryView.swift`.

1. **Kill the double title** (:121 `navigationTitle("History")` + :133 serif
   38pt "History"): keep the serif hero, change the nav title to
   `.navigationBarTitleDisplayMode(.inline)` with an **empty/blank principal**
   while at top — simplest compliant fix: drop the serif hero block entirely and
   let the nav title stand (R2). Pick ONE; do not show both. (Recommend dropping
   the in-scroll hero — one line saved, matches Review/Goals which have no
   in-scroll hero.) Keep the kicker if it survives visually.
2. **Chart identity**: the trend line renders in flat dark ink on a bare grid.
   Stroke it with the selected skill's accent
   (`TrainingArcConfig.color(for: stat.colorToken)`), add a soft
   accent-to-clear `LinearGradient` fill under the line (find the chart builder
   `statChart(for:)` — grep; it's custom Path/Charts code around :300–360), and
   keep gridlines as-is. Pure visual; no data change.
3. Serif swaps at :245/:256/:369/:406 land in WS10 — nothing more here.
4. The OVERALL 6-stat grid (:226–233) stays (user hasn't objected and it's
   unique content).

**Acceptance**: exactly one "History" title visible; chart line/fill uses the
skill accent; switching skills in the picker re-tints the chart.

---

## WS16 — P2: Settings — knit into the app's visual language

✅ **DONE — commit `f64c242`** (2026-07-15). Added
`.tint(TrainingArcConfig.color(for: "focus"))` to the `List` root — the same
generic accent `OnboardingFlowView` already uses for non-skill-specific
controls. Confirmed the Workout Types disclosure-group toggles are in the
same `List` hierarchy (not a separate pushed view), so one tint covers them
too; no per-control changes needed. Left copy/structure/footers untouched
per the plan. 96/96 tests green; app builds clean.

`SettingsView.swift`. The page is stock-iOS (green toggles) inside a parchment
app. Minimal knit, not a redesign:

1. Apply `.tint(TrainingArcConfig.color(for: "focus"))` (or the app's primary
   accent — check what onboarding uses) to the settings `Form`/`List` root so
   every Toggle renders in the app accent instead of system green (:205–296).
2. Verify section header styling matches other pages' caption case; leave
   structure, copy, and grouping alone (WS5.9/5.10 already fixed the copy).
3. Explanatory footers under toggles are legitimate `Form` footers (R4-compliant
   pattern on a settings screen) — keep them.

**Acceptance**: no system-green toggle anywhere in Settings (screenshot check
against `Screenshot …14.06.17.png`/`14.06.22.png`); everything else pixel-same.

---

## WS17 — P2: Goals page balance

✅ **DONE — commit `e82a01d`** (2026-07-15). Section headers ("ACTIVE") now
only render when `nonEmptyGoalGroupCount > 1` — a single-group screen relies
on the page kicker alone, matching the plan's intent; multi-group screens
keep headers since they're then load-bearing. The progress bar now clamps to
a minimum 3pt accent fill at 0% instead of a literal zero-width bar.
Investigated the footer-link item: grepped the codebase and confirmed no
goals-affect-pacing explainer sheet exists anywhere (only a Settings toggle
with its own inline description) — per the plan's explicit fallback, skipped
building new navigation; the existing per-card "Tracking only…" caption
already covers it. 96/96 tests green; app builds clean.

`GoalsView.swift`. The page is one card floating in a full screen of empty
parchment (opposite problem from Review).

1. Collapse the double header: `V4PageKicker("Targets & Pacing")` + "ACTIVE"
   section label + a single card = three layers of chrome for one item. Keep the
   kicker, drop the "ACTIVE" label when there's only one section rendered.
2. Give the goal card a visible progress bar fill: the screenshot shows an empty
   track with `0 / 50` below — at 0 progress render a 2–3pt accent "spark" at the
   leading edge so the bar reads as "empty by data" rather than "unstyled" (grep
   the goal row's ProgressView/track builder at :180–230).
3. Add a lightweight footer link-row "How goals affect pacing →" opening the
   existing goals explainer if one exists (grep `goalsAffectPacing` copy in
   Settings for the explanation text; if no sheet exists, render the one-line
   caption "Tracking only — doesn't affect charge or rank." exactly once — it's
   already on the card (:158 area) — and skip the link). Do NOT build new
   navigation for this (parity with WS8's restraint).
4. Serif swaps (:158, :207) land in WS10.

**Acceptance**: one header layer above the card; empty-progress state looks
intentional; no new sheets unless one already existed.

---

## Phase 2 sequencing, QA & definition of done

**Order**: WS10 → WS11 → WS12 → WS13 → WS14 → WS15 → WS16 → WS17. WS10 first —
it touches the most files mechanically and every later WS builds on its fonts.
WS11 and WS12 are the user-visible payoff; do not start WS13+ before they land.

**QA script per workstream** (same harness as Phase 1):
1. `xcodebuild -project MythosLog.xcodeproj -scheme MythosLog -destination
   'platform=iOS Simulator,name=iPhone 17 Pro' test` — 96/96 green — then build
   the widget target.
2. Settings → Debug Tools → **Seed Stagnating**; walk the 15-screenshot route
   (Dashboard game grid + layout menu, Strength detail full scroll, Review full
   scroll, Goals, More, Settings both scrolls, History 3M both scrolls, Manage
   Skills, This Week sheet) and compare against `Screenshots/` (2026-07-15 set)
   for regressions.
3. Dynamic Type XL spot-check on any screen whose layout you changed (WS11,
   WS12, WS13 especially — WS2/WS7 set the bar: zero collisions at AX sizes).
4. VoiceOver spot-check on Review after WS11 (log actions moved — labels/hints
   must survive).

**Definition of done (Phase 2)**:
- WS10: serif appears only on the kept-list surfaces; Review page has no serif
  below its verdict title.
- WS11–WS12: no fact rendered twice on Review or Skill detail; Review's skill
  names each appear once; per-row status pills replaced by group headers.
- WS13–WS14: dashboard tiles read as one family; This Week sheet has no repeated
  sentence.
- WS15–WS17: single History title, accent-tinted chart, app-accent toggles,
  balanced Goals page.
- One commit per workstream, ✅ + hash recorded here, tests green throughout.
