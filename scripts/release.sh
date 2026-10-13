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

# Submits $1 and polls Apple until it is processed (retrying through network errors, up to
# 3 hours); prints Apple's log and fails unless it was accepted.
notarize() {
  local id status="" deadline=$((SECONDS + 3 * 3600))
  id="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --output-format json | plutil -extract id raw -)"
  echo "  submission $id"
  while [ "$SECONDS" -lt "$deadline" ]; do
    status="$(xcrun notarytool info "$id" --keychain-profile "$PROFILE" --output-format json 2>/dev/null |
      plutil -extract status raw - 2>/dev/null || true)"
    case "$status" in Accepted|Invalid|Rejected) break ;; esac
    sleep 30
  done
  echo "  status: ${status:-unknown}"
  if [ "$status" != Accepted ]; then
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    exit 1
  fi
}

echo "[release] $VERSION: copying the app"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto "$SRC" "$APP"
xattr -cr "$APP"

# Inside out: every Mach-O file first (except the executables of the bundles signed below),
# then the helper bundles, then the app. Executables get the entitlements of their
# runtime; libraries need none.
echo "[release] signing nested code"
n=0
while IFS= read -r -d '' f; do
  kind="$(file -b "$f")"
  case "$kind" in Mach-O*) ;; *) continue ;; esac
  case "$f" in "$APP/Contents/MacOS/"*|"$APP/Contents/Helpers/"*/Contents/MacOS/*) continue ;; esac
  # Code Apple signed itself (libd3dshared from the Game Porting Toolkit) keeps that signature.
  # (Capture first: with pipefail, grep -q exiting early fails the pipeline and the skip never ran.)
  case "$(codesign -dvv "$f" 2>&1)" in *$'\nAuthority=Software Signing\n'*) continue ;; esac
  case "$kind:$f" in
    *executable*:"$APP/Contents/Resources/wine/"*) sign --entitlements "$ENT/wine.plist" "$f" ;;
    *executable*:"$APP/Contents/Resources/jre/"*) sign --entitlements "$ENT/java.plist" "$f" ;;
    *) sign "$f" ;;
  esac >/dev/null
  n=$((n + 1))
done < <(find "$APP/Contents" -type f -print0)
echo "  $n files"
for helper in "$APP/Contents/Helpers/"*.app; do sign "$helper"; done
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
notarize "$DMG"
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
echo "[release] $DMG ($(du -h "$DMG" | cut -f1))"
