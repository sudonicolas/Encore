#!/bin/bash
# Builds Encore as a universal (Apple silicon + Intel) release and assembles Encore.app.
#
#   ./build.sh               Local build in build/Encore.app, sandboxed like the store build.
#                            Signed with your Apple Development certificate when there is
#                            one (a stable signature keeps macOS from asking about the app's
#                            data on every rebuild), ad-hoc otherwise. Override with
#                            SIGN_IDENTITY="…".
#   ./build.sh --app-store   Mac App Store build: embeds the provisioning profile, signs for
#                            distribution and wraps the app in build/Encore.pkg, ready to
#                            upload with Transporter. See docs/APP_STORE.md.
#                            Needs APPSTORE_PROFILE=/path/to/profile.provisionprofile.
set -euo pipefail

APP_NAME="Encore"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
PKG_PATH="$ROOT_DIR/build/$APP_NAME.pkg"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icon"
ENTITLEMENTS="$ROOT_DIR/$APP_NAME.entitlements"
INFO_PLIST="$ROOT_DIR/Info.plist"

MODE="local"
case "${1:-}" in
    "") ;;
    --app-store) MODE="app-store" ;;
    *) echo "Usage: $0 [--app-store]" >&2; exit 64 ;;
esac

# First identity whose name starts with one of the given prefixes, if any.
find_identity() {
    local prefix identities
    identities="$(security find-identity -v -p "$1" 2>/dev/null)"
    shift
    for prefix in "$@"; do
        grep -o "\"$prefix[^\"]*\"" <<< "$identities" | head -1 | tr -d '"' && return 0
    done
    return 0
}

if [ "$MODE" = "app-store" ]; then
    PROFILE="${APPSTORE_PROFILE:?Set APPSTORE_PROFILE to your Mac App Store provisioning profile (.provisionprofile)}"
    [ -f "$PROFILE" ] || { echo "No provisioning profile at $PROFILE" >&2; exit 1; }
    APP_IDENTITY="${SIGN_IDENTITY:-$(find_identity codesigning "Apple Distribution" "3rd Party Mac Developer Application")}"
    INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(find_identity basic "3rd Party Mac Developer Installer" "Mac Installer Distribution")}"
    [ -n "$APP_IDENTITY" ] || { echo "No Apple Distribution certificate in the keychain. See docs/APP_STORE.md." >&2; exit 1; }
    [ -n "$INSTALLER_IDENTITY" ] || { echo "No Mac Installer Distribution certificate in the keychain. See docs/APP_STORE.md." >&2; exit 1; }

    # The store build's entitlements must also name the app ID and team from the profile.
    PROFILE_PLIST="$(mktemp -t encore-profile)"
    SIGNING_ENTITLEMENTS="$(mktemp -t encore-entitlements)"
    trap 'rm -f "$PROFILE_PLIST" "$SIGNING_ENTITLEMENTS"' EXIT
    security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
    APP_ID="$(plutil -extract Entitlements.com\\.apple\\.application-identifier raw "$PROFILE_PLIST" 2>/dev/null \
        || plutil -extract Entitlements.application-identifier raw "$PROFILE_PLIST")"
    TEAM_ID="$(plutil -extract Entitlements.com\\.apple\\.developer\\.team-identifier raw "$PROFILE_PLIST")"
    BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
    if [ "$APP_ID" != "$TEAM_ID.$BUNDLE_ID" ]; then
        echo "The profile is for $APP_ID, but the app's bundle ID is $BUNDLE_ID." >&2
        exit 1
    fi
    cp "$ENTITLEMENTS" "$SIGNING_ENTITLEMENTS"
    plutil -insert com\\.apple\\.application-identifier -string "$APP_ID" "$SIGNING_ENTITLEMENTS"
    plutil -insert com\\.apple\\.developer\\.team-identifier -string "$TEAM_ID" "$SIGNING_ENTITLEMENTS"
else
    APP_IDENTITY="${SIGN_IDENTITY:-$(find_identity codesigning "Apple Development")}"
    APP_IDENTITY="${APP_IDENTITY:--}"
    SIGNING_ENTITLEMENTS="$ENTITLEMENTS"
fi

echo "==> Building $APP_NAME (release, universal)..."
swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT_DIR"
BUILD_DIR="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$ROOT_DIR" --show-bin-path)"

echo "==> Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE" "$PKG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
# Privacy manifest (required by the App Store) and the one-time move of pre-sandbox data
# into the app's container.
cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$APP_BUNDLE/Contents/Resources/"
cp "$ROOT_DIR/Resources/container-migration.plist" "$APP_BUNDLE/Contents/Resources/"

# The icon is an Icon Composer document (layered Liquid Glass artwork). actool compiles
# it into Assets.car — which macOS renders live in light, dark, clear and tinted
# appearances — plus an AppIcon.icns fallback.
echo "==> Compiling app icon..."
PARTIAL_PLIST="$(mktemp -t encore-icon)"
ACTOOL_STATUS=0
ACTOOL_OUTPUT="$(xcrun actool "$ICON_SOURCE" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    --output-format human-readable-text \
    --errors --warnings 2>&1)" || ACTOOL_STATUS=$?
rm -f "$PARTIAL_PLIST"
if [ "$ACTOOL_STATUS" -ne 0 ] || grep -qiE "error|warning" <<< "$ACTOOL_OUTPUT"; then
    echo "$ACTOOL_OUTPUT" >&2
    [ "$ACTOOL_STATUS" -eq 0 ] || exit "$ACTOOL_STATUS"
fi

if [ "$MODE" = "app-store" ]; then
    cp -X "$PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
fi

# A downloaded profile carries com.apple.quarantine, and productbuild keeps extended
# attributes in the package, which App Store Connect rejects (ITMS-91109). Strip them all.
xattr -cr "$APP_BUNDLE"

if [ "$APP_IDENTITY" = "-" ]; then
    echo "==> Code signing (ad-hoc, sandboxed)..."
else
    echo "==> Code signing as \"$APP_IDENTITY\" (sandboxed)..."
fi
codesign --force --options runtime --entitlements "$SIGNING_ENTITLEMENTS" --sign "$APP_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

if [ "$MODE" = "app-store" ]; then
    echo "==> Packaging $APP_NAME.pkg..."
    productbuild --component "$APP_BUNDLE" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
    echo "==> Done."
    echo "Installer package: $PKG_PATH"
    echo "Upload it with the Transporter app (free on the Mac App Store). See docs/APP_STORE.md."
else
    echo "==> Done."
    echo "App bundle: $APP_BUNDLE"
    echo "To install: ditto \"$APP_BUNDLE\" /Applications/$APP_NAME.app"
    echo "(To launch at login, the app must be run from a stable location, e.g. /Applications.)"
fi
