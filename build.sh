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
SPARKLE_VERSION=2.10.0
SPARKLE_URL=https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
# Microsoft's D3DX 9 for 64-bit Windows (d3dx9_31.dll, October 2006) from the DirectX
# End-User Runtime redistributable: SWG Legends' 64-bit client compiles its HLSL shaders with
# it, and Wine's own d3dx9_31 (vkd3d-shader) rejects them (a variable named "point"). It ships
# in the app unmodified (Resources/d3dx9; ensure_d3dx9 in src/common.sh).
DXREDIST_URL=https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe
DXREDIST_SHA256=053f76dcbb28802e23341b6a787e3b0791c0fa5c8d4d011b1044172dbf89c73b
D3DX9_31_SHA256=84167b7df7e97c63f0cc15c1d272cdc7bba942f6f36a8801aec9840825891d0d

# SWGL_VERSION overrides the version for test builds (e.g. two versions to test updates with).
APP_VERSION=${SWGL_VERSION:-0.0.5}
APP_AUTHOR="Jan Drlý / Pharaphobia"
GITHUB_URL=https://github.com/jdrly
REPO_URL=https://github.com/jdrly/swgl-on-mac
CACHE="$ROOT/.cache"
APP="$ROOT/dist/SWGL on Mac.app"

fetch() { # url sha256 -> prints path of the verified download
  local url=$1 sha=$2 dir="$CACHE/$2"
  local file
  file="$dir/$(basename "$url")"
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
# Sparkle (app updates): the framework goes into the app, its tools (generate_appcast,
# BinaryDelta, generate_keys) are used from here by scripts/release.sh.
SPARKLE="$CACHE/sparkle-$SPARKLE_VERSION"
if [ ! -d "$SPARKLE/Sparkle.framework" ]; then
  sparkle_txz=$(fetch "$SPARKLE_URL" "$SPARKLE_SHA256")
  rm -rf "$SPARKLE.part" && mkdir -p "$SPARKLE.part"
  tar -xJf "$sparkle_txz" -C "$SPARKLE.part"
  rm -rf "$SPARKLE" && mv "$SPARKLE.part" "$SPARKLE"
fi
# d3dx9_31.dll out of the redistributable (a cabinet of cabinets; bsdtar reads them).
D3DX="$CACHE/d3dx9_31-$D3DX9_31_SHA256/d3dx9_31.dll"
if [ ! -f "$D3DX" ]; then
  dxredist=$(fetch "$DXREDIST_URL" "$DXREDIST_SHA256")
  rm -rf "$CACHE/d3dx9_31.part" && mkdir -p "$CACHE/d3dx9_31.part"
  tar -xf "$dxredist" -C "$CACHE/d3dx9_31.part" OCT2006_d3dx9_31_x64.cab
  tar -xf "$CACHE/d3dx9_31.part/OCT2006_d3dx9_31_x64.cab" -C "$CACHE/d3dx9_31.part" d3dx9_31.dll
  echo "$D3DX9_31_SHA256  $CACHE/d3dx9_31.part/d3dx9_31.dll" | shasum -a 256 -c --quiet
  mkdir -p "${D3DX%/*}" && mv "$CACHE/d3dx9_31.part/d3dx9_31.dll" "$D3DX"
  rm -rf "$CACHE/d3dx9_31.part"
fi

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
install -m 755 src/collect-logs.sh "$R/collect-logs.sh"
[ -f prebuilt/wintools/swgl-dpapi.exe ] || { echo "Missing prebuilt/wintools; run scripts/build-wintools.sh" >&2; exit 1; }
mkdir -p "$R/tools"
install -m 644 prebuilt/wintools/swgl-dpapi.exe "$R/tools/swgl-dpapi.exe"
# src/java starts the official launcher unchanged (app menu name "Launcher") and loads
# src/native, the app's macOS menus, updates and update window. Needs a JDK for javac and jni.h.
JAVAC=${JAVAC:-}
for c in /opt/homebrew/opt/openjdk/bin/javac "$(/usr/libexec/java_home 2>/dev/null)/bin/javac"; do
  [ -z "$JAVAC" ] && [ -x "$c" ] && JAVAC=$c
done
[ -n "$JAVAC" ] || { echo "No JDK found (javac 9+); set JAVAC=/path/to/javac" >&2; exit 1; }
JDK_INCLUDE="$(cd "$(dirname "$(realpath "$JAVAC")")/../include" && pwd)"

mkdir -p "$R/jre"
tar -xzf "$jre_tgz" -C "$R/jre" --strip-components 1
# AppKit picks the design by the SDK the process's executable was linked against; Zulu's java
# says macOS 11.1, which gave the launcher's About panel, alerts and Sparkle's windows the
# pre-26 look. Claim the current SDK instead (the launcher runs unchanged on it); vtool
# breaks the signature, so sign again (release.sh signs it for real).
java_bin="$R/jre/Contents/Home/bin/java"
xcrun vtool -set-build-version macos 11.0 "$(xcrun --show-sdk-version)" -replace -output "$java_bin.sdk" "$java_bin" 2>/dev/null
mv "$java_bin.sdk" "$java_bin" && chmod 755 "$java_bin"
codesign --force --sign - "$java_bin"
tar -xJf "$wine_txz" -C "$R"
mkdir -p "$R/java"
"$JAVAC" --release 8 -Xlint:-options -encoding UTF-8 -cp "$R/jre/Contents/Home/lib/ext/jfxrt.jar" \
  -d "$R/java" src/java/*.java
# Sparkle is weakly linked: without the framework the menus still work, just without updates.
# The update window is SwiftUI (UpdateWindow.swift): compiled first, for the Objective-C
# header the updater imports, then linked with the rest by swiftc (Swift runtime from the OS).
NB="$CACHE/native-build"
rm -rf "$NB" && mkdir -p "$NB"
swiftc -parse-as-library -O -target arm64-apple-macos26.0 -module-name SWGLMenus -c \
  -o "$NB/UpdateWindow.o" -emit-objc-header-path "$NB/SWGLMenus-Swift.h" src/native/UpdateWindow.swift
for m in swglmenus swglupdates; do
  clang -arch arm64 -mmacosx-version-min=26.0 -fobjc-arc -fmodules -O2 -Wall -c \
    -I"$JDK_INCLUDE" -I"$JDK_INCLUDE/darwin" -I"$NB" -F "$SPARKLE" -o "$NB/$m.o" "src/native/$m.m"
done
swiftc -emit-library -target arm64-apple-macos26.0 -o "$R/java/libswglmenus.dylib" "$NB"/*.o \
  -framework Cocoa -F "$SPARKLE" -Xlinker -weak_framework -Xlinker Sparkle \
  -Xlinker -rpath -Xlinker @loader_path/../../Frameworks
# Sparkle for app updates (src/native/swglupdates.m). Its XPC services are only for sandboxed
# apps; Sparkle's license ships with it.
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/XPCServices" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
mkdir -p "$R/licenses/sparkle"
cp "$SPARKLE/LICENSE" "$R/licenses/sparkle/LICENSE"
# First-run welcome window, SwiftUI (downloads the official launcher; see ensure_launcher in
# src/main.sh). Its own helper bundle, so it does not take over the app's identity.
H="$APP/Contents/Helpers/SWGL on Mac Setup.app/Contents"
mkdir -p "$H/MacOS" "$H/Resources"
swiftc -parse-as-library -O -target arm64-apple-macos26.0 -o "$H/MacOS/SWGLonMacSetup" src/native/Setup.swift
# Settings window, SwiftUI (SWGL on Mac → Settings…): a helper too, since the launcher's Java
# is linked against an old SDK and its windows get the old design.
HS="$APP/Contents/Helpers/SWGL on Mac Settings.app/Contents"
mkdir -p "$HS/MacOS" "$HS/Resources"
swiftc -parse-as-library -O -target arm64-apple-macos26.0 -o "$HS/MacOS/SWGLonMacSettings" src/native/Settings.swift
# Rosetta check, Intel only: opening it makes macOS offer to install Rosetta (ensure_rosetta).
HR="$APP/Contents/Helpers/SWGL on Mac Rosetta Check.app/Contents"
mkdir -p "$HR/MacOS" "$HR/Resources"
clang -arch x86_64 -mmacosx-version-min=26.0 -O2 -Wall -o "$HR/MacOS/SWGLonMacRosettaCheck" src/native/rosetta-check.c
printf 'version=%s\nauthor=%s\ngithub=%s\nrepo=%s\n' "$APP_VERSION" "$APP_AUTHOR" "$GITHUB_URL" "$REPO_URL" >"$R/app.properties"
chmod -R u+w "$R/jre" "$R/wine"
# Drop the Wine SDK (headers, compilers, import libs, conformance tests); the runtime needs none of it.
rm -rf "$R/wine/include" "$R/wine/lib/wine/tests" "$R/wine/share/man"
# d9mt replaces the bundle's D3D9: the 32-bit d3d9.dll goes into the d3d9 tree compatdb
# loads by default (named "mtld3d" in this Wine), marked builtin with the release's own
# winebuild; its winemetal bridge replaces the default winemetal (DXMT keeps its own tree).
D9=prebuilt/d9mt
for f in d3d9.dll d3d9-x64.dll winemetal32.dll winemetal64.dll winemetal.so; do
  [ -f "$D9/$f" ] || { echo "Missing $D9/$f; run scripts/build-d9mt.sh" >&2; exit 1; }
done
W="$R/wine/lib/wine"
install -m 644 "$D9/d3d9.dll" "$W/d3d9/mtld3d/i386-windows/d3d9.dll"
"$R/wine/bin/winebuild" --builtin "$W/d3d9/mtld3d/i386-windows/d3d9.dll"
# 64-bit clients (SWG Legends' 64-bit test client) get d9mt too, not the tree's own mtld3d.
install -m 644 "$D9/d3d9-x64.dll" "$W/d3d9/mtld3d/x86_64-windows/d3d9.dll"
"$R/wine/bin/winebuild" --builtin "$W/d3d9/mtld3d/x86_64-windows/d3d9.dll"
install -m 644 "$D9/winemetal32.dll" "$W/i386-windows/winemetal.dll"
install -m 644 "$D9/winemetal64.dll" "$W/x86_64-windows/winemetal.dll"
install -m 755 "$D9/winemetal.so" "$W/x86_64-unix/winemetal.so"
install -m 644 src/d9mt.conf "$R/d9mt.conf"
# d9mt's licenses and third-party notices must ship with its binaries.
mkdir -p "$R/licenses/d9mt"
cp -R "$D9/LICENSE" "$D9/LICENSES" "$D9/THIRD_PARTY_NOTICES.md" "$R/licenses/d9mt/"
# Microsoft's d3dx9_31 for the 64-bit client (see DXREDIST_URL); the wrapper puts it into the
# prefix. The notice says where it comes from and under which terms it ships.
mkdir -p "$R/d3dx9/x86_64" "$R/licenses/microsoft-d3dx9"
install -m 644 "$D3DX" "$R/d3dx9/x86_64/d3dx9_31.dll"
cat >"$R/licenses/microsoft-d3dx9/NOTICE.txt" <<EOF
d3dx9_31.dll (64-bit, October 2006) is Microsoft's D3DX 9 library,
Copyright (c) Microsoft Corporation. All rights reserved.

It is taken unmodified from Microsoft's DirectX End-User Runtime redistributable
($DXREDIST_URL,
SHA-256 $DXREDIST_SHA256; the file's SHA-256 is $D3DX9_31_SHA256)
and is distributed with SWGL on Mac, which uses it to run SWG Legends' 64-bit game client,
as redistributable code under the terms of Microsoft's DirectX SDK licence. It is not part
of SWGL on Mac's own licence. Microsoft does not endorse or support SWGL on Mac.
EOF
# Mac driver with raw mouse-look and stale SetCursorPos handling (patches/winemac-swg.patch)
# and an input thread fed by GCMouse (patches/winemac-input.patch), built for exactly this
# Wine by scripts/build-winemac.sh.
[ "$WINE_TAG" = "$(cat prebuilt/winemac/wine-tag 2>/dev/null)" ] &&
  [ -f prebuilt/winemac/i386-windows/winemac.drv ] || {
  echo "prebuilt/winemac is not built for $WINE_TAG; run scripts/build-winemac.sh" >&2
  exit 1
}
install -m 755 prebuilt/winemac/winemac.so "$W/x86_64-unix/winemac.so"
for a in i386 x86_64; do
  install -m 644 "prebuilt/winemac/$a-windows/winemac.drv" "$W/$a-windows/winemac.drv"
done
# Game Mode (see enable_game_mode in src/common.sh): the Info.plist of the game bundle the
# wrapper assembles at run time (outside the app, so the app's signature stays intact).
mkdir -p "$R/gamemode"
cat >"$R/gamemode/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>@EXE@</string>
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
# Wine's Windows-side modules ship with full DWARF debug info: ~930 MB of the app, ~370 MB
# without. Crash backtraces still name modules and exports; for source lines, symbolize
# against the pinned release tarball. Homebrew mingw-w64's strip, per architecture (it keeps
# the "Wine builtin DLL" marker); files that are not PE are left alone.
for arch in i386:i686 x86_64:x86_64; do
  find "$R/wine/lib/wine" -path "*/${arch%%:*}-windows/*" -type f -print0 |
    xargs -0 -n 64 "/opt/homebrew/bin/${arch##*:}-w64-mingw32-strip" --strip-debug 2>/dev/null || true
done
# Apple's D3DMetal (Direct3D 11/12 via the Game Porting Toolkit) and the DXGI tree that uses it:
# SWG is Direct3D 9 on d9mt, so it is never loaded, and it is Apple's to distribute.
# libd3dshared.dylib stays (ntdll loads it at startup), with its license.
rm -rf "$R/wine/lib/external/D3DMetal.framework" "$R/wine/lib/wine/dxgi/gptk"


printf 'wine %s\njre %s\nd9mt %s\nsparkle %s\napp %s\n' "$WINE_TAG" "$(basename "$JRE_URL" .tar.gz)" \
  "$(tr '\n' ' ' <"$D9/VERSION")" "$SPARKLE_VERSION" "$APP_VERSION" >"$R/VERSIONS"

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
# helper_plist <Contents dir> <executable> <bundle ID suffix> [extra plist lines]
helper_plist() {
  cp "$R/AppIcon.icns" "$1/Resources/AppIcon.icns"
  cat >"$1/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>$2</string>
	<key>CFBundleIdentifier</key><string>io.github.jdrly.swglonmac.$3</string>
	<key>CFBundleName</key><string>SWGL on Mac</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
	<key>CFBundleVersion</key><string>$APP_VERSION</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>NSHighResolutionCapable</key><true/>${4:-}
</dict>
</plist>
EOF
  plutil -lint -s "$1/Info.plist"
}
helper_plist "$H" SWGLonMacSetup setup
# An accessory app: no Dock icon, and the launcher's menus stay in the menu bar.
helper_plist "$HS" SWGLonMacSettings settings $'\n\t<key>LSUIElement</key><true/>'
helper_plist "$HR" SWGLonMacRosettaCheck rosetta-check $'\n\t<key>LSUIElement</key><true/>'

xattr -cr "$APP"
# Sparkle without its XPC services no longer matches its own signature (release.sh signs it
# for real, in the same order).
fw="$APP/Contents/Frameworks/Sparkle.framework"
for f in "$fw/Versions/B/Autoupdate" "$fw/Versions/B/Updater.app" "$fw"; do
  codesign --force --sign - "$f" 2>/dev/null || echo "note: ad-hoc signing of $f skipped" >&2
done
for helper in "$APP/Contents/Helpers/"*.app; do
  codesign --force --sign - "$helper" 2>/dev/null || echo "note: ad-hoc signing of $(basename "$helper") skipped" >&2
done
codesign --force --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing skipped" >&2
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = --install ]; then
  rm -rf "/Applications/SWGL on Mac.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/SWGL on Mac.app"
fi
