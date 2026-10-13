#!/bin/bash
# Signs, notarizes and packages dist/SWGL on Mac.app (run ./build.sh first), and prepares the
# update feed for Sparkle (src/native/swglupdates.m):
#   release/<version>/SWGL on Mac.app                   Developer ID, hardened runtime
#   release/<version>/SWGL-on-Mac-<version>.dmg         signed, notarized, stapled
#   release/<version>/SWGL-on-Mac-<version>-from-<old>.delta   delta updates from older versions
#   release/<version>/appcast.xml                       the feed, with only this version
#   release/updates/                                    DMGs of this and the 5 previous versions
# then creates a draft GitHub release v<version> with the DMG, the deltas and appcast.xml.
# Publishing the draft makes the update live: the app reads
# https://github.com/jdrly/swgl-on-mac/releases/latest/download/appcast.xml.
#
# One notarization: submitting the disk image notarizes the app inside it too (Gatekeeper
# looks its ticket up online when the app is first opened); the ticket is stapled to the DMG.
#
# Needs the Developer ID Application identity in the keychain, a notarytool keychain profile
# (xcrun notarytool store-credentials swgl-notary --key … --key-id … --issuer …), Sparkle's
# EdDSA key in the login keychain (Sparkle's generate_keys; build.sh unpacks the tools into
# .cache/sparkle-<version>/bin), gh logged in, and release notes in Markdown at
# release-notes/<version>.md (they go into the appcast and the GitHub release).
#
#   scripts/release.sh               sign, notarize, package, feed, draft release
#   scripts/release.sh --sign-only   sign and verify only (for testing the signed app locally)
#   scripts/release.sh --no-notarize sign, package and build the feed, without notarizing or a
#                                    GitHub release (local dry runs and update tests)
#
# Overrides: IDENTITY, NOTARY_PROFILE; RELEASE_DIR (default release), DOWNLOAD_URL_PREFIX
# (where the appcast points, default the version's GitHub release), ED_KEY_FILE (a private
# EdDSA key file instead of the keychain, for test keys), RELEASE_NOTES (the notes file).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
case "$MODE" in ""|--sign-only|--no-notarize) ;; *) echo "unknown option: $MODE" >&2; exit 2 ;; esac
IDENTITY="${IDENTITY:-Developer ID Application: Jan Drly (3JT82CY6ZK)}"
PROFILE="${NOTARY_PROFILE:-swgl-notary}"
REPO=jdrly/swgl-on-mac
SRC="dist/SWGL on Mac.app"
ENT="$PWD/src/entitlements"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist")"
RELEASE_DIR="${RELEASE_DIR:-release}"
OUT="$RELEASE_DIR/$VERSION"
UPDATES="$RELEASE_DIR/updates"
APP="$OUT/SWGL on Mac.app"
DMG="$OUT/SWGL-on-Mac-$VERSION.dmg"
NOTES="${RELEASE_NOTES:-release-notes/$VERSION.md}"
URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"
FW_REL="Contents/Frameworks/Sparkle.framework"
SPARKLE_BIN="$PWD/.cache/sparkle-$(plutil -extract CFBundleShortVersionString raw "$SRC/$FW_REL/Resources/Info.plist")/bin"

