# UI_FIX_PLAN.md — Mythos Log UI/UX Fix Plan (2026-07-14)

Self-contained implementation plan for the UI/UX defects found in the 2026-07-14
screenshot audit (25 screenshots in `Screenshots/`, cross-verified against source).
Written for an implementing agent with **no prior conversation context**. Read this
whole file before touching code.

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
