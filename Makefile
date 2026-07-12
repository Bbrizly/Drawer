APP = Drawer.app
BINARY = .build/release/Drawer
MCP_BINARY = .build/release/drawer-mcp

.PHONY: build test app run clean release dist

RELEASE_TAG ?=

# Developer ID signing for distribution outside the Mac App Store.
# DEV_ID resolves to your one "Developer ID Application" cert by name.
# NOTARY_PROFILE is the keychain profile made once with:
#   xcrun notarytool store-credentials drawer-notary \
#     --apple-id <you> --team-id 8S2SR5UZ54 --password <app-specific-pw>
DEV_ID ?= Developer ID Application
NOTARY_PROFILE ?= drawer-notary

build:
	swift build

test:
	swift test

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp $(BINARY) $(APP)/Contents/MacOS/Drawer
	cp $(MCP_BINARY) $(APP)/Contents/MacOS/drawer-mcp
	cp -R .build/release/Drawer_Drawer.bundle $(APP)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign - $(APP)

# Runs the freshly built copy from /Applications with a clean Accessibility
# grant. The app is ad-hoc signed, so every build gets a new signature the old
# grant no longer matches -- macOS keeps showing Drawer as "granted" while
# AXIsProcessTrusted() stays false. Resetting the grant clears that stale entry
# so the right-Command tap (and Work Mode) can be re-granted against this build.
# Re-grant Accessibility once after each run; that is inherent to ad-hoc signing.
run: install
	-osascript -e 'quit app "Drawer"' 2>/dev/null
	sleep 1
	-pkill -f "Drawer.app/Contents/MacOS/Drawer" 2>/dev/null
	sleep 1
	@echo "--- reset accessibility grant for Drawer ---"
	-tccutil reset Accessibility com.bassam.drawer 2>&1
	@echo "--- relaunch installed copy ---"
	open /Applications/Drawer.app
	sleep 3
	@ps aux | grep "[D]rawer.app/Contents/MacOS/Drawer" | awk '{print $$2, $$11}'

# Sign with Developer ID + hardened runtime, notarize, and staple.
# Produces Drawer.zip that any Mac opens with no Gatekeeper warning.
# Needs the Developer ID cert and the drawer-notary keychain profile (see top).
dist: app
	codesign --force --options runtime --timestamp -s "$(DEV_ID)" $(APP)/Contents/MacOS/drawer-mcp
	codesign --force --options runtime --timestamp -s "$(DEV_ID)" $(APP)
	ditto -c -k --keepParent $(APP) Drawer.zip
	xcrun notarytool submit Drawer.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	rm -f Drawer.zip
	ditto -c -k --keepParent $(APP) Drawer.zip
	@echo "Notarized Drawer.zip is ready to ship."

clean:
	rm -rf .build $(APP)

install: app
	rm -rf /Applications/Drawer.app
	cp -R Drawer.app /Applications/Drawer.app

release:
	@test -n "$(RELEASE_TAG)" || (echo "Usage: make release RELEASE_TAG=v1.0.0" && exit 1)
	./scripts/release.sh $(RELEASE_TAG)