if [ "$MODE" != --sign-only ]; then
  [ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Missing $SPARKLE_BIN; run ./build.sh" >&2; exit 1; }
  if [ ! -f "$NOTES" ]; then
    [ "$MODE" = --no-notarize ] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
    echo "[release] note: no release notes ($NOTES)"
  fi
  if [ -z "$MODE" ]; then
    gh auth status >/dev/null 2>&1 || { echo "gh is not logged in" >&2; exit 1; }
    ! gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 || { echo "Release v$VERSION already exists" >&2; exit 1; }
  fi
fi

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

# Inside out: every Mach-O file first (except the executables of the bundles signed below,
# and Sparkle, signed after), then Sparkle in its documented order, then the setup helper
# bundle, then the app. Executables get the entitlements of their runtime; libraries need none.
echo "[release] signing nested code"
n=0
while IFS= read -r -d '' f; do
  case "$f" in "$APP/Contents/MacOS/"*|"$APP/Contents/Helpers/"*/Contents/MacOS/*|"$APP/Contents/Frameworks/"*) continue ;; esac
  kind="$(file -b "$f")"
  case "$kind" in Mach-O*) ;; *) continue ;; esac
  # Code Apple signed itself (libd3dshared from the Game Porting Toolkit) keeps that signature.
  codesign -dvv "$f" 2>&1 | grep -q '^Authority=Software Signing$' && continue
  case "$kind:$f" in
    *executable*:"$APP/Contents/Resources/wine/"*) sign --entitlements "$ENT/wine.plist" "$f" ;;
    *executable*:"$APP/Contents/Resources/jre/"*) sign --entitlements "$ENT/java.plist" "$f" ;;
    *) sign "$f" ;;
  esac >/dev/null
  n=$((n + 1))
done < <(find "$APP/Contents" -type f -print0)
echo "  $n files"
# Sparkle without its XPC services (build.sh removes them): Autoupdate, Updater.app, then the
# framework, each with the hardened runtime and no --deep.
fw="$APP/$FW_REL"
sign "$fw/Versions/B/Autoupdate"
sign "$fw/Versions/B/Updater.app"
sign "$fw"
sign "$APP/Contents/Helpers/SWGL on Mac Setup.app"
sign "$APP"
codesign --verify --strict --deep "$APP"
echo "[release] signature verified: $(codesign -dvv "$APP" 2>&1 | grep -E '^Authority=Developer ID Application' | cut -d= -f2)"
[ "$MODE" = --sign-only ] && exit 0

echo "[release] building the disk image"
stage="$OUT/dmg"
mkdir -p "$stage"
ditto "$APP" "$stage/SWGL on Mac.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "SWGL on Mac $VERSION" -srcfolder "$stage" -fs HFS+ -format ULMO "$DMG"
rm -rf "$stage"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
if [ "$MODE" = --no-notarize ]; then
  echo "[release] not notarized (--no-notarize)"
else
  echo "[release] notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
fi

# The update feed. release/updates keeps the DMGs of this and the 5 previous versions, the
# bases of the delta updates. generate_appcast runs on a copy of them, so the feed starts
# afresh every time and holds only this version (it would rewrite older entries' URLs to
# this release's).
echo "[release] building the update feed"
mkdir -p "$UPDATES"
rm -f "$UPDATES/${DMG##*/}"
cp -c "$DMG" "$UPDATES/"
kept=($(ls "$UPDATES" | sed -n 's/^SWGL-on-Mac-\(.*\)\.dmg$/\1/p' | sort -V))
for ((i = 0; i < ${#kept[@]} - 6; i++)); do rm -f "$UPDATES/SWGL-on-Mac-${kept[i]}.dmg"; done
feed="$OUT/feed"
rm -rf "$feed"
mkdir -p "$feed"
cp -c "$UPDATES"/SWGL-on-Mac-*.dmg "$feed/"
[ -f "$NOTES" ] && cp "$NOTES" "$feed/SWGL-on-Mac-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" ${ED_KEY_FILE:+--ed-key-file "$ED_KEY_FILE"} \
  --maximum-versions 1 --maximum-deltas 5 --embed-release-notes \
  --download-url-prefix "$URL_PREFIX" "$feed"
# Deltas are named "SWGL on Mac<new>-<old>.delta"; GitHub replaces spaces in asset names, so
# rename them and their URLs. (The appcast itself is not signed, so it may be edited.)
cp "$feed/appcast.xml" "$OUT/appcast.xml"
deltas=()
for d in "$feed"/*.delta; do
  [ -e "$d" ] || continue
  pair="${d##*/SWGL on Mac}"; pair="${pair%.delta}"   # <new>-<old>
  new="${pair%%-*}"; old="${pair#*-}"
  name="SWGL-on-Mac-$new-from-$old.delta"
  mv "$d" "$OUT/$name"
  sed -i '' "s|SWGL%20on%20Mac$new-$old\.delta\"|$name\"|" "$OUT/appcast.xml"
  deltas+=("$OUT/$name")
done
rm -rf "$feed"
xmllint --noout "$OUT/appcast.xml"
! grep -q 'SWGL%20on%20Mac' "$OUT/appcast.xml" || { echo "appcast.xml still names unrenamed deltas" >&2; exit 1; }
echo "  $OUT/appcast.xml, ${#deltas[@]} delta(s)"

# Check the feed as Sparkle will: lengths and EdDSA signatures against the app's public key.
echo "[release] checking the update feed"
swift scripts/check-appcast.swift "$OUT/appcast.xml" "$OUT" \
  "$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist")"
# Apply every delta to the app of its old version, which must give this version's app with
# a valid signature (BinaryDelta checks the result against the hash in the delta).
for d in ${deltas[@]+"${deltas[@]}"}; do
  old="${d##*-from-}"; old="${old%.delta}"
  mnt="$(mktemp -d)"; tmp="$(mktemp -d "$OUT/delta-check.XXXXXX")"
  # diskutil image (macOS 27) replaces the deprecated hdiutil attach.
  if diskutil image attach --readOnly --nobrowse --mountPoint "$mnt" "$UPDATES/SWGL-on-Mac-$old.dmg" >/dev/null 2>&1; then :
  else hdiutil attach -quiet -readonly -nobrowse -noverify -mountpoint "$mnt" "$UPDATES/SWGL-on-Mac-$old.dmg"; fi
  ok=1
  "$SPARKLE_BIN/BinaryDelta" apply "$mnt/SWGL on Mac.app" "$tmp/SWGL on Mac.app" "$d" >/dev/null &&
    codesign --verify --strict --deep "$tmp/SWGL on Mac.app" &&
    [ "$(plutil -extract CFBundleShortVersionString raw "$tmp/SWGL on Mac.app/Contents/Info.plist")" = "$VERSION" ] || ok=0
  hdiutil detach -quiet "$mnt" || hdiutil detach -quiet -force "$mnt"
  rm -rf "$tmp" "$mnt"
  [ "$ok" = 1 ] || { echo "Delta ${d##*/} does not apply to $old" >&2; exit 1; }
  echo "  ${d##*/}: applies to $old, signature valid"
done

if [ "$MODE" = --no-notarize ]; then
  echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); no GitHub release (--no-notarize)"
  exit 0
fi

echo "[release] creating the draft GitHub release v$VERSION"
gh release create "v$VERSION" --repo "$REPO" --draft --title "SWGL on Mac $VERSION" \
  --notes-file "$NOTES" "$DMG" ${deltas[@]+"${deltas[@]}"} "$OUT/appcast.xml"
echo "[release] $DMG ($(du -h "$DMG" | cut -f1)); publish the draft to make the update live"
