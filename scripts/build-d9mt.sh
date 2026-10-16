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
#
# The macOS side targets the app's minimum macOS (MACOS_MIN). The drivers embed each
# metallib twice, for the newest Metal language and a Compat build for MACOS_MIN, and fall
# back to the latter where Metal rejects the newer one; without it macOS 26 shows a black
# screen (#25). The checks below fail the build if that is not the case.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO=https://github.com/jdrly/d9mt.git
COMMIT=159bec7c5f3433cb3273db2ed576464086ac762c
MACOS_MIN=26.0
V="$ROOT/.cache/d9mt"
OUT="$ROOT/prebuilt/d9mt"
export PATH="/opt/homebrew/bin:$PATH"   # the d9mt scripts need bash >= 4.3
export MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN

# newer_than_min <version>: true if it is above MACOS_MIN (trailing ".0"s don't count).
newer_than_min() {
  local v="$1" m="$MACOS_MIN"
  while [[ $v == *.0 ]]; do v="${v%.0}"; done
  while [[ $m == *.0 ]]; do m="${m%.0}"; done
  [ "$v" != "$m" ] && [ "$(printf '%s\n%s\n' "$v" "$m" | sort -V | tail -1)" = "$v" ]
}

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
llvm_min="$(otool -l toolchains/llvm-x86_64/lib/libLLVMSupport.a | awk '/minos/ { print $2 }' | sort -V | tail -1)"
if newer_than_min "$llvm_min"; then
  echo "LLVM in $V/toolchains/llvm-x86_64 is built for macOS $llvm_min, newer than $MACOS_MIN;" >&2
  echo "rebuild it (remove the link or folder and rerun) or set D9MT_LLVM to one built for $MACOS_MIN" >&2
  exit 1
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

so_min="$(vtool -show-build "$OUT/winemetal.so" | awk '/minos/ { print $2 }')"
newer_than_min "$so_min" && { echo "winemetal.so is built for macOS $so_min, newer than $MACOS_MIN" >&2; exit 1; }
# The metallibs embedded in the drivers (fixed function, blit) name their target in the AIR:
# every one for a newer macOS needs a Compat one for MACOS_MIN or older next to it.
for dll in "$OUT/d3d9.dll" "$OUT/d3d9-x64.dll"; do
  newer=0 compat=0
  for t in $(strings -a "$dll" | sed -n 's/.*air64[_a-z0-9]*-apple-macosx\([0-9.]*\).*/\1/p'); do
    if newer_than_min "$t"; then newer=$((newer + 1)); else compat=$((compat + 1)); fi
  done
  if [ "$compat" -eq 0 ] || [ "$compat" -lt "$newer" ]; then
    echo "${dll##*/}: $newer metallibs for macOS newer than $MACOS_MIN but $compat Compat ones" >&2
    exit 1
  fi
done
echo "[d9mt] built for macOS $MACOS_MIN (winemetal.so minos $so_min)"
echo "[d9mt] prebuilt/d9mt: $(ls "$OUT" | tr '\n' ' ')"
