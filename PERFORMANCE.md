# Drawer performance deep dive

A forensic, line-referenced accounting of where CPU and battery actually go.

## Status (2026-07-02)

This report describes the tree before the optimization pass. Fixed since:

- Tier 1A/1B/2A/2B: SwipeCoordinator, WorkClock, FocusTimer, CelebrationCenter
  migrated to `@Observable`; rows hold the store as a plain `let` and are
  `Equatable` + `.equatable()`, so ticks, swipes, toggles, and bursts no longer
  fan out to every row.
- Tier 2 list cost: the task list is a `LazyVStack`, bounding N to the viewport.
- Tier 3: green-noise band-pass coefficients precomputed in `NoiseGenerator.init`
  (no per-sample `sin` in green mode).
- Tier 6: `arranged` skips its sort when nothing is in progress; `TodoStore`
  caches its day formatter; collapsed Backlog/Archive headers count without
  grouping.

Still open, judged not worth the risk blind (see the closing advice): Tier 4
file amplification, Tier 5 log re-decode, the per-sample `kind` switch, and the
global defaults observer.

## Method and honest limits

No profiler was run. The sandbox has no Swift toolchain and the app uses
macOS-only frameworks, so it cannot build or run off your Mac, and Terminal and
Xcode are read-only to the tooling here, so Instruments could not be driven.

What this is instead: a static cost accounting cross-checked by three
independent passes over the whole of `Sources/Drawer` and `Sources/DrawerCore`
(re-render graph, ongoing CPU and wakeups, allocations and algorithmic cost).
The three agreed on every major point. Every claim below has a file:line anchor
so you can verify it directly. Magnitudes in absolute time still need
Instruments; the recipe is at the end.

## The honest headline

For a typical user (a small markdown file, a short visible list) the per-action
costs here are tiny in absolute terms, sub-millisecond to low-millisecond. The
app is event-driven and has no idle hot loop. So this is not a slow app.

The performance that actually matters lives in two categories:

- Work that repeats many times per second during an interaction or while a
  feature runs. These cause animation hitches and battery drain you can feel.
- Work that scales with list length or file size, which bites once the list is
  long (Archive expanded, big file) even though it is invisible when short.

Everything is ranked by that real-world lens, not by raw operation count.

## Root cause in one sentence

Child rows subscribe to whole `ObservableObject`s they barely read from, so a
single change in any of four objects re-evaluates every visible row, and two of
those objects fire many times per second.

---

## Tier 1: continuous re-render storms (the ones you can feel)

These re-run the SwiftUI body of many views repeatedly during normal use. This
is the highest-value target.

### 1A. A swipe re-renders every row and the whole DrawerView, on every drag frame

`SwipeCoordinator.offsets` is a single `@Published [String: CGFloat]`
(`SwipeToDelete.swift:14`). During a swipe, `drag(id:translationX:)`
(`SwipeToDelete.swift:33`) writes `offsets[id]` on every mouse `onChanged`
(`TaskRowView.swift:326`) and every trackpad scroll event
(`SwipeToDelete.swift:144`), dozens of writes per gesture. Each write publishes
the whole coordinator. Subscribers that re-evaluate on every one of those frames:

- Every `TaskRowView`, via `@EnvironmentObject swipe` (`TaskRowView.swift:20`),
  injected at `DrawerView.swift:273`. So O(N rows) body re-evaluations per drag
  frame, not just the row being dragged.
- `DrawerView` itself, via `@StateObject swipe` (`DrawerView.swift:41`), even
  though its body reads nothing from `swipe`. The entire header, controls, and
  scroll tree re-evaluate every drag frame.

This is the worst offender because it fires continuously during a gesture and
fans out to everything.

### 1B. Work Mode re-renders every row and DrawerView twice a second

`WorkClock.tick` publishes `elapsed` every 0.5s (`WorkClock.swift:262`, timer at
`:250`). `elapsed` is read only by `WorkModeHeaderView` (the live total). But the
publish hits:

