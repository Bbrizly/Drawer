# One editable timer, breaks optional

Date: 2026-07-10
Status: design, approved to plan

## The idea

Today the header shows two timer pills at once: a plain countdown and a
Pomodoro. They are not really two things. A Pomodoro focus segment is a
countdown. The only thing Pomodoro adds is that when it hits zero it rolls
into a break and keeps cycling.

So collapse them. There is one timer in the header. It is always editable.
A single toggle decides whether it auto-cycles into breaks (Pomodoro) or just
ends (plain countdown). Flipping the toggle mid-run is seamless, because it is
the same clock underneath. No mode to commit to, no separate stopwatch, and
one pill instead of two.

This is a net simplification: two engines and two pills become one engine and
one pill.

## Current state (verified)

- `DrawerView.timerPills` renders every enabled pill together. Both
  `feature.focusTimer` and `feature.pomodoro` default to true, so the default
  header shows two pills. `ViewThatFits` only picks horizontal vs vertical
  arrangement, not which timer.
- Two engines in `DrawerCore`: `FocusTimer` (124 lines, 7 tests) and
  `PomodoroTimer` (232 lines, 6 tests). `PomodoroTimer.format` delegates to
  `FocusTimer.format`.
- `FocusTimer.taskTitle` is vestigial. The only caller passes `"Focus"`
  (`TimerHeaderView`). Minute badges on tasks do not start a timer.
- `AppDelegate` wires the two engines separately: `timerFinished` and
  `pomodoroFinished` completion handlers, two `setDisplayActive` calls, and
  `startAlarm` watches both `.phase == .finished`.
- Two keys hold a focus length: `defaultMinutesText` (a String, "25") for the
  plain timer and `pomodoro.focusMinutes` (an Int) for Pomodoro.
- `PomodoroTimer.progress(settings:)` recomputes the segment total from live
  settings on every call. This is the bug that edit-while-running must fix.

## What the user sees

One pill in the header. Layout by state:

```
Idle
  ◔ FOCUS   25:00  ⟳ breaks   ▶
            tap 25:00 to edit

Running
  ◔ FOCUS   23:41  ⟳ breaks   ⏸  ✕
     −5  +5     ●●○○

Finished
  ⌣ FOCUS DONE   Next: Short break   →  ✕
```

- `⟳ breaks` is the auto-cycle toggle. On means Pomodoro, off means a plain
  countdown. It lives on the pill and flips live.
- The ring (segment marker) and the cycle dots only show when breaks are on.
  In countdown mode the pill is just a labelled clock.
- Tap the big time when idle to type a new duration. This is the same inline
  edit the plain timer has today.
- `−5` and `+5` adjust the current run while it is running, without touching
  the saved default. This covers the common "give me five more minutes".
- The ring still opens the segment chooser (focus, short, long) when breaks
  are on. The chooser gains steppers for the four saved values, so the saved
  presets are editable from the header, not just from Settings.

## Engine

Keep `PomodoroTimer` as the single engine. Delete `FocusTimer`.

Additions to `PomodoroTimer`:

- `autoCycle: Bool`. When false, a focus segment that reaches zero goes to
  `.finished` and does not propose a next segment. `nextSegment` and the ring
  chooser are unused in this mode. When true, behaviour is unchanged from
  today.
- `activeTotal: TimeInterval`, snapshotted when a segment starts. `progress()`
  reads this snapshot, not live settings. This fixes the jump bug: editing a
  saved value mid-run no longer contradicts the running clock.
- `adjust(byMinutes: Int)`: add or remove minutes from the current run.
  Re-anchors `endDate = now() + newRemaining`. Clamps `remaining` to
  `[0, cap]`. Below zero finishes the segment.
- `setDuration(minutes:)` while running: re-anchor to the new total.
  `newRemaining = newTotal − elapsed`, where `elapsed = activeTotal − remaining`.
  If `newRemaining <= 0` the segment finishes now. Updates `activeTotal`.
- Move `format` into `PomodoroTimer` (inline the three lines) and drop the
  delegation to the deleted `FocusTimer`.

Every edit to a saved value routes through `Settings.sanitized`, so the
existing clamp ranges hold (focus 5 to 90, short 1 to 30, long 5 to 60, cadence
2 to 8). The running-clock cap is separate and wider: `−/+` on a live run
clamps `remaining` to `[0, 480 minutes]`, matching the plain timer's old
ceiling, so a running session can be stretched past the 90 minute preset range
but never absurdly high.

The engine keeps its injectable `now` clock, which the tests use.

## Editing while running: exact semantics

- `−/+ quick adjust`: changes `remaining` directly, clamped to `[0, cap]`.
  Take it below zero and the segment finishes.
- Edit the duration field: re-anchor. `newRemaining = newTotal − elapsed`,
  elapsed preserved so the ring stays honest. Shorten below elapsed and it
  finishes now.
- Edit a saved segment value while that segment runs: apply the delta to the
  running segment too, so the visible timer never contradicts the number you
  just set.
- Flip breaks off mid-cycle: the current segment finishes normally, then stops
  instead of proposing a break. Flip back on and cycling resumes from the
  current count.

## Settings and migration

- Retire the `pomodoro` feature flag and its Settings on/off toggle. The header
  `⟳ breaks` toggle replaces it.
- Keep `feature.focusTimer` as the master on/off for the whole timer widget.
- The four duration steppers and the presets stay on the Settings Timers tab.
  They now also read and write from the header chooser, same keys, so the two
  stay in sync.
- Standardize the focus length on `pomodoro.focusMinutes` (Int). Retire
  `defaultMinutesText`.

One-time migration on first launch after the update:

- Set `timer.autoCycle` from the old `feature.pomodoro` value. A user who had
  Pomodoro off keeps a plain countdown. A user who had it on keeps cycling.
- If `defaultMinutesText` was changed from "25", carry that number into
  `pomodoro.focusMinutes` before dropping the key.
- New users default `timer.autoCycle` to true, matching today's out-of-box
  Pomodoro.

## What gets deleted

- `Sources/DrawerCore/FocusTimer.swift`
- `Sources/Drawer/TimerHeaderView.swift`
- `Tests/DrawerCoreTests/FocusTimerTests.swift`
- The `pomodoro` case in `FeatureFlag` and its Settings toggle.
- The second timer object and its wiring in `AppDelegate` and `DrawerView`.

## What changes

- `AppDelegate`: one timer object, one completion handler, one
  `setDisplayActive`, `startAlarm` watches one phase.
- `DrawerView`: `timerPills` shows one pill; holds one timer.
- `PomodoroHeaderView`: becomes the unified widget (breaks toggle, inline edit
  when idle, quick adjust when running, stepper chooser).
- `DrawerVisualRenderTests`: retarget the three `FocusTimer` uses to the merged
  engine.

## Testing

Extend `PomodoroTimerTests` (best practice: cover the new non-trivial logic):

- `adjust(byMinutes:)` adds and removes time, clamps at zero, finishes when
  driven below zero.
- `setDuration` while running re-anchors correctly and finishes when shortened
  below elapsed.
- Editing a running segment's saved value moves the running clock by the delta.
- `autoCycle == false`: a focus segment that reaches zero finishes and proposes
  no next segment.
- `activeTotal` snapshot: `progress` is stable when settings change mid-run.

Keep the existing cadence and clamp tests. `PomodoroPreferencesTests` is
unaffected.

## Out of scope

- No count-up stopwatch. The editable countdown covers it. Cost to add later is
  near zero (a countdown with no target), noted for the record.
- Work mode (the task-logging stopwatch) is untouched. It stays its own pill,
  off by default.
