#!/bin/bash
# Signs, notarizes and packages dist/SWGL on Mac.app (run ./build.sh first):
#   release/<version>/SWGL on Mac.app                 Developer ID, hardened runtime
#   release/<version>/SWGL-on-Mac-<version>.dmg       signed, notarized, stapled
# One notarization: submitting the disk image notarizes the app inside it too (Gatekeeper
# looks its ticket up online when the app is first opened); the ticket is stapled to the DMG.
#
# Needs the Developer ID Application identity in the keychain and a notarytool keychain
# profile (xcrun notarytool store-credentials swgl-notary --key … --key-id … --issuer …).
#
#   scripts/release.sh              sign, notarize, package
#   scripts/release.sh --sign-only  sign and verify only (for testing the signed app locally)
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${IDENTITY:-Developer ID Application: Jan Drly (3JT82CY6ZK)}"
PROFILE="${NOTARY_PROFILE:-swgl-notary}"
SRC="dist/SWGL on Mac.app"
ENT="$PWD/src/entitlements"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist")"
OUT="release/$VERSION"
APP="$OUT/SWGL on Mac.app"
DMG="$OUT/SWGL-on-Mac-$VERSION.dmg"

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

echo "[release] $VERSION: copying the app"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto "$SRC" "$APP"
xattr -cr "$APP"

# Inside out: every Mach-O file first (except the executables of the bundles signed below),
# then the setup helper bundle, then the app. Executables get the entitlements of their
# runtime; libraries need none.
echo "[release] signing nested code"
n=0
while IFS= read -r -d '' f; do
  kind="$(file -b "$f")"
  case "$kind" in Mach-O*) ;; *) continue ;; esac
  case "$f" in "$APP/Contents/MacOS/"*|"$APP/Contents/Helpers/"*/Contents/MacOS/*) continue ;; esac
  case "$kind:$f" in
    *executable*:"$APP/Contents/Resources/wine/"*) sign --entitlements "$ENT/wine.plist" "$f" ;;
    *executable*:"$APP/Contents/Resources/jre/"*) sign --entitlements "$ENT/java.plist" "$f" ;;
    *) sign "$f" ;;
  esac >/dev/null
  n=$((n + 1))
done < <(find "$APP/Contents" -type f -print0)
echo "  $n files"
sign "$APP/Contents/Helpers/SWGL on Mac Setup.app"
sign "$APP"
codesign --verify --strict --deep "$APP"
echo "[release] signature verified: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Developer ID Application' | cut -d= -f2)"
[ "${1:-}" = --sign-only ] && exit 0

echo "[release] building the disk image"
stage="$OUT/dmg"
mkdir -p "$stage"
ditto "$APP" "$stage/SWGL on Mac.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "SWGL on Mac $VERSION" -srcfolder "$stage" -fs HFS+ -format ULMO "$DMG"
rm -rf "$stage"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "[release] notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json >"$OUT/notary.json" || true
status="$(plutil -extract status raw "$OUT/notary.json")"
if [ "$status" != Accepted ]; then
  echo "notarization: $status" >&2
  xcrun notarytool log "$(plutil -extract id raw "$OUT/notary.json")" --keychain-profile "$PROFILE" >&2
  exit 1
fi
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
echo "[release] $DMG ($(du -h "$DMG" | cut -f1))"
