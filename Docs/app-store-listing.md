# Mythos Log: App Store Connect Copy

Everything to paste into App Store Connect for the resubmission, plus the
TestFlight and Reddit text for the beta. Character limits are noted per field.

---

## 1. App Information

**Name** (30): `Mythos Log`

**Subtitle** (30), pick one:
- `A character for every habit` (27)
- `Habits that level up your hero` (30)
- `Train real skills. Earn forms.` (30)

**Primary category:** Health & Fitness
**Secondary category:** Lifestyle (or Productivity)

---

## 2. Version 1.0: iPhone and iPad

### Promotional Text (170)

> Seven skills. Ten character forms each. Beat your weekly baseline to unlock the next one, and watch it slip away if you stop. Progress you can actually see.

### Description (4000)

> Mythos Log turns the real things you do each week into a character that changes as you do.
>
> Every skill has its own figure. Strength, Cardio, Focus, Intellect, Creativity, Emotional and Cooking each have ten forms, from Untrained to Master. Each form is its own illustration, and the ones you haven't reached yet stay as dark silhouettes until you've earned them.
>
> HOW IT WORKS
>
> • Set a baseline. Tell Mythos Log what a normal week looks like for each skill: three gym sessions, sixty minutes of deep work, two home-cooked meals.
> • Log what you actually do. Tap to log, use Shortcuts, or let Apple Health bring in your workouts automatically.
> • Beat your baseline to earn Charge. Every unit above your baseline is banked.
> • Rank up at the weekly review. Meet your baseline with four Charge stored and the skill ranks up. Your character takes its next form, and your baseline rises with it.
>
> THE CATCH
>
> Ranks aren't permanent. Fall short week after week and a skill stagnates, then decays, and can drop back a rank. Mythos Log tracks the habits you keep, not the ones you started once.
>
> WEEKLY REVIEW
>
> Each week ends with a reckoning. See which skills are on pace, which are at risk, and what last week did to each one. When a skill ranks up, you reveal its new form.
>
> ALSO INCLUDED
>
> • Apple Health workout import, matched to the right habit
> • Goals for longer targets, which can optionally feed your Charge
> • Home Screen and Lock Screen widgets
> • Siri and Shortcuts actions for logging without opening the app
> • iCloud sync across iPhone and iPad
> • Adjustable progression: strictness, regression and decay are yours to tune
> • Your data stays on your devices and in your own iCloud. No accounts, no ads, no tracking.

### Keywords (100)

```
habit,rpg,level up,gamify,self improvement,weekly review,discipline,character,routine,tracker
```

Don't repeat words already in the name or subtitle; Apple indexes those separately.

### Screenshots: iPhone 6.9" (1320 × 2868)

From `Screenshots/iPhone 6.9in v2/`, in this order. The first three appear in
search results, so they carry the pitch.

| # | File | Suggested caption, if you add text overlays |
|---|------|------------------------------------|
| 1 | `01-dashboard.png` | Every habit becomes a character |
| 2 | `02-roster-strength.png` | Ten forms per skill. Earn each one. |
| 3 | `03-rank-ladder.png` | From Untrained to Master |
| 4 | `04-rank-increased.png` | Rank up and reveal your next form |
| 5 | `05-rank-up-pending.png` | Beat your baseline. Bank Charge. Rank up. |
| 6 | `06-roster-focus.png` | Focus, Intellect, Creativity and more |
| 7 | `07-weekly-review.png` | A weekly reckoning, not a daily streak |
| 8 | `08-skill-strength.png` | Log in a tap or sync from Apple Health |
| 9 | `09-goals.png` | Longer goals alongside weekly training |

### Screenshots: iPad 13" (2064 × 2752)

The existing set in `Screenshots/iPad 13in/` is valid. Ideally recapture it in
the same order so iPad reviewers also see the roster first.

### Support URL / Marketing URL / Privacy Policy URL

Unchanged from the current listing.

---

## 3. App Review Information: Notes

Paste this into **Notes** on the version page when you submit the new build.
Fill in the bracketed parts, and keep every statement true.

