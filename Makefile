# Command Line Tools ship Swift Testing outside the default search path, and its
# Foundation cross-import overlay has no module files, so overlays are disabled.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := $(if $(wildcard $(CLT_FRAMEWORKS)),-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS))

APP := dist/Harbor.app

.PHONY: build test app run clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/Harbor $(APP)/Contents/MacOS/Harbor
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run: app
	open $(APP)

clean:
	rm -rf .build dist
