# The Bureau: implementation spec

2026-07-12. The HOW for the feature designed in `bureau-spec.md`. That file owns
every WHAT and every resolved decision. This file does not repeat them. It names
real types, real files, and the build order.

Grounding done against the live tree, not memory. Where the design spec assumed
something the code does not have, it is flagged in the closing review-items list.

## 1. Integration map

New SPM target `DrawerBureau`, gated by `@AppStorage("feature.bureau")` and
guarded at every Drawer call site with `#if canImport(DrawerBureau)`. That guard
is the deletion contract: drop the target and its dependency line from
`Package.swift` and every branch compiles out, leaving today's app.

Touched (small, reversible edits, all behind the guard):

- `Package.swift`. Add the `DrawerBureau` target; add it to `Drawer`'s
  dependencies. DrawerBureau depends on `DrawerCore` only.
- `Sources/Drawer/DrawerView.swift`. The bottom region is built inline in
  `body` (there is no standalone list view, see review items). Add one
  conditional branch: when `feature.bureau` is on and a sticky/queue exists,
  render `BureauView` instead of the task list. Add the mode button and the
  queue-counter chip to the top strip via the existing header layout.
- `Sources/Drawer/TaskRowView.swift`. Add a "Queue for Bureau" `contextMenu`
  item (Decision 1). Calls into the DrawerBureau facade.
- `Sources/Drawer/FeatureFlags.swift`. Add `case bureau`, `defaultValue false`,
  kept out of `groupsInOrder` so it renders no dead toggle until surfaced. The
  raw `feature.bureau` key works even if the target is absent.

Strictly untouched (Bureau reads their public API only, writes back through
`TodoStore`): `TodoStore`, `TodoWriteback`, `TodoItem`, `FileWatcher`,
`TitleSimilarity`, `DrawerTheme` / `Palette` / `PanelBackground`, `FontLoader`,
`FocusTimer`, `WorkClock`, `PomodoroTimer`, all header views
(`TimerHeaderView`, `PomodoroHeaderView`, work-mode header), `PanelController`,
`TeleprompterController`.

Writeback rule: Bureau never touches `Drawer.md` bytes. It calls
`TodoStore.toggle(_:)`, `.setNote(_:_:)`, `.rename(_:to:)`, `.add(_:)`. Those
route through `TodoStore.commit` (the content-CAS with `lastWrittenData`
suppression), so no watcher loop and no clobbering an external Obsidian save.

## 2. New target layout

`Sources/DrawerBureau/`

- `BureauFeature.swift` (~50). The one facade Drawer imports: a factory that
  returns the SwiftUI `BureauView`, the queue action, and the queued count.
  Everything else stays internal so the guard surface is one type.
- `BureauView.swift` (~120). SwiftUI host. Wraps `SpriteView(scene:)`, overlays
  `PrinterSlot` and the stamp summon button, reads the active `DrawerTheme` and
  `BureauTuning`. Owns the push-left mode transition alongside DrawerView.
- `BureauScene.swift` (~260). The `SKScene`. Spawns receipts, runs the physics
  world, the rummage `SKFieldNode`, the FILED tray node. Pauses on hide, sleeps
  bodies when settled.
- `ReceiptSprite.swift` (~90). `SKSpriteNode` subclass holding a `ReceiptLink`
  id and its cached texture. No text drawing here; it displays a texture.
- `TextureRenderer.swift` (~140). Task title to `NSImage` at
  `backingScaleFactor`, nearest-neighbor, cached by (text, size, scale).
  Re-render only on edit. Mirrors the spike-board `contentsScale` discipline.
- `ReceiptStore.swift` (~120). `Codable` JSON in `AppPaths.drawerDataDirectory`.
  Links, positions, sticky states, lifetime FILED counter. Atomic write.
- `ReceiptLink.swift` (~110). Identity: `UUID` + `textSnapshot` +
  `sectionDate`/`occurrence`. Re-link to a live `TodoItem` via
  `TitleSimilarity.score`; no match above threshold means orphan = EXPIRED slip.