> Hello,
>
> Thank you for the review of our previous submission (ID b6d170c4-c31e-4112-af42-8c6141c1eec9). Since then we have run a TestFlight beta and made changes based on tester feedback, listed under question 4. Our answers to your questions are below.
>
> **1. What the app does.** Mythos Log is a weekly progression system for real-world habits. The user sets a weekly baseline for each skill (for example, three strength sessions). Activity above the baseline earns Charge. At the weekly review, a skill that met its baseline with four Charge stored ranks up: its baseline rises by one and its character advances to the next of ten illustrated forms. Repeated shortfalls cause stagnation, decay and possible rank loss. The problem it solves is that most habit trackers reward streaks, which break on one missed day and never ask for more. Mythos Log rewards sustained weekly effort, raises the bar as the user improves, and shows that progress as a character that visibly changes.
>
> **2. Intended user.** Adults who want to build several habits at once (training, focus, learning, creative practice, cooking) and are motivated by visible progression of the kind found in role-playing games, but who find daily-streak apps either too punishing or too easy to game.
>
> **3. Gap addressed.** Gamified habit apps generally use XP points, avatars with cosmetic items, or streak counters. None that we found combine (a) an adaptive weekly baseline that rises with each rank and falls with sustained underperformance, (b) Charge carried between weeks, so one strong week doesn't instantly level a skill, and (c) seventy character forms, ten per skill, made specifically for this app, that serve as the progression itself rather than decoration.
>
> **4. Beta testing.** We ran an external TestFlight beta from [date] to [date] with [N] testers recruited through [subreddit / personal network]. Feedback applied to this build:
> - [Feedback] → [change made]
> - [Feedback] → [change made]
> - [Feedback] → [change made]
>
> **5. Standalone or suite.** Mythos Log is a standalone product. [It is the only app on this developer account. / Other apps on this account are: ___; they share no functionality with Mythos Log.]
>
> **6. Could it be an in-app purchase in another app?** No. [There is no other app on this account. / None of the other apps on this account are habit or progression apps.]
>
> **7. Shared code with our other apps.** None. [Or: no other apps on this account.] The codebase was written specifically for Mythos Log in Swift and SwiftUI, using only Apple frameworks (SwiftData, CloudKit, HealthKit, WidgetKit, App Intents).
>
> **8. Shared code with third-party apps.** None. The app uses no third-party SDKs, templates or app builders.
>
> **9. Built for a client?** No. Mythos Log is my own product. I designed and developed the app and created the concept and progression system. The character artwork was generated with AI image tools to my direction, then selected, edited and processed for the app (background removal, consistent framing, and locked silhouette versions of each form).
>
> **Testing tip:** Ranks change at the end of a week, so to see a rank-up straight away, log a skill above its baseline and then open Review. Settings → Progression lets you adjust the progression rules.

**Sign-in required:** No.

---

## 4. TestFlight

### Beta App Description (external testing)

> Mythos Log turns your habits into seven characters, one per skill, that change form as you improve. Set a weekly baseline, log what you do, and rank up at the weekly review. Each skill has ten illustrated forms to unlock.

### What to Test

> Thanks for testing! Please use the app for at least one full week, since ranks resolve at the end of the week.
>
> 1. Setup: was it clear how to pick a baseline?
> 2. Logging: anything slow or confusing?
> 3. After your first weekly review, did the result make sense? Did it feel fair?
> 4. Would you keep using it? What would make you stop?
>
> Send feedback with a screenshot (take one in the app, then tap Share Beta Feedback) or reply on the Reddit thread.

### Feedback Email

Your own address.

---

## 5. Reddit Post (r/TestFlight, r/AppHype, optionally r/getdisciplined)

Check each subreddit's rules first. Some only allow beta links on set days or
require a flair.

**Title:** `[TestFlight] Mythos Log: a habit tracker where each skill is a character with 10 forms to unlock`

> I've been building a habit app for the past six months and I'm looking for a handful of testers before launch.
>
> The idea: each skill (Strength, Focus, Cooking, etc.) has a weekly baseline. Going over it earns Charge, and at the end of the week a skill with enough Charge ranks up. The character for that skill takes its next form, and the baseline goes up. Slack off for a few weeks and it slips back down.
>
> What I need: use it for about a week and tell me what was confusing or annoying, especially around the first weekly review.
>
> iPhone and iPad, iOS [minimum version]+. No account, no ads. Data stays on your device and in iCloud.
>
> TestFlight link: [public link]
>
> Screenshots: [imgur album of the v2 screenshots]
>
> Happy to answer anything about how it's built.

---
