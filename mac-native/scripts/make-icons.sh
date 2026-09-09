#!/bin/bash
# Regenerates every app icon from the single renderer in make-icon.swift:
# the macOS .icns and the PNG electron-builder derives the Windows .ico from.
#
# The outputs are committed, so this only needs running when the artwork
# changes — neither `make app` nor the release workflow calls it.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(cd .. && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MASTER="$WORK/icon-1024.png"
swift scripts/make-icon.swift "$MASTER"

# macOS: an .iconset of every size Finder, the Dock and Privacy & Security
# each ask for, folded into one .icns.
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
	sips -z $size $size "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
	sips -z $((size * 2)) $((size * 2)) "$MASTER" \
		--out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "wrote mac-native/Resources/AppIcon.icns"

# Windows/Linux: electron-builder picks up build/icon.png by convention and
# generates the .ico itself, so one 1024px master is all it needs.
mkdir -p "$REPO_ROOT/os-menu/build"
cp "$MASTER" "$REPO_ROOT/os-menu/build/icon.png"
echo "wrote os-menu/build/icon.png"