- `StickyPanelManager.swift` (~120). Owns the live stickies, caps at 12
  (tunable), retires the oldest on #13.
- `StickyPanel.swift` (~140). Non-activating `NSPanel`, built on the
  `TeleprompterController` recipe (borderless, `.nonactivatingPanel`,
  `isFloatingPanel`, `level` floating+1, clear background, `hasShadow`,
  `hidesOnDeactivate = false`).
- `StickyView.swift` (~180). SwiftUI content: in-place edit, expand/collapse
  subtasks, size cycle (full / title / chip).
- `HoverScrollMover.swift` (~120). Local `NSEvent` `.scrollWheel` monitor with
  phase and inertia. Scroll always moves the note (Decision 2); subtask lists
  never scroll.
- `StampArm.swift` (~160). Right-edge overlay window, DONE / POSTPONED, appears
  only when a sticky sits in the right zone AND the cursor is in the right zone.
- `PrinterSlot.swift` (~130). Stepped line-by-line emergence from the seam
  between header and bottom region.
- `BureauTuning.swift` (~180). `Codable` load of every feel value, hot-reloaded
  via a `FileWatcher` on the tuning json, plus the hidden slider panel.
- `BureauCopy.swift` (~40). All user-facing strings.

## 3. Key flows

(a) Queue then enter. Right-click a row, "Queue for Bureau"
(`TaskRowView.contextMenu`) calls `BureauFeature.queue(item)`, which writes a
`ReceiptLink` in state `queued` to `ReceiptStore` and bumps the counter chip.
Press the mode button: `BureauView` mounts, DrawerView animates the task list
LEFT off-panel while the drawer slides in from the RIGHT (same footprint, no
resize), duration and easing from `BureauTuning.transition`. Reduce Motion
crossfades. Each queued link prints in sequence (flow b), 250ms stagger.

(b) Print-on-add in Bureau mode. Enter in the existing add field calls
`TodoStore.add(_:)` (unchanged). Bureau observes the new `todayItems` publish,
finds the added item, and runs `PrinterSlot`: a receipt steps out of the seam
`stepPx` at a time every `stepMs`, dot-matrix chatter, ding, tear, then a
`ReceiptSprite` drops into `BureauScene` with a downward impulse. List mode adds
behave exactly as today (no `BureauView` mounted, nothing observes).

(c) Drag receipt into a sticky (S1 handoff). `mouseDown` on a `ReceiptSprite`,
`mouseDragged` moves it in-scene. When its center crosses the SKView bounds, a
local `NSEvent` monitor (`.leftMouseDragged`, `.leftMouseUp`) takes over, the
sprite despawns, and a `StickyPanel` spawns under the cursor at the same visual,
following the cursor to `mouseUp`. One continuous motion. Fallback if the spike
fails: a pull-out tray zone at the drawer edge; releasing a drag there spawns
the sticky centered, no mid-drag handoff.

(d) Stamp DONE. Summon button (gated per StampArm rule) fires the arm: sweep in
from right, overshoot, ease back, settle with a small shiver (four keyframes,
all tunable). On contact: 12-frame slam, ink lands `inkRotationMin..max` degrees
rotated with a double-strike ghost, thunk plus optional haptic, then
`TodoStore.toggle(item)` checks the task in `Drawer.md`, the receipt crumples and
flies into the FILED tray, `ReceiptStore.lifetimeFiled += 1`. POSTPONED: red
stamp, receipt slides back into the pile, task untouched.

