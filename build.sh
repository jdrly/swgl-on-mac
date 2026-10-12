#!/bin/bash
# Builds "dist/SWGL on Mac.app": native arm64 Java 8 + JavaFX for the official
# launcher, and a WoW64 Wine (CrossOver 26 based, with x87sidecar for fast x87
# under Rosetta) running the game client on d9mt (D3D9 -> Metal).
#
# d9mt comes from prebuilt/d9mt (scripts/build-d9mt.sh).
#
#   ./build.sh                 build into dist/
#   ./build.sh --install       also copy the app to /Applications
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

# Pinned dependencies. Bump the version and sha256 together.
JRE_URL=https://cdn.azul.com/zulu/bin/zulu8.96.0.205-ca-fx-jre8.0.504-macosx_aarch64.tar.gz
JRE_SHA256=97d384e8ed02b5042c51fd19c94e2b8c33070ab913a24d1f7ab8e376e816fc16
WINE_TAG=cx-26.3.0-8
WINE_URL=https://github.com/athei/wine-build/releases/download/$WINE_TAG/wine-$WINE_TAG-macos-x86_64.tar.xz
WINE_SHA256=1976c3310a1f8be2f8e9a46fcb524f77b4316df3d281d94af2c8542bef60456d

APP_VERSION=0.0.1
APP_AUTHOR="Jan Drlý / Pharaphobia"
GITHUB_URL=https://github.com/jdrly
REPO_URL=https://github.com/jdrly/swgl-on-mac
CACHE="$ROOT/.cache"
APP="$ROOT/dist/SWGL on Mac.app"

fetch() { # url sha256 -> prints path of the verified download
  local url=$1 sha=$2 dir="$CACHE/$2"
  local file="$dir/$(basename "$url")"
  if [ ! -f "$file" ]; then
    mkdir -p "$dir"
    echo "Downloading $url" >&2
    curl -fL --progress-bar -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | shasum -a 256 -c --quiet >&2
  echo "$file"
}

jre_tgz=$(fetch "$JRE_URL" "$JRE_SHA256")
wine_txz=$(fetch "$WINE_URL" "$WINE_SHA256")

echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"
R="$APP/Contents/Resources"

sed "s/@VERSION@/$APP_VERSION/g" src/Info.plist >"$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"
# The main executable is a small native launcher that runs Resources/main.sh (signable with
# the hardened runtime, unlike a script).
clang -arch arm64 -mmacosx-version-min=26.0 -O2 -Wall -o "$APP/Contents/MacOS/SWGLonMac" src/native/launcher.c
install -m 755 src/main.sh "$R/main.sh"
install -m 644 src/common.sh "$R/common.sh"
install -m 755 src/wine-shim.sh "$R/bin/wine"
install -m 755 src/relaunch-shim.sh "$R/bin/SWGLegendsLauncher.exe"
install -m 755 src/settings.sh "$R/settings.sh"
[ -f prebuilt/wintools/swgl-dpapi.exe ] || { echo "Missing prebuilt/wintools; run scripts/build-wintools.sh" >&2; exit 1; }
mkdir -p "$R/tools"
install -m 644 prebuilt/wintools/swgl-dpapi.exe "$R/tools/swgl-dpapi.exe"
# src/java starts the official launcher unchanged (app menu name "Launcher") and loads
# src/native, the app's macOS menus (About, Features). Needs a JDK for javac and jni.h.
JAVAC=${JAVAC:-}
for c in /opt/homebrew/opt/openjdk/bin/javac "$(/usr/libexec/java_home 2>/dev/null)/bin/javac"; do
  [ -z "$JAVAC" ] && [ -x "$c" ] && JAVAC=$c
done
[ -n "$JAVAC" ] || { echo "No JDK found (javac 9+); set JAVAC=/path/to/javac" >&2; exit 1; }
JDK_INCLUDE="$(cd "$(dirname "$(realpath "$JAVAC")")/../include" && pwd)"