- Every `TaskRowView`, via `@EnvironmentObject workClock`
  (`TaskRowView.swift:21`), injected at `DrawerView.swift:274`. Rows read
  `isOn`, `activeTaskID`, `phase`, never `elapsed`, so the tick is pure waste
  for them, yet all N rows re-evaluate 2x/s.
- `DrawerView`, via `@ObservedObject workClock` (`DrawerView.swift:7`), full body
  2x/s.

So while Work Mode runs: (N rows + DrawerView + header) body evaluations every
half second, of which only the header is necessary.

### 1C. Focus timer re-renders DrawerView twice a second

`FocusTimer.tick` publishes `remaining` every 0.5s (`FocusTimer.swift:77`, timer
at `:65`). `DrawerView` subscribes via `@ObservedObject timer`
(`DrawerView.swift:6`) but reads no timer property, so its whole body
re-evaluates 2x/s while a timer runs. Rows are not subscribed to FocusTimer (it
is not in the environment), so this one is DrawerView-only.
`TimerHeaderView` legitimately needs the tick.

### 1D. The hidden panel keeps doing 1B and 1C

`PanelController.hide` uses `orderOut(nil)` (`PanelController.swift:102`), which
hides but does not destroy the hosting view, and `DrawerView.onDisappear`
(`DrawerView.swift:290`) does not reliably fire on `orderOut`. Consequences:

- While a focus timer or Work Mode runs with the drawer closed, the header views
  still re-render 2x/s against a hidden window.
- `ScrollSwipeMonitor` (installed in `onAppear`, `DrawerView.swift:279`) likely
  stays installed for the app lifetime, so its `.scrollWheel` local monitor
  (`SwipeToDelete.swift:92`) runs its closure for every scroll event the app
  receives even when the drawer is hidden.

---

## Tier 2: the N-row over-subscription on discrete actions

Same root cause as Tier 1, but fired once per action rather than continuously,
so it matters mainly as the list grows.

### 2A. One task toggle re-evaluates every visible row

`store.toggle(item)` (`TaskRowView.swift:206`) runs `mutate` then `apply`, which
assigns seven `@Published` arrays back to back (`TodoStore.swift:227`-237).
SwiftUI coalesces those seven into one update per runloop, so the cost is not
7x. But every `TaskRowView` holds `@ObservedObject var store`
(`TaskRowView.swift:6`) and, with the legacy `ObservableObject` model, a
subscriber re-evaluates on any publish regardless of what its body reads. No row
body reads a published store property; rows render from their `let item`
(a value type passed by the parent). So a toggle costs N row body
re-evaluations, of which N-1 are pure waste.

### 2B. Confetti re-renders every row, on the burst and again on its removal

`CelebrationCenter.bursts` publishes on append in `fire` and on the delayed
`removeAll` (`ConfettiBurst.swift:27` and `:31`). Every `TaskRowView` subscribes
via `@EnvironmentObject celebration` (`TaskRowView.swift:19`) although rows only
call `celebration.fire` and never read `bursts`. So all N rows re-evaluate twice
per celebration. Because a completion fires a toggle (2A) and a burst (2B) at
once, checking a task off triggers two overlapping N-row passes.

---

## Tier 3: sustained audio CPU (the real battery item while in use)

`NoiseGenerator.render` synthesizes the focus sound sample by sample on the audio
thread (`FocusSound.swift:106`, `sample()` at `:63`). Active only while
`FocusSoundPlayer.isPlaying` (between `play()` `:187` and the ~0.25s teardown
after `stop()` `:218`); zero audio CPU otherwise. It runs independent of the
panel, by design, so it continues while the drawer is hidden.

Per-sample work runs at 44100 Hz x 2 channels = 88,200 sample() calls/second.
Default pink mode is roughly 42 floating-point ops per sample (xorshift ~9, the
Kellet 7-pole pink filter ~28, low-pass plus blend plus clamp ~5), so on the
order of 3.7 million ops/second, no transcendentals.

Two exact inefficiencies in that path:

- Green mode recomputes `let f = 2 * sin(Double.pi * 500 / sampleRate)` every
  sample (`FocusSound.swift:87`), a constant, adding 88,200 `sin` calls/second
  on top of the per-sample SVF.
