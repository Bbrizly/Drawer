APP = Drawer.app
BINARY = .build/release/Drawer

.PHONY: build test app run clean

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
	codesign --force --sign - $(APP)

run: app
	open $(APP)

clean:
	rm -rf .build $(APP)

install: app
	rm -rf /Applications/Drawer.app
	cp -R Drawer.app /Applications/Drawer.app
