# The Bureau: feature spec v2

2026-07-10. Supersedes v1 (same file). Source: Bassam's full vision dump, this date.
Status: R0 done, all decisions resolved (see Decisions). Next: Spike S1. Implementation spec: Docs/bureau-impl.md.
Vault capture: `1 Projects/Drawer.md` backlog. Copy deck + issues list also in vault.

## One paragraph

The drawer panel splits in two: the top strip (buttons, notes, pomodoro, work timer, add task) never changes. The bottom region flips between the normal task list and the Bureau: a 3D-looking, Papers-Please-textured drawer full of printed receipt-notes with physics. You select the tasks you intend to finish this week, enter Bureau mode with a slick horizontal push transition, rummage, pull a receipt out into a manipulable sticky note, and finish tasks under a weighty two-stamp mechanism: DONE files it, POSTPONED sends it back. Adding a task while in Bureau mode prints a receipt from the seam between the two regions, line by line, ding, drop, physics. Every animation value is tunable.

## Layout and mode switch

- Top strip: existing controls, byte-identical in both modes. Idea-board swipe unchanged.
- Bottom region has two implementations behind `feature.bureau`: the existing inline list region in DrawerView.body (untouched) and BureauView; the swap is a conditional branch in DrawerView, not a named-view swap.
- Transition: current list pulls LEFT off-panel while the drawer slides in moving RIGHT, reading as a physical object with depth (parallax between drawer front lip, receipts, and drawer floor gives the 3D). Same footprint as the panel, no resize. Duration/easing tunable. Reduce Motion: crossfade.
- Trigger: a mode button in the top strip (drawer-pull icon). Auto-switch after printing from selection (below).

## Selecting what enters the Bureau

