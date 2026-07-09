# Settings restructure design

**Date:** 2026-07-09
**Status:** Approved, ready for implementation

## Problem

The Settings window has 5 tabs (General, Features, Board, Advanced, Help) with
weak information architecture:

- **General is a junk drawer** — shortcut, tasks file, panel size, theme, font,
  task size, and all three timer cards are crammed together.
- **Duplicate timer toggles** — the same `feature.focusTimer` / `feature.pomodoro`
  / `feature.workMode` UserDefaults keys are toggled in *both* General's "Timers"
  section and the Features flag list.
- **Misplaced controls** — "open at full height" sits away from panel behavior;
  list-default toggles (hide completed, expand backlog/archive) are detached from
  the flags they relate to.
- The recently-removed dead "sticky note colours" picker is already gone.

## Approved shape: 7 tabs, window widened 440 → 540pt

Codex consult corrected two earlier moves: keep a dedicated Board tab (gesture
sliders don't belong in the Features toggle list), and do not invent a
"Time & Sound" tab (check-off sound is task feedback, not time).

| Tab | Contents |
|-----|----------|
| **General** | Global shortcut (+ right ⌘), tasks file, panel size + slide, **open at full height** (moved here), launch at login |
| **Appearance** | Theme, app font, task text size |
| **Timers** | The 3 timer cards (single home), focus default, Pomodoro cadence, **timer-end + focus sound** |
| **Features** | Pure flags + Minimal/Everything presets; list defaults sit next to their related flags (hide-completed / unchecked-first by the Filter group; expand-backlog / archive by the Section toggles); **check-off sound** in the Feedback group |
| **Board** | Background + swipe-to-open + zoom (self-contained) |
| **Advanced** | Data paths, teleprompter, notes-pad height, reset |
| **Help** | Unchanged |

Window widens from `440` to `540` to carry 7 tabs (~77pt/tab vs ~65pt cramped
at 6). One-line frame change.

## Preset safety

`applyMinimal()` / `applyEverything()` iterate all `FeatureFlag.allCases`,
including the timer flags that now live on the **Timers** tab rather than in the
Features list. Pressing a preset in Features flips timers on another tab.

Fix: keep the preset behaviour (timer flags stay in the enum and presets still
affect them — the Timers cards reflect changes live via `@AppStorage`), and add
a one-line caption under the presets noting they also toggle timers. No silent
off-screen change.

## Non-goals

- No sidebar navigation (user chose to keep the horizontal tab bar).
- No new features. Pure reorganization + one window-width change + one caption.
- No renaming of flags (e.g. "Work mode" → "Stopwatch") in this pass.

## Files touched

- `Sources/Drawer/SettingsView.swift` — the tab bar, new `AppearanceSettingsView`
  and `TimersSettingsView`, slimmed `GeneralSettingsView`, regrouped
  `FeatureSettingsView`, window frame width.
- No model changes; all bindings are existing `@AppStorage` keys.
