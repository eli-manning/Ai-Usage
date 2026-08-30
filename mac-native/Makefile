# Build, bundle and verify the native macOS app.
#
# SwiftPM can only produce a bare executable; macOS needs a real .app bundle
# before it will grant a status-bar slot, register a login item, or let the app
# be signed. `make app` assembles that bundle around the SwiftPM output.

APP_NAME    := AI Usage
BUNDLE_ID   := com.eli.aiusage
# Overridable so CI can stamp the release tag into the bundle:
# `make dmg VERSION=1.2.0`. Defaults to the dev version for local builds.
VERSION     ?= 0.1.0
CONFIG      := release
ARCH_DIR    := $(shell swift build -c $(CONFIG) --show-bin-path)
BUILD_DIR   := build
DIST_DIR    := dist
APP_DIR     := $(BUILD_DIR)/$(APP_NAME).app
# Hyphenated: a URL with %20 in it is a bad download link to hand someone.
DMG         := $(DIST_DIR)/AI-Usage.dmg
ZIP         := $(DIST_DIR)/AI-Usage.zip
MACOS_DIR   := $(APP_DIR)/Contents/MacOS
RES_DIR     := $(APP_DIR)/Contents/Resources

.PHONY: all build app run debug test verify fixtures dmg zip dist clean

all: app

build:
	swift build -c $(CONFIG)

test:
	swift test

## Run straight from SwiftPM — fastest loop for popover/settings work, but the
## menu-bar item and login-item registration need the real bundle below.
debug:
	swift run AiUsage

## Assemble the .app bundle.
app: build
	@rm -rf "$(APP_DIR)"
	@mkdir -p "$(MACOS_DIR)" "$(RES_DIR)"
	@cp "$(ARCH_DIR)/AiUsage" "$(MACOS_DIR)/$(APP_NAME)"
	@# ptydrive sits beside the main executable; UsageFetcher.helperURL looks
	@# for it there first, which is the same place `swift run` leaves it.
	@cp "$(ARCH_DIR)/ptydrive" "$(MACOS_DIR)/ptydrive"
	@if [ -d "$(ARCH_DIR)/AiUsage_AiUsage.bundle" ]; then \
		cp -R "$(ARCH_DIR)/AiUsage_AiUsage.bundle" "$(RES_DIR)/"; \
	fi
	@# `%b`, not `%s` — the template below carries \n/\t escapes, and %s
	@# writes them through as literal backslash-n. That produced a one-line
	@# plist that `plutil -lint` rejects and Gatekeeper reports as "a required
	@# plist file or resource is malformed", even though the app still launched.
	@printf '%b' '$(INFO_PLIST)' > "$(APP_DIR)/Contents/Info.plist"
	@plutil -lint "$(APP_DIR)/Contents/Info.plist" >/dev/null
	@# Ad-hoc sign, inner binary first — a nested executable must carry its own
	@# signature or Gatekeeper rejects the whole bundle. Same fix os-menu needed
	@# in its afterSign hook.
	@codesign --force --sign - "$(MACOS_DIR)/ptydrive"
	@codesign --force --sign - --deep "$(APP_DIR)"
	@echo "built $(APP_DIR)"

run: app
	@open "$(APP_DIR)"

## Distributable artifacts. `dmg` is what the README links to; `zip` exists
## because it is the only format Sparkle-style auto-update could consume later,
## and it costs nothing to emit both.
dist: dmg zip

dmg: app
	@mkdir -p "$(DIST_DIR)"
	@rm -f "$(DMG)"
	@# A staging dir with an /Applications symlink is what gives the mounted
	@# volume the familiar drag-to-install layout.
	@rm -rf "$(BUILD_DIR)/dmg-stage"
	@mkdir -p "$(BUILD_DIR)/dmg-stage"
	@cp -R "$(APP_DIR)" "$(BUILD_DIR)/dmg-stage/"
	@ln -s /Applications "$(BUILD_DIR)/dmg-stage/Applications"
	@hdiutil create -volname "$(APP_NAME)" -srcfolder "$(BUILD_DIR)/dmg-stage" \
		-ov -format UDZO -quiet "$(DMG)"
	@rm -rf "$(BUILD_DIR)/dmg-stage"
	@echo "built $(DMG)"

zip: app
	@mkdir -p "$(DIST_DIR)"
	@rm -f "$(ZIP)"
	@# ditto, not `zip` — it is the only archiver that preserves the bundle's
	@# code signature and resource forks intact.
	@ditto -c -k --keepParent "$(APP_DIR)" "$(ZIP)"
	@echo "built $(ZIP)"

## Prove the ported parsers still agree with os-menu's JavaScript originals on
## the captured fixtures. Requires the sibling claude-usage-tracker checkout.
verify: test
	@bash scripts/verify-against-js.sh

## Re-capture fixtures from the CLIs installed on this machine, and regenerate
## the expected JSON using the JavaScript parsers. Run this only when a CLI's
## output format has genuinely changed — it rewrites the contract the tests
## check against.
fixtures: build
	@bash scripts/capture-fixtures.sh

clean:
	swift package clean
	@rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"

# LSUIElement is what makes this a menu-bar app with no Dock icon.
define INFO_PLIST
<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n\t<key>CFBundleName</key>\n\t<string>$(APP_NAME)</string>\n\t<key>CFBundleDisplayName</key>\n\t<string>$(APP_NAME)</string>\n\t<key>CFBundleIdentifier</key>\n\t<string>$(BUNDLE_ID)</string>\n\t<key>CFBundleVersion</key>\n\t<string>$(VERSION)</string>\n\t<key>CFBundleShortVersionString</key>\n\t<string>$(VERSION)</string>\n\t<key>CFBundleExecutable</key>\n\t<string>$(APP_NAME)</string>\n\t<key>CFBundlePackageType</key>\n\t<string>APPL</string>\n\t<key>LSMinimumSystemVersion</key>\n\t<string>13.0</string>\n\t<key>LSUIElement</key>\n\t<true/>\n\t<key>NSHighResolutionCapable</key>\n\t<true/>\n</dict>\n</plist>
endef
