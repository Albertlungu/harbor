# Command Line Tools ship Swift Testing outside the default search path, and its
# Foundation cross-import overlay has no module files, so overlays are disabled.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := $(if $(wildcard $(CLT_FRAMEWORKS)),-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS))

APP := dist/Harbor.app
# A fixed self-signed identity (Scripts/make-signing-identity.sh) keeps the code identity the same
# across builds, so privacy grants survive rebuilds; without it the build is signed ad hoc.
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/harbor-signing.keychain-db
SIGN_IDENTITY := Harbor Local Signing
SIGN_PASSWORD := harbor-local-signing
# Each build gets a new CFBundleVersion so Harbor can tell it was updated.
BUILD_STAMP := $(shell date +%Y%m%d%H%M%S)

.PHONY: build test app run install clean

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
	if [ -f Support/AppIcon.icns ]; then cp Support/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns; fi
	if [ -f Support/MenuBarIcon.png ]; then cp Support/MenuBarIcon.png Support/MenuBarIcon@2x.png $(APP)/Contents/Resources/; fi
	if [ -f .build/release/harbor-mcp ]; then cp .build/release/harbor-mcp $(APP)/Contents/MacOS/harbor-mcp; fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_STAMP)" $(APP)/Contents/Info.plist
	if [ -f "$(SIGN_KEYCHAIN)" ]; then \
		security unlock-keychain -p "$(SIGN_PASSWORD)" "$(SIGN_KEYCHAIN)" && \
		codesign --force --keychain "$(SIGN_KEYCHAIN)" --sign "$(SIGN_IDENTITY)" $(APP)/Contents/MacOS/harbor-mcp 2>/dev/null; \
		codesign --force --keychain "$(SIGN_KEYCHAIN)" --sign "$(SIGN_IDENTITY)" $(APP); \
	else \
		codesign --force --sign - $(APP); \
	fi

run: app
	open $(APP)

# Quits the running Harbor so it can restore the macOS Dock, then replaces and relaunches it.
install: app
	osascript -e 'tell application id "io.github.albertlungu.harbor" to quit' 2>/dev/null || true
	for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Harbor >/dev/null || break; sleep 0.5; done
	rm -rf /Applications/Harbor.app
	ditto $(APP) /Applications/Harbor.app
	open /Applications/Harbor.app

clean:
	rm -rf .build dist
