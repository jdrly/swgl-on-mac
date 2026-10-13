#!/bin/bash
# Builds the d9mt pieces the app ships into prebuilt/d9mt/, from Jan's public fork
# https://github.com/jdrly/d9mt at a pinned commit, with that repo's own "Build" recipe:
#   d3d9.dll         32-bit D3D9 -> Metal driver (PE, i686), stripped
#   d3d9-x64.dll     64-bit driver (PE, x86_64) for 64-bit clients, stripped
#   winemetal32.dll  bridge, PE side (i686)       winemetal64.dll  bridge, PE side (x86_64)
#   winemetal.so     bridge, macOS side (x86_64), includes the AIR shader compiler
#   LICENSE, LICENSES/, THIRD_PARTY_NOTICES.md   (a binary release must carry them)
#
# Needs Homebrew bash, mingw-w64, cmake and ninja (brew install bash mingw-w64 cmake ninja),
# and Xcode for the metal compiler. LLVM 15 is built once into the clone, which takes long;
# D9MT_LLVM=<an llvm-x86_64 install prefix> reuses an existing build instead.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO=https://github.com/jdrly/d9mt.git
COMMIT=fd76b39771878380d2899dedf1cb58569184391b
V="$ROOT/.cache/d9mt"
OUT="$ROOT/prebuilt/d9mt"
export PATH="/opt/homebrew/bin:$PATH"   # the d9mt scripts need bash >= 4.3

[ -d "$V/.git" ] || git clone -q "$REPO" "$V"
if [ "$(git -C "$V" rev-parse HEAD)" != "$COMMIT" ]; then
  [ -z "$(git -C "$V" status --porcelain --untracked-files=no)" ] || { echo "$V has local changes" >&2; exit 1; }
  git -C "$V" fetch -q origin
  git -C "$V" checkout -q --detach "$COMMIT"
  rm -rf "$V/build"  # the build does not track every input change
fi

cd "$V"
scripts/fetch-deps.sh
if [ -n "${D9MT_LLVM:-}" ]; then
  mkdir -p toolchains && ln -sfn "$D9MT_LLVM" toolchains/llvm-x86_64
elif [ ! -f toolchains/llvm-x86_64/lib/libLLVMBitWriter.a ]; then
  scripts/build-llvm-unixside.sh
fi
echo "[d9mt] bridge"
SMOKE=0 scripts/build-bridge.sh >build-bridge.log 2>&1 || { tail -20 build-bridge.log; exit 1; }
echo "[d9mt] driver (i686)"
ARCH=x86 scripts/build-driver.sh >build-driver.log 2>&1 || { tail -20 build-driver.log; exit 1; }
echo "[d9mt] driver (x86_64)"
ARCH=x64 scripts/build-driver.sh >build-driver-x64.log 2>&1 || { tail -20 build-driver-x64.log; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
install -m 644 build/driver/d3d9.dll "$OUT/d3d9.dll"
i686-w64-mingw32-strip "$OUT/d3d9.dll"
install -m 644 build/driver-x64/d3d9.dll "$OUT/d3d9-x64.dll"
x86_64-w64-mingw32-strip "$OUT/d3d9-x64.dll"
install -m 644 build/bridge/winemetal32.dll "$OUT/winemetal32.dll"
install -m 644 build/bridge/winemetal64.dll "$OUT/winemetal64.dll"
install -m 755 build/bridge/winemetal.so "$OUT/winemetal.so"
strip -x "$OUT/winemetal.so"
cp -R LICENSE LICENSES THIRD_PARTY_NOTICES.md "$OUT/"
git rev-parse --short HEAD >"$OUT/VERSION"
echo "[d9mt] prebuilt/d9mt: $(ls "$OUT" | tr '\n' ' ')"