- The `kind` switch is read per sample (`FocusSound.swift:73`-99), so the mode
  branch is taken 88,200 times/second instead of being chosen once when `kind`
  changes.

Green and ocean are the heaviest modes because each does a real `sin` per sample.

---

## Tier 4: per-edit file amplification

Every task edit does far more I/O and copying than the one byte it changes.
Honest magnitude: on a small file this is microseconds and invisible; it only
matters for a large file or rapid repeated edits. But it is exact and real.

Trace of one toggle (`TodoStore.mutate`, `TodoStore.swift:178`):

1. `readData` full disk read (`:180`).
2. `TodoWriteback.toggle` builds a per-line array and copies the whole file
   `Data` to flip one byte (below).
3. `writeData` full atomic disk write (`:183`).
4. `apply` decodes the whole file and runs `TodoParser.parse` plus
   `TodoParser.display` (`:184`).
5. The atomic write trips the `FileWatcher`, so `reload` (`:80`) does another
   full disk read and an O(file) byte compare for self-write suppression
   (`:97`-100). The parse is correctly skipped here, but the extra read and
   compare are not free.

Net per toggle: 2 disk reads, 1 write, 1 full parse, 1 full-file compare, and
about three full in-memory text copies.

The single-byte copy, `TodoWriteback.toggle` (`TodoWriteback.swift:62`-67):

```
var out = data        // copy-on-write, still shared
out[boxIndex] = ...   // single-byte write forces a full copy of the file
```

`delete` (`:168` `removeSubrange`), `setNote` (`:245` `replaceSubrange`), and
`append` (`:305` `insert`) are all the same shape: one full O(file) copy plus a
memmove regardless of edit size.

`markdownLines` (`TodoWriteback.swift:329`) decodes the entire file once just to
validate UTF-8 and throws it away (`:330`), then walks every byte and allocates a
`MarkdownLine` holding a `String` copy of each line (`:354`). Combined with the
decode in `apply`, a single edit decodes the file text three times: validation,
the per-line array, and apply.

## Tier 5: WorkSessionLog re-decodes the whole log per query

`all()` reads the file and JSON-decodes every line, building a fresh
`JSONDecoder` each call (`WorkSessionLog.swift:62`, decoder at `:42`). Every
`total`, `summary`, and `setTotal` calls `all()`. Counting calls per WorkClock
operation: `track`/`resume`/`restore`/`splitAtMidnight` each do one full log read
plus L decodes (via `log.total`), `end` one (via `summary`), and `editSummary`
up to three full reads plus a full O(L) rewrite (`WorkClock.swift:162`-174).
Good news: the 0.5s `tick` does not touch the log (the header total is cached),
and `closeSegment` appends one line in O(1) via a seek-to-end file handle. So
this only bites as the log grows large.

## Tier 6: small, easy, mostly off the hot path

- `DrawerView.arranged(_:)` (`DrawerView.swift:493`) always runs an
  `enumerated().sorted().map` to float in-progress tasks (`:508`-515) even when
  none are in progress and no sort is needed. It is called for Today, Carried,
  and Upcoming (`:211`, `:212`, `:226`), and `grouped` calls it once per Backlog
  and Archive subsection (`:313`); `collapsibleSection` even calls `grouped` just
  to show a count while collapsed (`:327`). Under a running timer this whole
  chain re-runs 2x/s. Tiny lists, so low absolute cost, but it is unconditional
  work in `body`.
- `TodoStore.localToday` (`:61`) and `dayAfter` (`:241`) build a fresh
  `DateFormatter` per call, about two constructions per `apply`. (`WorkClock`'s
  is already cached; `TodoParser` and `TodoArchiver` use cached static ones.)
- `FocusSoundPlayer` observes `UserDefaults.didChangeNotification` globally
  (`FocusSound.swift:167`) and runs `syncFromDefaults` on every defaults write
  anywhere. Dragging the focus-sound volume slider writes `focusSoundVolume`
  each frame, so the observer fires many times/second during that drag. The work
  is cheap (two reads), but it is an avoidable wakeup on every `@AppStorage`
  write app-wide.
