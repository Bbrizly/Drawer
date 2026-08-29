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
3. Drawer stores a bookmark to that file and coordinates reads/writes through `NSFileCoordinator`.
4. The app writes a small, versioned widget snapshot into the App Group container after each successful canonical file read/write.

No Drawer account, cloud backend, or task database is involved.

## Widget writeback

Interactive widget completion attempts the exact same canonical Markdown mutation as the app and refreshes its snapshot only after that write succeeds. This intentionally avoids optimistic widget state that could disagree with Obsidian.

External security-scoped bookmark behavior from a WidgetKit extension is sensitive to the selected File Provider and OS version. Test interactive completion on a physical device with the exact storage providers you intend to support (iCloud Drive / Obsidian and any third-party providers). A failed external-file mutation does not update the widget cache.

## Interaction contract

See `../Docs/IOS.md` for the product architecture and tactile language. The key rule is that haptics mark state changes and physical gesture thresholds, not every tap.

## CI

The iOS workflow runs the repository's Swift package tests and an unsigned iPhone Simulator build/test of this project on macOS 26. Store signing and App Group provisioning still require a developer account / Xcode signing setup.
