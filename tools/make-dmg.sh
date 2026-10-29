#!/bin/bash
# Packs a built Encore.app into a drag-to-install disk image.
#
#   tools/make-dmg.sh build/Encore.app build/Encore.dmg [--first-launch-note]
#
# The image opens to a 660 x 420 pt window (plus the title bar) with Encore on the left, an Applications shortcut on the right
# and an arrow between them. --first-launch-note adds the "Open Anyway" steps to the
# backdrop, for an app that isn't notarized. build.sh --dmg calls this.
set -euo pipefail

APP="${1:?Usage: $0 Encore.app Encore.dmg [--first-launch-note]}"
DMG="${2:?Usage: $0 Encore.app Encore.dmg [--first-launch-note]}"
NOTE="${3:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOLUME="Encore"
APP_NAME="$(basename "$APP")"

WORK="$(mktemp -d -t encore-dmg)"
MOUNT="/Volumes/$VOLUME"
cleanup() {
    hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# A leftover mount from an interrupted run would make this one attach as "Encore 1".
hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

python3 "$HERE/dmg/make-background.py" "$WORK/background" $NOTE
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"

echo "==> Laying out the install window (Finder may ask to be controlled)..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 568}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 120
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$APP_NAME" of container window to {180, 200}
        set position of item "Applications" of container window to {480, 200}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# The mounted volume wears the app's icon. (Added after the layout: Finder drops it if it
# is already there when the window is set up.)
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
    xcrun SetFile -a C "$MOUNT"
fi

# Let Finder write .DS_Store before the volume goes away.
sync
sleep 2
hdiutil detach "$MOUNT" -quiet

rm -f "$DMG"
hdiutil convert "$WORK/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$DMG"
echo "Disk image: $DMG"
