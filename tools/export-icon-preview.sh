#!/bin/bash
# Renders the app icon (Resources/AppIcon.icon) to docs/icon.png for the README, using
# the renderer that ships inside Icon Composer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"

"$ICTOOL" "$ROOT_DIR/Resources/AppIcon.icon" \
    --export-image \
    --output-file "$ROOT_DIR/docs/icon.png" \
    --platform macOS \
    --rendition Default \
    --width 512 --height 512 --scale 1 > /dev/null
echo "Wrote docs/icon.png"