mkdir -p "$R/jre"
tar -xzf "$jre_tgz" -C "$R/jre" --strip-components 1
tar -xJf "$wine_txz" -C "$R"
mkdir -p "$R/java"
"$JAVAC" --release 8 -Xlint:-options -encoding UTF-8 -cp "$R/jre/Contents/Home/lib/ext/jfxrt.jar" \
  -d "$R/java" src/java/*.java
clang -arch arm64 -mmacosx-version-min=26.0 -fobjc-arc -O2 -dynamiclib -Wall \
  -I"$JDK_INCLUDE" -I"$JDK_INCLUDE/darwin" -framework Cocoa \
  -o "$R/java/libswglmenus.dylib" src/native/swglmenus.m
# First-run welcome window, SwiftUI (downloads the official launcher; see ensure_launcher in
# src/main.sh). Its own helper bundle, so it does not take over the app's identity.
H="$APP/Contents/Helpers/SWGL on Mac Setup.app/Contents"
mkdir -p "$H/MacOS" "$H/Resources"
swiftc -parse-as-library -O -target arm64-apple-macos26.0 -o "$H/MacOS/SWGLonMacSetup" src/native/Setup.swift
printf 'version=%s\nauthor=%s\ngithub=%s\nrepo=%s\n' "$APP_VERSION" "$APP_AUTHOR" "$GITHUB_URL" "$REPO_URL" >"$R/app.properties"
chmod -R u+w "$R/jre" "$R/wine"
# Drop the Wine SDK (headers, compilers, import libs, conformance tests); the runtime needs none of it.
rm -rf "$R/wine/include" "$R/wine/lib/wine/tests" "$R/wine/share/man"
# d9mt replaces the bundle's D3D9: the 32-bit d3d9.dll goes into the d3d9 tree compatdb
# loads by default (named "mtld3d" in this Wine), marked builtin with the release's own
# winebuild; its winemetal bridge replaces the default winemetal (DXMT keeps its own tree).
D9=prebuilt/d9mt
for f in d3d9.dll winemetal32.dll winemetal64.dll winemetal.so; do
  [ -f "$D9/$f" ] || { echo "Missing $D9/$f; run scripts/build-d9mt.sh" >&2; exit 1; }
done
W="$R/wine/lib/wine"
install -m 644 "$D9/d3d9.dll" "$W/d3d9/mtld3d/i386-windows/d3d9.dll"
"$R/wine/bin/winebuild" --builtin "$W/d3d9/mtld3d/i386-windows/d3d9.dll"
install -m 644 "$D9/winemetal32.dll" "$W/i386-windows/winemetal.dll"
install -m 644 "$D9/winemetal64.dll" "$W/x86_64-windows/winemetal.dll"
install -m 755 "$D9/winemetal.so" "$W/x86_64-unix/winemetal.so"
install -m 644 src/d9mt.conf "$R/d9mt.conf"
# d9mt's licenses and third-party notices must ship with its binaries.
mkdir -p "$R/licenses/d9mt"
cp -R "$D9/LICENSE" "$D9/LICENSES" "$D9/THIRD_PARTY_NOTICES.md" "$R/licenses/d9mt/"
# Mac driver with raw mouse-look and stale SetCursorPos handling (patches/winemac-swg.patch),
# built for exactly this Wine by scripts/build-winemac.sh.
[ "$WINE_TAG" = "$(cat prebuilt/winemac/wine-tag 2>/dev/null)" ] || {
  echo "prebuilt/winemac is not built for $WINE_TAG; run scripts/build-winemac.sh" >&2
  exit 1
}
install -m 755 prebuilt/winemac/winemac.so "$W/x86_64-unix/winemac.so"
# Game Mode (see enable_game_mode in src/common.sh): the Info.plist of the game bundle the
# wrapper assembles at run time (outside the app, so the app's signature stays intact).
mkdir -p "$R/gamemode"
cat >"$R/gamemode/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>SwgClient_r.exe</string>
	<key>CFBundleIdentifier</key><string>io.github.jdrly.swglonmac.game</string>
	<key>CFBundleName</key><string>SWGL on Mac</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
	<key>CFBundleVersion</key><string>$APP_VERSION</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.role-playing-games</string>
	<key>LSSupportsGameMode</key><true/>
	<key>GCSupportsGameMode</key><true/>
</dict>
</plist>
EOF
plutil -lint -s "$R/gamemode/Info.plist"
( cd "$R/wine/bin" && rm -f function_grep.pl widl winebuild winecpp winedump wineg++ winegcc winemaker wmc wrc )
find "$R/wine/lib/wine" -name '*.a' -delete


printf 'wine %s\njre %s\nd9mt %s\napp %s\n' "$WINE_TAG" "$(basename "$JRE_URL" .tar.gz)" \
  "$(tr '\n' ' ' <"$D9/VERSION")" "$APP_VERSION" >"$R/VERSIONS"

iconset="$CACHE/AppIcon.iconset"
rm -rf "$iconset"
# The icon is the logo from SWGL's launcher (its download is cached; not shipped in the app).
launcher_zip="$CACHE/launcher/SWGLegendsLauncher.zip"
[ -f "$launcher_zip" ] || { mkdir -p "$CACHE/launcher"; curl -fL --progress-bar -o "$launcher_zip.part" \
  "$(sed -n 's/^LAUNCHER_ZIP_URL=//p' src/common.sh)" && mv "$launcher_zip.part" "$launcher_zip"; }
unzip -p "$launcher_zip" SWGLegendsLauncher.exe >"$CACHE/launcher/SWGLegendsLauncher.exe"
unzip -p "$CACHE/launcher/SWGLegendsLauncher.exe" launcher/images/logo.png >"$CACHE/logo.png" 2>/dev/null || true
swift src/make-icon.swift "$CACHE/logo.png" "$iconset"
iconutil -c icns "$iconset" -o "$R/AppIcon.icns"
cp "$R/AppIcon.icns" "$H/Resources/AppIcon.icns"
cat >"$H/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>SWGLonMacSetup</string>
	<key>CFBundleIdentifier</key><string>io.github.jdrly.swglonmac.setup</string>
	<key>CFBundleName</key><string>SWGL on Mac</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
	<key>CFBundleVersion</key><string>$APP_VERSION</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
plutil -lint -s "$H/Info.plist"

xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Helpers/SWGL on Mac Setup.app" 2>/dev/null || echo "note: ad-hoc signing of the setup helper skipped" >&2
codesign --force --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing skipped" >&2
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = --install ]; then
  rm -rf "/Applications/SWGL on Mac.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/SWGL on Mac.app"
fi
