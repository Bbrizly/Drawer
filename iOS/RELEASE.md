# Drawer iOS Release Acceptance

This is the final release checklist for the native iPhone companion. `Drawer.md` remains the only task source of truth. CI proves repository behavior; signed hardware validation proves Apple platform integration.

## App Review setup

Drawer does **not** require an account, backend, Obsidian installation, or network service to be reviewed.

A reviewer can exercise the complete core app with a plain Markdown file in Files:

1. In Files, create a text file named `Drawer.md` under **On My iPhone** or **iCloud Drive**.
2. Put this sample content in it:

```markdown
## 2026-08-31
- [ ] Review Drawer (25m)
- [/] Test the Focus timer (5m)
    This note should stay attached to the task.
- [ ] Recurring example
    <!-- drawer:repeat=daily -->

## 2026-09-01
- [ ] Tomorrow task

## Backlog
- [ ] Backlog example
```

3. Open Drawer and choose that `Drawer.md` with the system document picker.
4. Add, edit, complete/reopen, mark in progress, move and delete/undo tasks.
5. Start Focus from a task. With notifications permitted, background the app and verify the completion alert. On devices that support Live Activities, verify the Lock Screen / Dynamic Island surface.
6. Add a Drawer widget and complete a task from the widget. The Markdown file is canonical; the widget only changes after the canonical write succeeds.

Obsidian is optional. If installed, Drawer can point at the same `Drawer.md` in an Obsidian vault, but App Review does not need it.

## Exact automated gate

The merge candidate must pass on its exact head SHA:

- shared `DrawerCore` tests
- existing macOS Drawer Release package and signature regression
- iOS plist / entitlement / privacy-manifest invariants
- matching app + widget App Group
- App Group UserDefaults required-reason declaration
- 1024×1024 opaque App Store icon validation
- Debug iPhone Simulator app + widget tests
- optimized unsigned iOS Release app + widget build

No earlier SHA counts as release evidence after the branch moves.

## Physical iPhone acceptance

### Canonical file and editing

- [ ] Pick a local **On My iPhone** `Drawer.md`, force-quit, relaunch and reboot; the bookmark reconnects without another picker prompt.
- [ ] Pick an iCloud Drive `Drawer.md`, force-quit, relaunch and reboot; the bookmark reconnects without another picker prompt.
- [ ] Edit `Drawer.md` externally while Drawer is foregrounded; Drawer refreshes without erasing the external edit.
- [ ] Race an external edit with complete/add/edit/move/delete; neither side is silently clobbered.
- [ ] Edit title + Focus duration + note in one Save. Verify all three persist together in Markdown.
- [ ] Edit only the title of a task with a custom duration such as `(45m)`; the 45-minute duration remains intact.
- [ ] Edit a recurring task; Drawer-owned recurrence metadata remains attached and recurrence still advances exactly once on completion.
- [ ] Delete or move, then externally modify the file before Undo; Drawer must refuse any Undo that could overwrite newer external bytes.
- [ ] Change to a bad/unreadable/non-UTF-8 replacement; the existing good file remains canonical.

### iCloud / Files provider recovery

- [ ] Test an evicted/not-downloaded iCloud item. Drawer requests materialization and never writes the placeholder/stale copy.
- [ ] Stage an unavailable replacement while a good file is connected. The old file remains visible, editable and widget-targeted until the replacement produces a current UTF-8 read.
- [ ] Force-quit during staged replacement and relaunch; the old canonical source returns and pending validation resumes.
- [ ] Exercise an authentication-required provider state; fix access in Files/provider UI and return to Drawer without reselecting the file.
- [ ] Exercise an unresolved iCloud conflict if practical; Drawer refuses canonical writes until it is resolved.
- [ ] Test any third-party Files provider you intend to advertise while offline/signed out; no optimistic mutation is shown.

### Widgets and ambient surfaces

- [ ] Add small, medium and large Home Screen widgets plus supported Lock Screen widgets.
- [ ] Verify carried tasks are ordered before today's unfinished tasks in the Next surface.
- [ ] Complete from medium/large widget against a local file; Markdown changes before widget truth changes.
- [ ] Repeat widget completion with Drawer force-quit, after unlock, and while the device is locked when the OS permits interaction.
- [ ] Make provider access fail during a widget mutation; the last-known-good snapshot stays visible with recovery messaging.
- [ ] Disconnect Drawer; widgets stop intentionally showing the old task snapshot.

### Focus / Live Activity

- [ ] Start Focus and verify the in-app timer, persisted session and Live Activity show the same task and remaining time.
- [ ] Pause Focus; the Live Activity stops counting and shows the paused value.
- [ ] Resume Focus; the Live Activity resumes from the persisted remaining time.
- [ ] End/reset Focus; the Live Activity ends instead of lingering as a stale countdown.
- [ ] Let Focus finish; the Live Activity reaches the completed state and the completion notification fires once when authorized.
- [ ] Background, lock, force-quit and relaunch during a running Focus; remaining time is derived from the absolute end date and does not reset.
- [ ] Deny notification permission; Focus still works and Drawer clearly reports that completion notifications are unavailable.
- [ ] Confirm task titles are appropriately protected on privacy-sensitive widget/Live Activity surfaces when the device is locked.

### Tactile, accessibility and layout

- [ ] Verify completion, reopen, add, progress, recurrence, move, delete, undo and Focus haptics on a physical Taptic Engine.
- [ ] Ordinary navigation and scrolling do not vibrate.
- [ ] Swipe thresholds feel deliberate; destructive delete feedback occurs only at the destructive threshold.
- [ ] Enable Reduce Motion and repeat primary flows; all state changes remain understandable without motion.
- [ ] Run VoiceOver through connection, capture, task row actions, edit/save, delete/undo, Focus, provider recovery and widgets.
- [ ] Run Dynamic Type through accessibility sizes in portrait and landscape; task titles remain readable and primary controls remain reachable.
- [ ] Verify frequent controls meet comfortable iPhone touch-target sizing and are not clipped by larger text.

### Signing / distribution

- [ ] Select the shipping Apple Developer team.
- [ ] Confirm `com.bbrizly.drawer`, `com.bbrizly.drawer.widgets`, and `group.com.bbrizly.drawer` (or the deliberate shipping replacements) are provisioned consistently.
- [ ] Install a signed Release build on a physical iPhone.
- [ ] Archive in Xcode and pass Organizer validation for signing, icon, privacy manifest, App Group, widgets and Live Activities.
- [ ] Upload to TestFlight, install the processed build, and repeat the local-file, iCloud, widget and Focus smoke paths.

## Release rule

Do not claim hardware behaviors as proven by Simulator CI. The repository can be merged when the exact-head automated gate is green. App Store submission remains blocked only by the signed-device checks above that require Apple credentials, real providers, lock state, Taptic Engine and TestFlight processing.
