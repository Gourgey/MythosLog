# Mythos Log: Build Plan

What each App Store Connect build contains, and what changed between them.
Update this file whenever a build is uploaded.

---

## Build numbers

Xcode's distribution step ("Manage Version and Build Number", on by default)
renumbers a build when App Store Connect already has that number. Twice the
archived number has been one behind what App Store Connect had, so **the
number in App Store Connect is the one that counts**. The archive's own
`Info.plist` records both (`CFBundleVersion` and `uploadedBuildNumber`).

| ASC build | Archived as | Uploaded | Code | Notes |
|---|---|---|---|---|
| 1 | 1 | 2026-09-25 | `e48f7ab` | First 1.0 submission build. |
| 2 | 2 | 2026-09-27 | | Health imports moved to a local-only store. |
| 3 | 3 | 2026-09-29 | | |
| 4 | 4 | 2026-09-29 | | Submitted 2026-09-29; rejected 2026-10-06 (4.3, 4.2.6). |
| 5 | 4 | 2026-10-06 | `675f7c7` | Health import to local store, background widget refresh. Xcode renumbered 4 → 5. |
| 6 | 5 | 2026-10-09 13:12 UTC | `540ce1d` | First round of TestFlight feedback (below). Xcode renumbered 5 → 6. |
| 7 | 6 | 2026-10-09 13:20 UTC | `540ce1d` | Same code as 6, re-archived after the project was set to 6; Xcode renumbered 6 → 7. Use 7 for testers. |
| 8 | | | | Next upload. Set the app **and** widget extension to 8 before archiving. |

The app and the widget extension should always carry the same build number.
At the time of writing the working copy has the app at 6 and the widget at 5;
both should be set to 8 before the next archive.

---

## Builds 6 and 7 (ASC), 2026-10-09

Commits `e8272be` (2026-10-09 10:57) and `540ce1d` (2026-10-09 14:05).
Work done 2026-10-08 to 2026-10-09 from the first TestFlight feedback.

### Tester feedback and changes

| Feedback | Change |
|---|---|
| A skill deselected during setup still appeared on the "current level per week" page. | Setup now picks skills, not starter habits. Only picked skills appear on the rank page. |
| Cardio was deselected but still on the dashboard; Strength was deselected but still under Active Skills in Manage Skills. | Unpicked skills (core ones included) start archived, so they are off the dashboard and Manage Skills' active list and can be restored later. A launch-time migration no longer re-enables archived core skills, and a fresh profile skips the one-time optional-skill archive pass. |
| The setup level page should show current, goal and maximum per skill; should the goal simply be the Level 10 target? | Target and personal max are merged into one **Level 10 goal**: the weekly amount that equals the top rank, with the ranks below scaled evenly up to it. Each setup card shows Current and Level 10 goal side by side. The separate Calibrate step is removed. |
| The setup level page shouldn't show +1/-1 style chips; + and − and the custom number are enough. | Quick-adjust chips removed (and their config). |
| Current and goal were shown twice on the setup card. | Current and Level 10 goal are tappable values; the large −/number/+ editor changes whichever is selected. Suggest and Clear appear when the goal is selected. |
| Explain how charge works; make the intro pages clearer with example screenshots. | New welcome page with the Cardio character at Levels 2, 5 and 9, and a Charge page with a worked Strength example (charge meter over three weeks) and the four charge rules. Page dots moved out from over the content. |
| The number of meals can't be changed when logging cooking. | The log sheet's amount row is named after the unit (MEALS, PAGES) and has − and + buttons. Quick-log buttons use the habit's unit ("+1 meal"). Removing the button below (next row) also stops the amount row being covered on the half-height sheet. |
| What does "Save for later" do when logging? | It only closed the sheet without saving, so it is removed. ✕ still cancels. |
| No Done button to dismiss the keypad when entering a target or personal max in Recalibrate. | Done added to the keyboard on Recalibrate and on the Level 10 goal screen. |

### Other changes in this build

- **Curiosity and Reading skills removed.** Gone from the catalog, setup,
  App Shortcuts, the widget and Settings → Connect Apps. Intellect keeps its
  Reading Pages habit and "Log Reading Pages" shortcut; the Kindle shortcut
  example now logs pages to Intellect. Existing installs delete any leftover
  Reading/Curiosity skill (with its habits, logs, resolved weeks and linked
  goals) at launch. `AppSettings.lastReadingBookTitle` stays in the model,
  unused, so the CloudKit schema is unchanged.
- **Dashboard fills the screen with fewer skills.** The honeycomb has a row
  arrangement for every count from 1 to 7 (7: 2·3·2, 6: 2·2·2, 5: 2·1·2,
  4: 2·2, 3: 2·1, 2: 1·1, 1: 1) and sizes rings from both width and height.
  On iPhone, rings can grow to 200pt with two per row and 260pt with one.
- Recalibrate, Manage Skills, Skill Detail, History and Settings show the
  single Level 10 goal in place of Target and Personal Max.

### CloudKit

No model fields were added or removed. No schema deploy is needed.

### Tests

129 unit tests pass (2026-10-09), including new tests for onboarding skill
selection and for removal of retired skill rows.

---

## Not yet done

- `Docs/how-to-use.md` still describes starter habits, a target and personal
  max, and Reading as an example skill.
- `Docs/app-store-listing.md`: fill in the beta dates and tester count in the
  review notes (question 4).