- `TaskRowView` reads six `@AppStorage` keys (`TaskRowView.swift:12`-18), so
  applying a Settings preset (which writes every flag in a loop,
  `FeatureFlags.swift:126`-138) re-renders every row several times.
- `TodoArchiver.archiveCompleted` (`TodoStore.swift:105` on each reload) splits
  all lines itself (`TodoArchiver.swift:41`), duplicating the split that
  `TodoParser.parse` does moments later in `apply`.

---

## Per-action cost table

| Action | Disk reads | Writes | Full text decodes | Full parses | Full file copies | Row body re-evals |
|---|---|---|---|---|---|---|
| Toggle a task | 2 | 1 | 3 | 1 | 1 | N (N-1 wasted) + N more from confetti |
| Delete a task | 2 | 1 | 3 | 1 | 1 | N |
| Edit a note | 2 | 1 | 3+ | 1 | 1 | N |
| Add a task | 2 | 1 | 3 | 1 | 1 | N |
| Swipe a row (per frame) | 0 | 0 | 0 | 0 | 0 | N + DrawerView, every drag frame |
| Work Mode running (per 0.5s) | 0 | 0 | 0 | 0 | 0 | N + DrawerView + header |
| Focus timer running (per 0.5s) | 0 | 0 | 0 | 0 | 0 | DrawerView + header |
| Focus sound playing | 0 | 0 | 0 | 0 | 0 | none; ~3.7M audio ops/s |
| Work: editSummary | up to 3 | 1 | up to 3xL | 0 | 0 | summary card |

N = visible rows. L = sessions in the work log.

## The three structural fixes that remove most of it

1. Stop rows subscribing to whole objects they do not read. Either migrate the
   stores to the Observation framework (`@Observable`), which tracks per-property
   reads so a row that reads nothing from `store`/`swipe`/`workClock`/
   `celebration` stops re-rendering on their changes, or pass rows only their
   `item` plus closures instead of the objects. This collapses Tiers 1 and 2 at
   once. You are on macOS 26, so `@Observable` is fully available.
2. Make the list lazy. `ScrollView { VStack { ForEach } }` (`DrawerView.swift`
   around `:200`-249) builds every row up front; `LazyVStack` builds only the
   visible ones, which bounds N to what is on screen.
3. Do not re-read and re-copy the whole file per edit. After a successful write
   you already hold the new text; apply that in memory and keep the suppression,
   rather than the read-write-watcher-read-compare loop. Cache parsed sessions in
   `WorkSessionLog` rather than decoding the whole log per query.

After 1 and 2, the per-row amplifiers (a swipe, a tick, a toggle, a burst) stop
being O(N) and the timers stop re-rendering the hidden panel.

## How to turn this into real numbers on your Mac

1. Instruments, SwiftUI template: watch "View Body" counts while you swipe a row,
   run Work Mode, and toggle tasks with Archive expanded. Confirm the N-row
   re-eval fan-out.
2. Drop `let _ = Self._printChanges()` at the top of `TaskRowView.body` and
   `DrawerView.body`; the console prints what triggered each re-evaluation.
3. Time Profiler while scrolling a long Archive and toggling, to see
   `TodoParser.parse` and `TodoWriteback` cost on your real file size.
4. Time Profiler with a focus sound playing, filtered to the audio thread, to
   measure `NoiseGenerator.render`. Compare pink against green and ocean.
5. Animation Hitches during the panel slide and during a swipe with a long list.
6. Energy log to see the cost of the 2x/s ticks while the drawer is hidden.

Measure before and after each change; some of these are invisible on a small
file and should not be optimized blind.

## What is already good

No force unwraps, no idle polling, the file watcher is event-driven and
debounced, the timers use absolute end dates so they survive sleep, confetti is
time-driven rather than restarting on republish, `closeSegment` appends in O(1),
the live Work Mode total is cached rather than re-read per tick, and the parser
and archiver use cached date formatters. The structure is sound. These are
targeted tunings, not a rewrite.
