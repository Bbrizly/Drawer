# Drawer for iPhone

> Drawer is the ambient action surface for a Markdown brain: glance, capture, check off, focus, leave.

This document is the implementation contract for the iOS companion. The iPhone app is not a vault browser, project manager, habit tracker, or replacement for Obsidian. `Drawer.md` remains canonical truth.

## Product principles

1. **The shortest path wins.** Launch goes directly to the user's day. No dashboard and no tab bar.
2. **Markdown remains the database.** Every task mutation writes back to the selected `Drawer.md` without a parallel task store.
3. **The phone is an ambient surface.** Home Screen widgets, Lock Screen widgets, Shortcuts/App Intents, and quick capture are first-class.
4. **Tactile, not noisy.** Haptics communicate state transitions and physical thresholds; ordinary navigation stays quiet.
5. **Never fake success.** A widget or app mutation only changes its rendered snapshot after the canonical Markdown write succeeds.
6. **Obsidian is context, not competition.** Drawer may deep-link to linked notes but does not index or render the whole vault.
7. **Native before clever.** SwiftUI/UIKit/WidgetKit/App Intents/Foundation file coordination; no web shell and no custom sync service.

## V1 information architecture

### Main scene

A single scrollable day surface:

- large date/day header + remaining count
- Carried Over (only when non-empty)
- Today
- Tomorrow / next dated section (collapsed by default)
- Backlog (collapsed)
- bottom quick-capture field

The first screen must be useful one-handed. Primary task actions live inside the lower two-thirds of the display.

### Task detail sheet

Tap a row to open a compact bottom sheet with:

- full title
- duration hint
- note / edit note
- Start Focus
- mark / clear In Progress
- move to Today / Tomorrow / Backlog
- Open in Obsidian when a `[[wikilink]]` is detectable
- Delete (destructive, separated visually)

### Quick capture

The bottom capture field expands in place. Return saves to Today. A small destination control allows Today / Tomorrow / Backlog without exposing a full task editor.

## Tactile language

Haptics are state grammar, not decoration.

| Moment | Feedback | Motion |
| --- | --- | --- |
| press task / control | none | 0.985–0.99 compression, fast release spring |
| checkbox touch-down | none | checkbox compresses slightly |
| task completed | success notification | checkbox fills/morphs, title resolves, row settles/collapses |
| task reopened | light impact | reverse checkbox transition; no celebration |
| add task | soft/light impact | capture field gives a tiny upward settle; new row inserts with spring |
| swipe crosses action threshold | selection detent, once per crossing | resistance changes past threshold |
| mark in progress | selection | accent rail/wash springs in |
| move/reassign | selection + light impact on committed destination | sheet snaps down; row migrates |
| destructive threshold | rigid/medium impact only when armed | red action locks in; cancelling crosses back silently |
| delete committed | warning notification | row compresses then collapses; Undo toast appears |
| undo | light impact | row restores from prior geometry |
| focus start/resume | medium impact | timer expands into active state |
| focus pause | selection | timer settles, no dramatic animation |
| focus finish | success notification | restrained completion pulse |
| file/save failure | error notification | mutation visually rolls back / never advances |

Implementation notes:

- Prefer SwiftUI `sensoryFeedback` where the trigger maps cleanly to state.
- Use prepared UIKit feedback generators for gesture thresholds where timing must land exactly on the drag crossing.
- Never fire haptics for scrolling, opening settings, expanding ordinary sections, or every button tap.
- Respect Reduce Motion; haptics remain useful when motion is reduced, but celebration effects disappear.

## Motion language

- Primary spring: responsive, low overshoot (`.snappy` / tuned spring near 0.2–0.3s perceived duration).
- Press states should react immediately and recover quickly.
- Completion sequence: press compression -> successful canonical write -> haptic -> checkbox symbol/fill -> title treatment -> row reflow.
- Do not animate optimistic completion before the Markdown mutation succeeds.
- Swipe gestures are velocity-aware, axis-locked, and use physical resistance beyond their reveal width.
- Rows never fly around gratuitously. Reordering/reassignment should feel like objects settling into place.

## Accessibility

- 44pt minimum interactive targets.
- Dynamic Type with multiline task titles; no hard truncation of the primary task text.
- VoiceOver labels describe the mutation (Complete, Reopen, Mark in progress, Move, Delete).
- Reduce Motion switches collapse/insert transitions to near-instant state changes.
- Differentiate in-progress and completed state with shape/symbol/text, never color alone.
- Lock Screen widgets use privacy redaction where appropriate.

## Architecture

```text
Drawer.md (canonical)
       |
       v
Drawer document access adapter
       |
       +--> DrawerCore parser / writeback transforms
       |
       +--> in-app observable model
       |
       +--> App Group WidgetSnapshot.json
                    |
                    v
             WidgetKit timeline
```

