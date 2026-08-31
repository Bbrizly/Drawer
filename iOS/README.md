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

## Widget writeback

Interactive widget completion attempts the exact same canonical Markdown mutation as the app and refreshes its snapshot only after that write succeeds. This intentionally avoids optimistic widget state that could disagree with Obsidian.

If a widget action cannot regain File Provider access, the last known-good task snapshot stays intact and the widget shows a short-lived recovery indicator instead of pretending the task changed. Disconnect removes the shared snapshot and requests an immediate WidgetKit reload.

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

Simulator CI cannot prove File Provider grants, real Taptic Engine feel, lock-state extension behavior, or Apple signing. Before App Store submission, complete this matrix on the intended shipping iOS version and the exact storage provider used in production:

- [ ] Select the correct Apple Developer team; app + widget identifiers provision successfully.
- [ ] Confirm `group.com.bbrizly.drawer` (or the chosen replacement) is enabled for both app and widget and matches code + entitlements exactly.
- [ ] Install a signed Release/TestFlight build on a physical iPhone.
- [ ] Pick a real `Drawer.md` in iCloud Drive / the Obsidian vault; force-quit and relaunch; verify the bookmark reconnects without another picker prompt.
- [ ] Reboot the iPhone and verify the same bookmark still reconnects.
- [ ] Edit `Drawer.md` externally while Drawer is foregrounded; verify the UI refreshes and the external edit is preserved.
- [ ] Race an external edit with a Drawer complete/move/add operation; verify neither side is silently clobbered.
- [ ] Change Drawer.md to an unreadable/non-UTF-8 file and verify the previous good connection is retained and a useful error is shown.
- [ ] Complete a task from medium and large widgets; verify canonical Markdown changes before the widget changes.
- [ ] Deny/revoke the widget's external-file access if the provider permits it; verify the widget keeps old truth, shows recovery UI, and never marks the task complete.
- [ ] Test widget completion while the device is locked, immediately after unlock, and after Drawer has been force-quit.
- [ ] Disconnect Drawer and verify Home/Lock Screen widgets stop intentionally showing the old task snapshot.
- [ ] Start, pause, resume, background, force-quit, and relaunch a Focus session; verify absolute remaining time is correct.
- [ ] With notification permission allowed, verify the background Focus completion alert fires once; with permission denied, verify Drawer explicitly says notifications are off.
- [ ] Check completion/add/delete/move/focus haptics on real hardware; verify no haptic fires for ordinary scrolling/navigation.
- [ ] Enable Reduce Motion and repeat the primary flows; state changes remain obvious without relying on animation.
- [ ] Run VoiceOver through connect, add, complete/reopen, progress, delete/undo, note save failure/retry, Focus, and widget recovery messaging.
- [ ] Exercise Dynamic Type through accessibility sizes; task titles remain readable and primary actions remain reachable.
- [ ] Archive the signed Release build in Xcode and inspect Organizer validation for signing, privacy manifest, icon, extension, and App Group warnings.
- [ ] Upload to TestFlight, install the processed build, and repeat the bookmark + widget + Focus smoke path before App Store submission.

A release is not considered device-validated until the applicable checks above have been performed on hardware. Repository CI is the automated gate; this matrix is the platform-integration gate.