Principle: the Bureau holds only what you CHOSE to work on (the week's set), not the whole backlog. Everything else stays in list mode.

- In list mode, each task gets a "queue for Bureau" affordance (right-click menu, see Decisions).
- Queued tasks show a small slip icon. A counter chip appears near the mode button.
- Pressing the mode button prints all newly queued tasks (sequential receipts, ~250ms stagger) and flips to Bureau.
- Un-queueing a task in list mode pulps its receipt (quick crumple) next time the Bureau is visible.

## The drawer scene (Bureau mode)

- Papers, Please aesthetic: gritty paper textures, muted palette, one red accent, chunky pixel-art rendering (nearest-neighbor scaling, low-res texture grid), but composed cleanly so it sits beside the existing top strip without clashing. No copied assets, fonts OFL, sounds CC0/self-made.
- Receipts: cream slips, baked jagged tears, the task title in BIG readable type (legibility beats flavor at drawer scale; dot-matrix flavor lives in the details).
- Physics: SpriteKit. Bodies sleep when settled; scene pauses when hidden. Mouse proximity (no click) nudges receipts: radial repulsion + slight torque, velocity-scaled paper rustle, rate-capped.
- FILED tray: a visible compartment at the bottom edge of the drawer. DONE receipts fly here and stack flat with their stamp showing. It is the day's trophy shelf (clears Mondays with ceremony, see Decisions).

## Pull-out: receipt to sticky note

- Left-drag a receipt past the drawer edge: it hands off into a floating sticky note (non-activating NSPanel), one smooth continuous motion. This is Spike S1, the riskiest interaction; fallback design is a pull-out tray zone.
- Sticky note abilities:
  - Edit the text in place (writes back through TodoStore's real mechanism (TodoWriteback line-locate + content-CAS commit, which already suppresses watcher loops)).
  - Expand/collapse to reveal subtasks; add subtasks inside the sticky. Reality: TodoItem carries one free-text note, so sticky subtasks are rendered lines of that string, edited via setNote, not a modeled array.
  - Reorder/promote subtasks within the sticky.
  - Sizes: full / title-only / chip (double-click cycles).
- NEW, signature interaction, hover-scroll move: while the cursor hovers a sticky, a two-finger trackpad scroll MOVES the note (window position follows scroll deltas with slight inertia), no click-drag needed. Guard rule per Decisions: scroll always moves the note.
- Cap 12 live stickies; #13 sends the oldest home.

## The stamp

- Appearance rule (subtlety is the point): the stamp summon button fades in ONLY when a sticky sits in the right-edge zone AND the cursor is also on the right side. Otherwise the mechanism does not exist.
- Press it: the stamp arm extends with a curved overshoot: sweeps in from the right, passes its rest point, eases back right, settles with a small left-right shiver. Weight and earthiness, all four keyframe values tunable.
- Two stamps: green **DONE**, red **POSTPONED**.
  - DONE: slam (12-frame), ink lands 2-4 degrees rotated with double-strike ghost, thunk + optional haptic, task checked in Drawer.md, receipt crumples and flies into the FILED tray.
  - POSTPONED: red stamp, receipt slides back into the pile, task untouched in Drawer.md. (Exact postpone semantics deferred by design, v1 = pure return.)
- Stamping happens only via stickies. One ritual, one code path.

## The printer

- The seam between top strip and bottom region IS the printer slot.
- Adding a task (existing add-task control) while in Bureau mode: on Enter, a receipt emerges from the seam line by line, stepped and incremental like a thermal printer (not smooth-scrolled), soft dot-matrix chatter, terminal ding, then it tears off and drops into the drawer with physics.
- Print emergence speed, step size, chatter volume, ding: all tunable.
- In list mode, add-task behaves exactly as today (no print).

## Tuning system (first-class requirement)

- Every feel value lives in `Application Support/Drawer/bureau-tuning.json`, hot-reloaded: transition duration/easing, physics (repulsion radius/strength, torque, friction, restitution), rustle gain/cap, print step ms, stamp arm keyframes, ink rotation range, crumple frames, hover-scroll sensitivity/inertia.
- Hidden tuning panel (debug flag or long-press on the mode button): sliders bound live to the json. This is a game-dev tuning workflow; the GIF gets made only after the values feel right.

## Architecture (unchanged from v1)

`DrawerBureau` SPM target behind `feature.bureau`; deleting the module leaves the app as today. Drawer.md remains the single source of truth; receipts are views (ReceiptLink = UUID + text snapshot, fuzzy re-link, orphan = faded EXPIRED slip). ReceiptStore JSON for positions/states/lifetime M.O.P. counter. TextureRenderer at backingScaleFactor, re-render on edit only. Writeback via TodoWriteback + TodoStore.commit content-CAS, no watcher loops. Perf contract: 0.0% idle CPU settled, 60fps rummage at 100 receipts, gate in PERFORMANCE.md.

## Spikes, then milestones

- S1 drag handoff (receipt leaves SKView mid-drag, becomes NSPanel under held cursor, seamless). Throwaway app. Exit: feels like magic, or adopt tray fallback.
- S2 field wake (does SKFieldNode wake resting bodies; else manual force loop). 1 hour.
- R1 drawer scene + selection + print flow + transition. R2 pull-out stickies + hover-scroll move. R3 sticky editing/subtasks + writeback. R4 stamp mechanism + FILED tray + sounds. R5 aging paper, polish backlog, GIF.
- Each R: tests green, make app && make install, commit, push, dated line in vault dashboard.

## Decisions (resolved 2026-07-10 with Bassam)

1. **Queue gesture: right-click menu "Queue for Bureau"** (primary). A hover slip-corner icon (small receipt icon appearing on task hover) may be added later as a secondary affordance; cheap, deferred.
2. **Hover-scroll: always moves the note.** Subtask lists inside stickies never scroll; visible subtasks capped (~6, tunable), overflow shown as "+N more" which expands the note taller instead of scrolling.
3. **Drawer scope: Bureau holds only queued/printed tasks.** Backlog stays list-only. Confirmed by default.
4. **FILED tray: clears every Monday with a filing ceremony animation.** Lifetime DONE count stays engraved on the tray.
5. **Aesthetic reach: the ENTIRE APP gets a Papers-Please treatment, delivered as a NEW THEME (the 9th: repo already has liquidGlass, reminders, widget, medieval, pixel, dots, notebook, windowsXP)** in the existing theme system (working name "Bureau" theme: gritty paper, muted palette + red accent, pixel type, chunky chrome). The Bureau drawer scene is always Papers-Please-styled regardless of active theme; activating the Bureau theme extends the look app-wide (top strip, list mode, settings). This rides the proven theme-token system (Pixel theme already bundles fonts), so it is an art pass, not an architecture change. Ship order: Bureau scene art first (R1), app-wide theme as R5+ so it never blocks the feature.