### Shared core

Keep `TodoParser`, `TodoWriteback`, `TodoItem`, planning, timer models, and other deterministic behavior in `DrawerCore`.

Add an iOS-compatible document boundary rather than teaching core logic about UIKit or WidgetKit. The mobile adapter owns:

- selected file bookmark
- coordinated reads/writes (`NSFileCoordinator`)
- foreground file presentation / external-change notifications (`NSFilePresenter`)
- stale/invalid bookmark recovery
- content-CAS retry before write, preserving Drawer’s existing no-clobber invariant

Apple’s current iOS file model returns externally selected URLs through the document picker, and persistent bookmarks should be treated as platform-specific. The implementation must explicitly test relaunch/reboot/iCloud/File Provider behavior rather than assuming macOS bookmark semantics.

### Mobile application model

`DrawerMobileModel` is MainActor-owned. It:

- resolves the selected document
- reloads + parses via `DrawerCore`
- exposes Today / Carried / Upcoming / Backlog
- performs mutation transforms against the freshest coordinated bytes
- publishes a widget snapshot only after a successful canonical write
- maintains a one-action undo payload for destructive/move actions

### Widget snapshot

Widgets never parse an arbitrary vault on render. The app stores a tiny versioned snapshot in the App Group container:

```swift
struct WidgetSnapshot: Codable {
    var schemaVersion: Int
    var generatedAt: Date
    var sourceFingerprint: String
    var todayKey: String
    var remaining: Int
    var tasks: [WidgetTask]
}
```

The widget renders immediately from this cache.

Interactive intents attempt the same canonical mutation path. On success they rebuild the snapshot and ask WidgetKit to reload. On failure they leave the snapshot untouched. This is critical: no UI-only completion state.

Because external-file bookmark behavior across app-extension processes is platform-sensitive, interactive widget writeback is an explicit integration spike. If the extension cannot safely regain access to the user-selected file, V1 must fall back to opening Drawer for that mutation rather than lying about completion.

## Widget design

### Medium — hero widget

- date + remaining count
- top 3–4 unfinished tasks
- interactive completion controls
- compact add/open affordance

### Large

- Carried + Today, up to roughly 7–9 tasks depending on Dynamic Type
- same completion behavior
- stale-state indicator only when genuinely necessary

### Lock Screen

- accessory rectangular: current/next task + remaining count
- accessory circular: remaining count

The widget’s visual language mirrors the app: generous text, restrained material, strong checkbox affordances. Widgets should not mimic a mini database UI.

## App Intents

V1 intents:

- Add Drawer Task (title + destination)
- Complete Drawer Task (entity-backed task selection)
- Capture to Drawer (text/url into Today or Backlog)
- Open Today in Drawer

These support Shortcuts/Siri/system surfaces and are also reused by interactive widgets where appropriate.

## Obsidian integration

No vault-wide index.

- detect `[[wikilinks]]` in task title/note
- expose an Open in Obsidian action using the Obsidian URL scheme when the selected file path provides enough vault context
- otherwise expose Open Source File in the Files/Obsidian ecosystem

Drawer remains useful with any Markdown editor; Obsidian integration is additive.

## Repository layout

```text
iOS/
  DrawerMobile.xcodeproj/
  DrawerMobile/
    App/
    Model/
    Views/
    FileAccess/
    Haptics/
    Intents/
    Resources/
  DrawerWidgets/
  Shared/
  Tests/
```

The Xcode project consumes the repository’s local `DrawerCore` Swift package product. The existing macOS `Drawer` executable remains untouched except for shared-core changes required to make the boundary platform-safe.

## Implementation order

1. Platform-enable `DrawerCore` without changing macOS behavior.
2. Build file picker + persisted bookmark + coordinated document adapter.
3. Build `DrawerMobileModel` and golden task mutation tests.
4. Build the day surface, task row, quick capture, detail sheet, undo.
5. Add the haptic/motion language and accessibility behavior.
6. Add App Group snapshot writer.
7. Build WidgetKit medium/large/Lock Screen widgets.
8. Add interactive widget intents and validate canonical write semantics.
9. Add App Intents / Shortcuts and Obsidian deep links.
10. Run macOS core tests plus iOS build/tests; review the final diff for macOS regressions.

## Explicit non-goals

- Drawer Cloud
- account/login
- independent database as task truth
- full vault browser/search/index
- habits/streaks
- Kanban
- team collaboration
- calendar replacement
- generic AI chat screen

If a proposed feature makes Drawer slower to glance at or increases the chance that `Drawer.md` stops being obviously authoritative, it does not belong in V1.
