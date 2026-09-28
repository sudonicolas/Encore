#!/bin/bash
# Renders Encore's Mac App Store screenshots (2880x1800) into docs/app-store/screenshots.
#
#   tools/screenshots/make-screenshots.sh                    All scenes
#   tools/screenshots/make-screenshots.sh --only hero,lookups
#   tools/screenshots/make-screenshots.sh --portrait         The five 4:5 (2160x2700)
#                                                            carousel slides, into
#                                                            docs/app-store/portrait
#
# Builds a screenshot tool from Encore's own sources plus tools/screenshots/*.swift and
# runs it against a fictional history in a throwaway home folder. Everything renders on a
# temporary virtual 2x display, so nothing shows on screen and no Screen Recording
# permission is needed. Needs Xcode 26+, an Apple Intelligence Mac (for the smart titles
# and the rewrite scene) and a network connection (for exchange rates).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL_DIR="$ROOT_DIR/tools/screenshots"
BUILD_DIR="$ROOT_DIR/build/screenshots"
DEFAULT_OUTPUT="$ROOT_DIR/docs/app-store/screenshots"
for arg in "$@"; do
    [[ "$arg" == --portrait ]] && DEFAULT_OUTPUT="$ROOT_DIR/docs/app-store/portrait"
done
OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT}"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"

mkdir -p "$BUILD_DIR"

echo "==> Rendering the app icon..."
"$ICTOOL" "$ROOT_DIR/Resources/AppIcon.icon" \
    --export-image --output-file "$BUILD_DIR/icon.png" \
    --platform macOS --rendition Default --width 512 --height 512 --scale 2 > /dev/null

echo "==> Building the screenshot tool..."
clang -dynamiclib -O2 -Wall "$TOOL_DIR/FixedClock.c" -o "$BUILD_DIR/libFixedClock.dylib"
# All of Encore but its entry point and AppDelegate: the tool is its own app, and must
# never start the clipboard monitor.
SOURCES=()
while IFS= read -r -d '' file; do SOURCES+=("$file"); done < <(
    find "$ROOT_DIR/Sources/Encore" -name '*.swift' ! -name EncoreApp.swift ! -name AppDelegate.swift -print0
)
swiftc -O -parse-as-library -swift-version 5 -target arm64-apple-macosx26.0 \
    -import-objc-header "$TOOL_DIR/VirtualDisplay.h" \
    "${SOURCES[@]}" "$TOOL_DIR"/*.swift \
    -o "$BUILD_DIR/encore-stage" 2>&1 | { grep -v -e "warning:" || true; }

STAGE_HOME="$(mktemp -d -t encore-stage)"
cleanup() {
    rm -rf "$STAGE_HOME"
    # The tool clears its preferences domain on exit; this drops the empty file cfprefsd keeps.
    defaults delete encore-stage > /dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/encore-stage.plist"
}
trap cleanup EXIT
# Seconds from now to 9:41 AM today.
CLOCK_OFFSET=$(( $(date -j -f '%H:%M:%S' '09:41:00' +%s) - $(date +%s) ))

stage() {
    env CFFIXED_USER_HOME="$STAGE_HOME" \
        DYLD_INSERT_LIBRARIES="$BUILD_DIR/libFixedClock.dylib" \
        ENCORE_STAGE_CLOCK_OFFSET="$CLOCK_OFFSET" \
        ENCORE_ICON_PNG="$BUILD_DIR/icon.png" \
        "$BUILD_DIR/encore-stage" "$@" -AppleShowScrollBars WhenScrolling
}

echo "==> Titling the demo history with Apple Intelligence..."
stage prepare

echo "==> Capturing..."
stage capture --out "$OUTPUT_DIR" "$@"