(e) Sticky edit writeback. Editing a sticky's title calls
`TodoStore.rename(_:to:)`; editing subtasks calls `TodoStore.setNote(_:_:)`
(subtasks are the item's indented note lines, see review items). Both go through
`commit`, which sets `lastWrittenData` before the write, so the resulting
`FileWatcher` event is suppressed. No re-render loop, no lost external edit.

## 4. S1 spike

Throwaway SwiftPM executable at `.gstack/spike-bureau/`, ~150 LOC, same shape as
`.gstack/spike-board/`. One window: an `SKView` on the left holding three
receipt sprites, empty space on the right.

Must prove: left-drag a sprite; when its center leaves the SKView, a
non-activating `NSPanel` spawns under the cursor showing the same receipt art,
and it follows the cursor to release, with the sprite gone. The seam must be
invisible.

Pass: reads as one physical object across the boundary, no pop, jump, flicker,
or dropped drag; the cursor stays glued through the handoff. Fail: any visible
discontinuity or a drag that drops at the edge. On fail, adopt the tray fallback
in flow (c) and cut the continuous handoff from the plan.

## 5. Data schemas

`bureau-receipts.json` (in `AppPaths.drawerDataDirectory`):

```
{
  "version": 1,
  "lifetimeFiled": 0,
  "receipts": [
    {
      "id": "5B1E...UUID",
      "textSnapshot": "Finish the product walkthrough",
      "sectionDate": "2026-07-12",
      "occurrence": 0,
      "state": "queued",          // queued | inDrawer | sticky | filed | expired
      "position": { "x": 120.0, "y": 80.0 },
      "rotation": 0.05,
      "stickySize": "full",       // full | title | chip
      "createdAt": "2026-07-12T09:14:00Z",
      "printedAt": null
    }
  ]
}
```

`bureau-tuning.json` (hot-reloaded, every feel value):

```
{
  "version": 1,
  "transition": { "pushMs": 320, "easing": [0.16, 1.0, 0.3, 1.0], "reduceMotionCrossfadeMs": 160 },
  "physics": { "repulsionRadius": 90, "repulsionStrength": 12, "torque": 0.4,
               "friction": 0.7, "restitution": 0.15, "linearDamping": 3.0,
               "angularDamping": 4.0, "gravity": -3.0 },
  "rustle": { "gain": 0.6, "velocityThreshold": 0.35, "maxVolume": 0.5, "rateCapMs": 60 },
  "print": { "stepMs": 55, "stepPx": 6, "chatterVolume": 0.4, "dingVolume": 0.7,
             "tearMs": 180, "dropImpulse": 8, "queueStaggerMs": 250 },
  "stamp": { "armInMs": 140, "overshootPx": 18, "settleMs": 120, "shiverPx": 3,
             "shiverCount": 3, "slamFrames": 12, "inkRotationMinDeg": 2,
             "inkRotationMaxDeg": 4, "doubleStrikeOffsetPx": 1.5,
             "thunkVolume": 0.8, "hapticEnabled": true },
  "crumple": { "frames": 8, "flyToTrayMs": 260 },
  "hoverScroll": { "sensitivity": 1.0, "inertiaFriction": 0.92, "minDelta": 0.5, "maxVelocity": 40 },
  "sticky": { "liveCap": 12, "subtaskVisibleCap": 6 },
  "texture": { "rerenderOnEditOnly": true },
  "filedTray": { "clearsMonday": true }
}
```

## 6. Test plan (mapped to R1-R5)

Unit (DrawerCoreTests or a new DrawerBureauTests):

- R1 `ReceiptStore` round-trip: encode then decode returns equal state; lifetime
  counter survives; atomic write leaves no partial file. Model the existing
  `BoardStoreTests` / `SnapshotStoreTests` shape.
- R1 `ReceiptLink` fuzzy re-link: reuse `TitleSimilarity.score`. Assert an exact
  title re-links, a renamed-but-close title re-links above threshold, an
  unrelated title falls below and yields EXPIRED. Riff on
  `TitleSimilarityTests`.
- R2-R5 `BureauTuning` hot-reload: write a new json, fire the `FileWatcher`
  `onChange`, assert the in-memory values changed. Reuse the `FileWatcherTests`
  temp-dir pattern.
- R3 writeback: a fake `TodoStore` (the test init that injects `readData` /
  `writeData`, as `TodoStoreTests` does) confirms a sticky edit calls
  `rename` / `setNote` and that `lastWrittenData` suppresses the echo.

Render (DrawerTests, riding `DrawerVisualRenderTests`):

- `TextureRenderer` output: render a title to `NSImage`, assert non-empty
  bitmap, correct pixel scale for a given `backingScaleFactor`, and legible ink
  (a dark-pixel-count check like `containsDarkChromePixels`).
- `BureauView` chrome: mount behind the flag, `bitmapImageRepForCachingDisplay`,
  assert the top strip is byte-identical to list mode (same header crop) and the
  seam/printer sits on the boundary. Live `SKScene` frames are not
  pixel-asserted; test the texture and the SwiftUI chrome, not the physics.

Perf gates (PERFORMANCE.md discipline, measured on the Mac, not in CI):

- 0.0% idle CPU settled: `scene.isPaused` and `view.isPaused` on hide (wired to
  `PanelController.onVisibilityChange`), bodies `isResting` when settled. Verify
  with the Energy log and Time Profiler showing no wakeups while the drawer is
  hidden, same method PERFORMANCE.md prescribes for the 2x/s tick audit.
- 60fps rummage at 100 receipts: seed 100 sprites, sweep the cursor, watch
  Animation Hitches and the SpriteKit fps counter. Record the before/after in a
  dated PERFORMANCE.md note.

## 7. Risk table

1. Drag handoff seam (S1). Prove it in the throwaway app first; tray fallback
   ready if it flickers.
2. `SKFieldNode` may not wake resting bodies (S2). If it does not, drive a
   manual force loop only while the cursor moves, then let bodies rest again.
3. SpriteKit idle CPU. Pause scene and view on `onVisibilityChange`; assert 0.0%
   with the Energy log per PERFORMANCE.md before shipping R1.
4. Fuzzy re-link false match. Use `TitleSimilarity.score` with a conservative
   threshold; below it, orphan to EXPIRED rather than mis-link. Cover both
   directions in the unit test.
5. Writeback race with Obsidian. Already handled: go through `TodoStore.commit`,
   which re-reads and re-applies the transform if the file changed. Never write
   bytes directly.
6. Texture blur at non-integer scale. Pin `contentsScale` /
   `backingScaleFactor` exactly as spike-board does; re-render on
   `viewDidChangeBackingProperties`.
7. Hover-scroll fights the list's `ScrollSwipeMonitor`. The sticky monitor is
   local to the panel and only active while a cursor hovers a live sticky; it
   consumes the event so the drawer swipe never sees it.
8. Non-activating panel focus. Copy `TeleprompterController`'s exact mask and
   flags (`.nonactivatingPanel`, `hidesOnDeactivate = false`); the sticky must
   never steal key from the app you are working in.
9. 100-receipt frame drops. `LazyVStack` bounds the list; for the scene, cap
   live bodies, sleep settled ones, and profile at 100 before R5.
10. Theme clash and fonts. The scene stays Papers-Please beside any active
    theme (Decision 5) by reading its own palette, not `DrawerTheme`'s. Fonts
    ship OFL through `FontLoader.registerBundledFonts`, the proven Pixel path.

## 8. Build order

- S1 drag handoff spike. Exit: handoff feels seamless or the tray fallback is
  chosen. ~1 session.
- S2 field wake test. Exit: know whether `SKFieldNode` wakes resting bodies or a
  manual loop is needed. ~1 session (the spec's 1 hour).
- R1 scene + selection + print + transition. Exit: queue a task, enter Bureau
  with the push-left transition, print-on-add works, 0.0% idle CPU verified,
  tests green, `make app && make install`, commit, push, dated dashboard line.
  ~3 sessions.
- R2 pull-out stickies + hover-scroll move. Exit: drag to sticky (S1 result),
  scroll moves the note, cap 12 holds. ~2 sessions.
- R3 sticky editing + subtasks + writeback. Exit: edits land in `Drawer.md`
  through `rename` / `setNote`, no watcher loop, round-trip test green.
  ~2 sessions.
- R4 stamp + FILED tray + sounds. Exit: DONE checks the task and files it,
  POSTPONED returns it, tray counts, sounds CC0/self-made. ~2 sessions.
- R5 aging paper, polish backlog, app-wide Bureau theme, GIF. Exit: theme rides
  the token system, tuning values locked, GIF recorded. ~2-3 sessions.

Each R ends the same way: tests green, build installed, commit, push, one dated
line in the vault dashboard.
