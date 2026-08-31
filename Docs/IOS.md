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

Dirty note drafts cannot be swipe-dismissed. **Done** saves first, a successful save shows an explicit Saved state, and a failed save remains editable with a Retry action instead of silently losing the draft.

### Quick capture

The bottom capture field expands in place. Return saves to Today. A small destination control allows Today / Tomorrow / Backlog without exposing a full task editor.

Committed state changes use a compact acknowledgement surface above quick capture in addition to haptics and row motion. The same messages are posted as VoiceOver announcements so success is still legible with Reduce Motion or when tactile feedback is unavailable. Delete/move continue to prioritize their conflict-safe Undo surface.

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
| dismiss completed focus | light acknowledgement | strip closes without implying a task state change |
| file/save failure | error notification | mutation visually rolls back / never advances |

Implementation notes:

- Use prepared UIKit feedback generators for gesture thresholds where timing must land exactly on the drag crossing.
- Never fire haptics for scrolling, opening settings, expanding ordinary sections, or every button tap.
- Respect Reduce Motion; haptics remain useful when motion is reduced, and visible/VoiceOver acknowledgements do not depend on animation.
- A focus timer remains valid if notifications are denied, but Drawer explicitly says that completion notifications are off instead of silently implying background alert delivery.

## Motion language

- Primary spring: responsive, low overshoot (`.snappy` / tuned spring near 0.2–0.3s perceived duration).
- Press states should react immediately and recover quickly.
- Completion sequence: press compression -> successful canonical write -> haptic/acknowledgement -> checkbox symbol/fill -> title treatment -> row reflow.
- Do not animate optimistic completion before the Markdown mutation succeeds.
- Swipe gestures are velocity-aware, axis-locked, and use physical resistance beyond their reveal width.
- Rows never fly around gratuitously. Reordering/reassignment should feel like objects settling into place.

## Accessibility

- 44pt minimum interactive targets.
- Dynamic Type with multiline task titles; no hard truncation of the primary task text.
- VoiceOver labels describe the mutation (Complete, Reopen, Mark in progress, Move, Delete).
- Successful state changes are announced; they are not communicated only through vibration or animation.
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
- content-CAS retry before every canonical write, preserving Drawer’s existing no-clobber invariant

A replacement file bookmark is committed only after the selected file can actually be read as UTF-8 Markdown, so a bad Change Drawer.md selection cannot discard the last known-good connection.

Apple’s iOS file model returns externally selected URLs through the document picker, and persistent bookmarks are platform-specific. Relaunch/reboot/iCloud/File Provider behavior remains a physical-device integration gate rather than something inferred from macOS bookmark semantics.

### Mobile application model

`DrawerMobileModel` is MainActor-owned. It:

- resolves the selected document
- reloads + parses via `DrawerCore`
- exposes Today / Carried / Upcoming / Backlog
- performs mutation transforms against the freshest coordinated bytes
- applies the same fresh-byte recheck to automatic recurrence reconciliation / completed-task normalization before those paths write canonical Markdown
- publishes a widget snapshot only after a successful canonical read/write
- reports auxiliary widget-cache failure separately without treating the canonical save as failed
- maintains a one-action undo payload for destructive/move actions and clears that payload on source-file changes
- persists/restores absolute Focus state across scene suspension and process relaunch

### Widget snapshot

The App Group stores a tiny, versioned last-known-good snapshot. Widget timeline generation renders safely from that snapshot and opportunistically refreshes it from the selected canonical `Drawer.md` when the extension can resolve the security-scoped bookmark. If the File Provider is unavailable—or the external file is temporarily not valid UTF-8—the widget preserves the last known-good snapshot instead of inventing an empty state.

```swift
struct WidgetSnapshot: Codable {
    var version: Int
    var generatedAt: Date
    var sourceFingerprint: String
    var todayKey: String
    var carried: [WidgetTask]
    var today: [WidgetTask]
    var upcoming: [WidgetTask]
    var backlog: [WidgetTask]
}
```

Interactive intents use the same canonical mutation path. On success they rebuild the snapshot and ask WidgetKit to reload. On failure they leave the snapshot untouched, record a short-lived recovery state, and the widget explicitly says the update failed / opens Drawer for recovery. Mutable widget content is marked invalidatable while WidgetKit reloads. This is critical: no UI-only completion state.

Disconnect removes the shared snapshot and immediately reloads WidgetKit so old task text is not intentionally left on the Home or Lock Screen after the source is disconnected.

External-file bookmark access from an app-extension process remains provider/OS-sensitive. If the extension cannot safely regain access to `Drawer.md`, the interaction fails closed; Drawer never marks the cached task complete without a canonical write.

## Widget design

### Medium — hero widget

- date + remaining count
- top 3–4 unfinished tasks
- interactive completion controls
- compact add/open affordance
- explicit recovery strip after a failed interactive mutation

### Large

- Carried + Today, up to roughly 7–9 tasks depending on Dynamic Type
- same completion and failure semantics

### Lock Screen

- accessory rectangular: current/next task + remaining count
- accessory circular: remaining count
- warning glyph/accessibility label when the last interaction failed

The widget’s visual language mirrors the app: generous text, restrained material, strong checkbox affordances. Widgets should not mimic a mini database UI.

## App Intents and system entry points

V1 ships:

- **Add Drawer Task** — title + Today / Tomorrow / Backlog destination
- **Complete Drawer Task** — entity-backed unfinished task selection
- **Open Today** — opens Drawer's day surface
- **Toggle Drawer Task** — internal interactive-widget mutation intent
- `drawer://capture` — opens Drawer directly into quick capture
- `drawer://today` — opens the day surface

The public Add, Complete, and Open Today intents are surfaced as App Shortcuts/Siri actions. Add/Complete preserve thrown failure semantics for Shortcut automations; interactive-widget Toggle handles extension errors in place and exposes recovery UI. Widgets reuse the canonical mutation engine rather than maintaining separate task state.

## Obsidian integration

No vault-wide index.

- detect `[[wikilinks]]` in task title/note
- expose an Open in Obsidian action using the Obsidian URL scheme when the selected file path provides enough vault context
- keep `Drawer.md` itself canonical and editable by any compatible Markdown/File Provider app

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
    Focus/
    Haptics/
    Obsidian/
    Resources/
  DrawerWidgets/
  Shared/
  Tests/
```

The Xcode project consumes the repository’s local `DrawerCore` Swift package product. The existing macOS `Drawer` executable remains untouched except for shared-core changes required to make the boundary platform-safe.

## Release gates

Every iOS/shared-core change is gated by:

1. Apple plist, entitlement, App Group, privacy-manifest and 1024×1024 opaque AppIcon validation.
2. The full shared `DrawerCore` test suite.
3. A Release build/package/signature verification of the existing macOS `Drawer.app`, so shared-core portability work cannot silently break the desktop product.
4. iPhone-simulator Debug app + widget tests.
5. An optimized Release app + widget build with signing disabled for CI.

Signing/provisioning, TestFlight/App Store submission, real haptic tuning, and real iCloud/Obsidian File Provider behavior are device/account gates and cannot be proven by simulator CI. The concrete physical-device acceptance matrix lives in `iOS/README.md` and must be completed before App Store submission.

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
