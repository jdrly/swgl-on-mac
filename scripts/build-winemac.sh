#!/bin/bash
# Rebuilds prebuilt/winemac/winemac.so: Wine's Mac driver from the exact athei/wine
# commit of the bundled Wine, with patches/winemac-*.patch applied (raw mouse while
# the game hides the cursor, stale SetCursorPos handling; see the patch comments).
# Only the x86_64 unix library is built; everything else comes from the release.
#
#   scripts/build-winemac.sh
#
# Needs Xcode Command Line Tools and Homebrew bison (brew install bison).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

WINE_TAG=cx-26.3.0-8
WINE_COMMIT=d23b39774528237cafe49f9a073286f854b779c0   # athei/wine-build release notes for $WINE_TAG
MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/llvm-mingw-20261006-ucrt-macos-universal.tar.xz
MINGW_SHA256=a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6

W="$ROOT/.cache/winemac"
mkdir -p "$W"

if [ ! -d "$W/mingw" ]; then
  curl -fL --progress-bar -o "$W/mingw.tar.xz" "$MINGW_URL"
  echo "$MINGW_SHA256  $W/mingw.tar.xz" | shasum -a 256 -c --quiet
  mkdir "$W/mingw" && tar -xJf "$W/mingw.tar.xz" -C "$W/mingw" --strip-components 1
fi
if [ ! -d "$W/src-$WINE_COMMIT" ]; then
  curl -fL --progress-bar -o "$W/wine-src.tar.gz" "https://codeload.github.com/athei/wine/tar.gz/$WINE_COMMIT"
  mkdir "$W/src-$WINE_COMMIT" && tar -xzf "$W/wine-src.tar.gz" -C "$W/src-$WINE_COMMIT" --strip-components 1
fi

# Fresh, patched copy of the sources.
rm -rf "$W/src" && cp -R "$W/src-$WINE_COMMIT" "$W/src"
for p in patches/winemac-*.patch; do
  patch -d "$W/src" -p1 --quiet <"$p"
done

export MACOSX_DEPLOYMENT_TARGET=26.0
export PATH="$(brew --prefix bison)/bin:$PATH:$W/mingw/bin"
without="--without-freetype --without-gnutls --without-sdl --without-unwind --without-opencl --without-alsa
  --without-capi --without-cups --without-dbus --without-ffmpeg --without-fontconfig --without-gettext
  --without-gphoto --without-gssapi --without-gstreamer --without-hwloc --without-inotify --without-krb5
  --without-netapi --without-oss --without-pcap --without-pcsclite --without-pulse --without-sane
  --without-udev --without-usb --without-v4l2 --without-vulkan --without-wayland --without-x"

# Native (arm64) build tools; the Command Line Tools compiler cannot run under Rosetta.
rm -rf "$W/tools" && mkdir "$W/tools"
( cd "$W/tools" && ../src/configure $without --without-coreaudio >configure.log && make -j"$(sysctl -n hw.ncpu)" __tooldeps__ >make.log )

# Cross build of the x86_64 Mac driver against those tools.
rm -rf "$W/build" && mkdir "$W/build"
( cd "$W/build" &&
  ../src/configure --host=x86_64-apple-darwin --with-wine-tools=../tools --enable-archs=i386,x86_64 \
    --with-mingw --with-coreaudio $without CC="clang -arch x86_64" >configure.log &&
  make -j"$(sysctl -n hw.ncpu)" dlls/winemac.drv/winemac.so >make.log )

mkdir -p prebuilt/winemac
install -m 755 "$W/build/dlls/winemac.drv/winemac.so" prebuilt/winemac/winemac.so
echo "$WINE_TAG" >prebuilt/winemac/wine-tag
echo "Built prebuilt/winemac/winemac.so for $WINE_TAG"
