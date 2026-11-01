#!/bin/bash
# Checks the AIR version tag on the shaders the prebuilt d9mt compiles while the game runs
# (#40). Metal treats a metallib's VERS tag as its deployment target, and macOS 26 accepts up to
# AIR 2.8: a d9mt that tags 2.9 there leaves the game black after its first loading screen.
# A small x86_64 harness (test-d9mt-air/air-check.m) compiles two shaders through
# prebuilt/d9mt/winemetal.so, as d3d9.dll does, in three modes:
#   D9MT_AIR_MACOS=26   every function is tagged AIR 2.7 and loads in Metal
#   D9MT_AIR_MACOS=27   AIR 2.9; it must load on macOS 27 and later
#   unset               the tag for the macOS this runs on (before 27: 2.7), and it loads
# and d9mt's log names its choice (d9mt: AIR metallibs tagged for macOS <n>).
# Needs Xcode's clang and Rosetta. Without a Metal device the loads are skipped.
#
# The .ir files are d9mt's test shaders air/tests/asm/vs_mvp.asm and ps_texld.asm, converted to
# the IR the driver hands the bridge. If a new pin cannot read them (compile status 1), make them
# again from that d9mt checkout, after scripts/build-d9mt.sh:
#   cd .cache/d9mt && clang++ -std=c++17 -O2 -arch x86_64 -Ithird_party/dxbc-spirv -I. \
#     -Itoolchains/llvm-x86_64/include ../../scripts/test-d9mt-air/dump-ir.cpp \
#     $(ls build/airlib/obj/*.o | grep -v 'air_air_\|unix\|loopback') -o /tmp/dump-ir
#   /tmp/dump-ir air/tests/bin/vs_mvp.bin ../../scripts/test-d9mt-air/vs_mvp.ir   (and ps_texld)
set -u
cd "$(dirname "$0")/.." || exit 1
SO="${D9MT_SO:-prebuilt/d9mt/winemetal.so}"
DIR=scripts/test-d9mt-air
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

arch -x86_64 /usr/bin/true 2>/dev/null || { echo "FAIL  needs Rosetta (winemetal.so is x86_64)"; exit 1; }
clang -arch x86_64 -fobjc-arc -O2 -Wall -Werror -framework Foundation -framework Metal \
  "$DIR/air-check.m" -o "$WORK/air-check" || { echo "FAIL  building the harness"; exit 1; }
host="$(sw_vers -productVersion | cut -d. -f1)"
host_air=2.7; [ "$host" -ge 27 ] && host_air=2.9
echo "$SO (d9mt $(cat "$(dirname "$SO")/VERSION" 2>/dev/null || echo '?')), macOS $(sw_vers -productVersion)"

failures=0
# run <shader> <D9MT_AIR_MACOS, empty for unset> <expected AIR> <must load: 1|0>
run() {
  local out tags log load what status
  if [ -n "$2" ]; then
    out="$(D9MT_AIR_MACOS="$2" "$WORK/air-check" "$SO" "$DIR/$1.ir" "$WORK/$1.metallib" --load 2>"$WORK/err")"
  else
    out="$(env -u D9MT_AIR_MACOS "$WORK/air-check" "$SO" "$DIR/$1.ir" "$WORK/$1.metallib" --load 2>"$WORK/err")"
  fi
  status=$?
  tags="$(printf '%s\n' "$out" | sed -n 's/^VERS \([0-9]*\.[0-9]*\)\/.*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')"
  log="$(grep -o 'd9mt: AIR metallibs tagged for macOS [0-9]*' "$WORK/err" | head -1)"
  load="$(printf '%s\n' "$out" | grep '^load' | head -1)"
  what="$1, D9MT_AIR_MACOS=${2:-(unset)}: VERS ${tags:-none}; ${load:-$(tail -1 "$WORK/err")}"
  if [ "$tags" != "$3" ]; then
    echo "FAIL  $what (expected AIR $3)"; failures=$((failures + 1))
  elif [ -z "$log" ]; then
    echo "FAIL  $what (no 'd9mt: AIR metallibs tagged for macOS' line)"; failures=$((failures + 1))
  elif [ "$4" = 1 ] && [ "$status" != 0 ]; then
    echo "FAIL  $what"; failures=$((failures + 1))
  else
    echo "ok    $what"
  fi
}

for shader in vs_mvp ps_texld; do
  run "$shader" 26 2.7 1
  must=0; [ "$host" -ge 27 ] && must=1
  run "$shader" 27 2.9 "$must"
  run "$shader" "" "$host_air" 1
done

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
