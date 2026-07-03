APP = Drawer.app
BINARY = .build/release/Drawer

.PHONY: build test app run clean release

RELEASE_TAG ?=

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
	cp -R .build/release/Drawer_Drawer.bundle $(APP)/Contents/Resources/ 2>/dev/null || true
	codesign --force --sign - $(APP)

run: app
	open $(APP)

clean:
	rm -rf .build $(APP)

install: app
	rm -rf /Applications/Drawer.app
	cp -R Drawer.app /Applications/Drawer.app

release:
	@test -n "$(RELEASE_TAG)" || (echo "Usage: make release RELEASE_TAG=v1.0.0" && exit 1)
	./scripts/release.sh $(RELEASE_TAG)
