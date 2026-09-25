# UI refinements — approved scope

## Implemented

- Dashboard: unchanged skill tiles, charge and character artwork by default; quieter flat header controls and reduced tab-bar decoration.
- Settings → Experience: two local display preferences, off by default. Dashboard icons affect all three dashboard layouts. App-wide icons override dashboard-only mode and include skill details, roster thumbnails, carousel artwork and rank reveals. Disabling app-wide mode restores the dashboard-only preference. These are device-local visual preferences, not progression settings.
- Skill Detail: removed the bottom Log Actions section and duplicate quick-log controls. The floating date-aware Log action remains. Habit creation/editing is reachable through Manage Habits in the toolbar.
- Review: retained urgency groups and direct logging, simplified the summary, reduced card decoration and removed the excessive bottom allowance. Past-review detail now discloses per-skill and Apple Health summaries.
- Goals: shorter empty state with optional explanation, restrained cards, one main status and neutral acknowledgement wording.
- History: Overview / By Skill modes, expandable effort ranking and resolved-week history. Selecting a skill from effort ranking opens its analysis.

## Icon and button scope

Implemented header icons use medium-weight symbols with 44-point button frames and a subtle active background instead of gradients and shadows. Tabs retain their labels and symbols with quieter outlines and selection styling. Optional character replacements use the existing skill symbols and colors. No broad global icon, button or Settings redesign was applied.

Proposed for a later pass: one standard tinted icon container for list rows, one primary filled action and quieter text/outline secondary actions. Progress rings should remain progress indicators, not decorative frames around every icon.

## Verification

- Full app and embedded widget simulator build succeeded after final source changes.
- Source whitespace checks passed for changed view files.
- Standalone illustrative dashboard preview rendered in the browser; artwork/icon switching was checked.
- Native simulator visual checks were not completed: the shared simulator was occupied by another app. The preview is illustrative, with sample values, and is not a native app screenshot.
- No progression, schema or data-migration changes were introduced for this UI pass.

## Selected mockup implemented — 16 September

The native dashboard now follows the user-selected artwork mockup: flat warm background, compact abbreviated date, text-only This Week chip, outlined layout control, 2–3–2 arrangement with 24-point row gaps, full-width skill labels, flat seven-point charge dots, and a solid neutral tab bar with outlined symbols and white selection pill. Skill ordering, artwork selection by rank, weekly totals, signed charge behavior and icon preferences remain data-driven. This does not add the screenshot viewer’s down-arrow overlay to the app.
