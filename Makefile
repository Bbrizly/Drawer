APP = Drawer.app
BINARY = .build/release/Drawer
MCP_BINARY = .build/release/drawer-mcp

.PHONY: build test app appstore masdist run clean release dist

RELEASE_TAG ?=

# Developer ID signing for distribution outside the Mac App Store.
# DEV_ID resolves to your one "Developer ID Application" cert by name.
# NOTARY_PROFILE is the keychain profile made once with:
#   xcrun notarytool store-credentials drawer-notary \
#     --apple-id <you> --team-id 8S2SR5UZ54 --password <app-specific-pw>
DEV_ID ?= Developer ID Application
NOTARY_PROFILE ?= drawer-notary

SWIFT_FLAGS ?=

build:
	swift build

test:
	swift test

app:
	swift build -c release $(SWIFT_FLAGS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/PrivacyInfo.xcprivacy $(APP)/Contents/Resources/PrivacyInfo.xcprivacy
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

# Mac App Store flavor for local inspection: -DAPPSTORE removes the
# Accessibility surface (attribution sampling and the right-Command tap) and
# switches defaults to sandbox-safe paths. Ad-hoc signed, still bundles
# drawer-mcp for dev convenience; `masdist` builds the real store artifact.
appstore: SWIFT_FLAGS = -Xswiftc -DAPPSTORE
appstore: app

# --- Mac App Store packaging ---
# Needs, from developer.apple.com for Team 69NPZWZB47:
#   - an "Apple Distribution" certificate (signs the app)
#   - a "Mac Installer Distribution" certificate (signs the pkg; its keychain
#     name is "3rd Party Mac Developer Installer: ...")
#   - a Mac App Store provisioning profile for com.bassam.drawer saved as
#     $(MAS_PROFILE). Verify its app-identifier prefix matches the
#     entitlements: security cms -D -i $(MAS_PROFILE)
# Then: make masdist, upload Drawer.pkg with Transporter (or
#   xcrun altool --validate-app -f Drawer.pkg -t macos ...).
MAS_APP_SIGN ?= Apple Distribution
MAS_PKG_SIGN ?= 3rd Party Mac Developer Installer
MAS_PROFILE ?= Drawer_MAS.provisionprofile
MAS_PRODUCTS = .build/apple/Products/Release

masdist:
	@test -f "$(MAS_PROFILE)" || (echo "Missing $(MAS_PROFILE); download it from developer.apple.com" && exit 1)
	swift build -c release --arch arm64 --arch x86_64 --product Drawer -Xswiftc -DAPPSTORE
	rm -rf $(APP) Drawer.pkg
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/PrivacyInfo.xcprivacy $(APP)/Contents/Resources/PrivacyInfo.xcprivacy
	cp $(MAS_PRODUCTS)/Drawer $(APP)/Contents/MacOS/Drawer
	cp -R $(MAS_PRODUCTS)/Drawer_Drawer.bundle $(APP)/Contents/Resources/ 2>/dev/null || true
	cp "$(MAS_PROFILE)" $(APP)/Contents/embedded.provisionprofile
	codesign --force --sign "$(MAS_APP_SIGN)" \
		--entitlements Resources/Drawer-AppStore.entitlements $(APP)
	codesign --verify --strict --verbose=2 $(APP)
	productbuild --component $(APP) /Applications --sign "$(MAS_PKG_SIGN)" Drawer.pkg
	@echo "Drawer.pkg is ready to upload with Transporter."

clean:
	rm -rf .build $(APP)

install: app
	rm -rf /Applications/Drawer.app
	cp -R Drawer.app /Applications/Drawer.app

release:
	@test -n "$(RELEASE_TAG)" || (echo "Usage: make release RELEASE_TAG=v1.0.0" && exit 1)
	./scripts/release.sh $(RELEASE_TAG)
