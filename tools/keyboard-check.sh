#!/bin/bash
# Checks the popover's keyboard against the real built app: Return copies, Escape peels
# back one layer at a time, and neither stops working after a copy, a click, the hover
# preview, or ten opens in a row.
#
#   tools/keyboard-check.sh [path/to/Encore.app]
#
# Defaults to build/Encore.app. Quits any running Encore, launches the one under test,
# and leaves it running.
#
# Needs Accessibility permission for whatever runs it (Terminal, iTerm, your editor):
# System Settings → Privacy & Security → Accessibility. The driver says so and stops if
# the permission is missing, rather than failing every check for the wrong reason.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT_DIR/build/Encore.app}"
DRIVER="$ROOT_DIR/tools/keyboard-check.swift"
BINARY="${TMPDIR:-/tmp}/encore-keyboard-check"

[ -d "$APP" ] || { echo "No app at $APP. Run ./build.sh first." >&2; exit 1; }

# Rebuilt only when the driver has changed.
if [ ! -x "$BINARY" ] || [ "$DRIVER" -nt "$BINARY" ]; then
    echo "==> Compiling the driver..."
    swiftc -O -o "$BINARY" "$DRIVER"
fi

echo "==> Launching $APP..."
osascript -e 'quit app "Encore"' >/dev/null 2>&1 || true
pkill -x Encore >/dev/null 2>&1 || true
sleep 1
open -a "$APP"
# Give the status item and the clipboard store time to come up.
sleep 2.5

echo "==> Checks"
"$BINARY"
