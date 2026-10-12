#!/bin/bash
# Builds the small Windows helpers the app runs inside its Wine into prebuilt/wintools/:
#   swgl-dpapi.exe   DPAPI for the game's saved password (src/win/swgl-dpapi.c)
#
# Uses the same pinned llvm-mingw as scripts/build-winemac.sh (shared download cache).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

MINGW_URL=https://github.com/mstorsjo/llvm-mingw/releases/download/20261006/llvm-mingw-20261006-ucrt-macos-universal.tar.xz
MINGW_SHA256=a7a19b11048e89372637d26279cdb7c430ed3cf8c1e224310421312bf986ebf6
W="$ROOT/.cache/winemac"
OUT="$ROOT/prebuilt/wintools"

mkdir -p "$W" "$OUT"
if [ ! -d "$W/mingw" ]; then
  curl -fL --progress-bar -o "$W/mingw.tar.xz" "$MINGW_URL"
  echo "$MINGW_SHA256  $W/mingw.tar.xz" | shasum -a 256 -c --quiet
  mkdir "$W/mingw" && tar -xJf "$W/mingw.tar.xz" -C "$W/mingw" --strip-components 1
fi

"$W/mingw/bin/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra -o "$OUT/swgl-dpapi.exe" \
  src/win/swgl-dpapi.c -lcrypt32
echo "Built $OUT/swgl-dpapi.exe"
