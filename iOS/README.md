# Drawer iOS

Native iPhone companion for Drawer. It consumes the repository's local `DrawerCore` package and edits the same user-selected `Drawer.md` used by the Mac app / Obsidian.

## Open

Open `iOS/DrawerMobile.xcodeproj` in Xcode 26 or later.

Targets:

- **DrawerMobile** — iPhone app, product name `Drawer`
- **DrawerWidgets** — Home Screen and Lock Screen widgets
- **DrawerMobileTests** — mobile shared-logic tests

Deployment target: iOS 18.0.

## Signing

The project uses these identifiers by default:

- app: `com.bbrizly.drawer`
- widgets: `com.bbrizly.drawer.widgets`
- App Group: `group.com.bbrizly.drawer`

Enable the App Group on both the app and widget identifiers in the Apple Developer portal. If your signing setup uses different identifiers, change the two bundle identifiers and `DrawerShared.appGroupIdentifier` / entitlements together.

The project uses automatic signing but does not hard-code a development team so clones remain buildable. Select your team in Xcode before installing on a physical device.

## First launch

1. Tap **Choose Drawer.md**.
2. Pick the same Markdown file used by Drawer on Mac / your Obsidian vault.
3. Drawer proves the selection is readable UTF-8 Markdown before replacing any existing bookmark.
4. Drawer stores the security-scoped bookmark and coordinates reads/writes through `NSFileCoordinator`.
5. The app writes a small, versioned widget snapshot into the App Group container after successful canonical reads/writes.

No Drawer account, cloud backend, or task database is involved.

## Supported storage locations

Drawer intentionally uses the system Files document picker instead of assuming an Obsidian-specific path. The selected `Drawer.md` can therefore live wherever iOS exposes an editable file grant.

### On My iPhone / local Files storage

A locally stored Obsidian vault or ordinary Markdown folder works through the same security-scoped bookmark and coordinated file access path. Local files have no cloud-freshness dependency: if the bookmark remains valid, Drawer reads and writes the canonical file directly.

Obsidian Sync is also compatible with this model because Obsidian maintains a local vault copy. Drawer still edits the selected local `Drawer.md`; Obsidian Sync remains responsible for synchronizing that vault. Drawer does not call Obsidian Sync APIs or maintain a second copy.

### iCloud Drive / Obsidian vaults

For Obsidian on iOS, iCloud vaults should live under `iCloud Drive/Obsidian/<Vault Name>`. iOS may evict an iCloud file or retain a local copy that is older than the cloud version.

Drawer checks Apple's iCloud download state before every canonical read/write:

- **current** — safe to read/write
- **downloaded but stale** — request the newest cloud version and do not mutate yet
- **not downloaded** — request materialization and do not mutate yet
- **unresolved iCloud conflict** — fail closed until the conflict is resolved in Files/Obsidian

The foreground app retries transient iCloud/provider availability without blocking the UI. A temporary cloud outage does **not** discard the saved bookmark or replace the UI with an empty task list.

### Other Files providers

Third-party providers exposed through Files use the same persisted bookmark + `NSFileCoordinator` boundary. Unlike iCloud, client apps do not have a universal public API for forcing every third-party provider to download a placeholder. If that provider is offline, signed out, or temporarily refuses the extension process, Drawer keeps the connection and last-known-good widget snapshot and reports the provider-specific recovery state instead of pretending a mutation succeeded.

The rule across every storage type is the same: **the selected `Drawer.md` is canonical; cached widget data is never promoted to source of truth.**

## Widget writeback

Interactive widget completion attempts the exact same canonical Markdown mutation as the app and refreshes its snapshot only after that write succeeds. This intentionally avoids optimistic widget state that could disagree with Obsidian.

If a widget action cannot regain File Provider access, if iCloud is still materializing the file, or if an iCloud conflict exists, the last known-good task snapshot stays intact and the widget shows a short-lived recovery indicator instead of pretending the task changed. Disconnect removes the shared snapshot and requests an immediate WidgetKit reload.

External security-scoped bookmark behavior from a WidgetKit extension is sensitive to the selected File Provider and OS version. Validate interactive completion on a physical device with every storage provider you intend to support.

## Interaction contract

See `../Docs/IOS.md` for the product architecture and tactile language. Haptics mark state changes and physical gesture thresholds, not every tap. Successful mutations also have visible/VoiceOver acknowledgements, so success never depends on vibration or animation alone.

## CI

The iOS workflow gates every relevant change with:

- Apple plist / entitlement / App Group / privacy-manifest validation
- 1024×1024 opaque App Store icon validation
- full shared `DrawerCore` tests
- Release build/package/signature verification of the existing macOS `Drawer.app`
- Debug iPhone Simulator app + widget tests
- optimized unsigned Release iOS app + widget build

The macOS packaging gate is deliberate: the iPhone target shares `DrawerCore`, so an iOS portability change is not considered safe unless the existing desktop app still builds and packages successfully too.

Store signing and App Group provisioning still require a developer account / Xcode signing setup.

## Physical-device release acceptance

Simulator CI cannot prove File Provider grants, real Taptic Engine feel, lock-state extension behavior, or Apple signing. Before App Store submission, complete this matrix on the intended shipping iOS version.

### Local / On My iPhone

- [ ] Pick a real `Drawer.md` from **On My iPhone** (including an Obsidian local vault if exposed in Files); force-quit and relaunch; verify the bookmark reconnects without another picker prompt.
- [ ] Reboot the iPhone and verify the same local bookmark still reconnects.
- [ ] Edit the local file externally while Drawer is foregrounded; verify the UI refreshes and preserves the edit.
- [ ] Complete/add/move/delete from Drawer and verify the exact same file changes in Files/Obsidian.
- [ ] Complete a task from medium and large widgets against the local file; verify canonical Markdown changes before the widget changes.

### iCloud Drive / Obsidian

- [ ] Pick a real `Drawer.md` under `iCloud Drive/Obsidian/<Vault>`; force-quit and relaunch; verify the bookmark reconnects without another picker prompt.
- [ ] Reboot the iPhone and verify the same iCloud bookmark still reconnects.
- [ ] Make the file available offline, edit it from another Apple device, and verify Drawer reads the newest cloud version rather than an older local copy.
- [ ] If the Files UI permits it, remove the local download / allow the item to be evicted; open Drawer and verify it reports syncing, requests materialization, then recovers automatically when the file becomes current.
- [ ] Create or simulate an unresolved iCloud document conflict if practical; verify Drawer refuses canonical writes until the conflict is resolved.
- [ ] Put the device offline while the item is not current; verify Drawer keeps the bookmark and last-known-good UI rather than emptying or overwriting the source.
- [ ] Restore connectivity and verify the app recovers without asking the user to choose the same file again.

### Shared integrity / provider behavior

- [ ] Select the correct Apple Developer team; app + widget identifiers provision successfully.
- [ ] Confirm `group.com.bbrizly.drawer` (or the chosen replacement) is enabled for both app and widget and matches code + entitlements exactly.
- [ ] Install a signed Release/TestFlight build on a physical iPhone.
- [ ] Edit `Drawer.md` externally while Drawer is foregrounded; verify the UI refreshes and the external edit is preserved.
- [ ] Race an external edit with a Drawer complete/move/add operation; verify neither side is silently clobbered.
- [ ] Change Drawer.md to an unreadable/non-UTF-8 file and verify the previous good connection is retained and a useful error is shown.
- [ ] Deny/revoke the widget's external-file access if the provider permits it; verify the widget keeps old truth, shows recovery UI, and never marks the task complete.
- [ ] Test widget completion while the device is locked, immediately after unlock, and after Drawer has been force-quit.
- [ ] Test any third-party Files provider you intend to advertise; sign out/go offline and verify Drawer keeps the bookmark/cache and reports provider recovery instead of false success.
- [ ] Disconnect Drawer and verify Home/Lock Screen widgets stop intentionally showing the old task snapshot.
- [ ] Start, pause, resume, background, force-quit, and relaunch a Focus session; verify absolute remaining time is correct.
- [ ] With notification permission allowed, verify the background Focus completion alert fires once; with permission denied, verify Drawer explicitly says notifications are off.
- [ ] Check completion/add/delete/move/focus haptics on real hardware; verify no haptic fires for ordinary scrolling/navigation.
- [ ] Enable Reduce Motion and repeat the primary flows; state changes remain obvious without relying on animation.
- [ ] Run VoiceOver through connect, add, complete/reopen, progress, delete/undo, note save failure/retry, Focus, provider-sync recovery, and widget recovery messaging.
- [ ] Exercise Dynamic Type through accessibility sizes; task titles remain readable and primary actions remain reachable.
- [ ] Archive the signed Release build in Xcode and inspect Organizer validation for signing, privacy manifest, icon, extension, and App Group warnings.
- [ ] Upload to TestFlight, install the processed build, and repeat both the local-file and iCloud bookmark/widget/Focus smoke paths before App Store submission.

A release is not considered device-validated until the applicable checks above have been performed on hardware. Repository CI is the automated gate; this matrix is the platform-integration gate.
