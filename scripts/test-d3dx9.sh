#!/bin/bash
# Checks ensure_d3dx9 (src/common.sh) in a sandbox: Microsoft's d3dx9_31 and the game's override
# are repaired on every start, and a failed step is a failure. Wine is a stub; nothing touches
# the real prefix, caches or Application Support.
#
#   scripts/test-d3dx9.sh                       the logic, with a fake DLL
#   TEST_DXREDIST=<directx_Jun2010_redist.exe> scripts/test-d3dx9.sh
#                                               also extracts the real DLL from that installer
set -u
cd "$(dirname "$0")/.." || exit 1
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" SWGL_HOME="$SANDBOX/support"
mkdir -p "$HOME/Library/Caches/SWGLonMac"
# shellcheck source=src/common.sh
. src/common.sh
mkdir -p "$PREFIX/drive_c/windows/system32" "$CACHES"
DLL="$PREFIX/drive_c/windows/system32/d3dx9_31.dll"
swgl_notify() { :; }
reg_calls=0 reg_status=0
wine_cmd() { reg_calls=$((reg_calls + 1)); return "$reg_status"; }

failures=0
check() { # check <description> <condition...>
  local what=$1; shift
  if "$@"; then echo "ok    $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}
override_reg() {
  printf '%s\n' 'WINE REGISTRY Version 2' '' \
    '[Software\\Wine\\AppDefaults\\SwgClient_r.exe\\DllOverrides] 1793040983' \
    '#time=1dd657bb1f99112' '"d3dx9_31"="native,builtin"' >"$PREFIX/user.reg"
}

# A fake "Microsoft" DLL stands in for the real one.
printf 'fake d3dx9_31\n' >"$SANDBOX/good.dll"
D3DX9_31_SHA256="$(sha256_of "$SANDBOX/good.dll")"

cp "$SANDBOX/good.dll" "$DLL"; : >"$PREFIX/user.reg"; reg_calls=0
ensure_d3dx9 >/dev/null; status=$?
check "right DLL, no override: the override is set" [ "$status" = 0 ] && [ "$reg_calls" = 1 ]

override_reg; reg_calls=0
ensure_d3dx9 >/dev/null; status=$?
check "right DLL and override: nothing to do, no Wine started" [ "$status" = 0 ] && [ "$reg_calls" = 0 ]

: >"$PREFIX/user.reg"; reg_status=1; reg_calls=0
out="$(ensure_d3dx9)"; status=$?
check "failed registry write: a failure, no success logged" [ "$status" != 0 ] && [ "${out#*prefer}" = "$out" ]
reg_status=0

printf 'Wine builtin DLL\n' >"$DLL"; mkdir -p "$CACHES/d3dx9"; cp "$SANDBOX/good.dll" "$CACHES/d3dx9/d3dx9_31.dll"; override_reg
ensure_d3dx9 >/dev/null; status=$?
check "Wine's DLL in the prefix: Microsoft's comes back from the cache" [ "$status" = 0 ] && cmp -s "$DLL" "$SANDBOX/good.dll"

printf 'Wine builtin DLL\n' >"$DLL"; rm -f "$CACHES/d3dx9/d3dx9_31.dll"
DXREDIST_URLS=("file://$SANDBOX/missing-1.exe" "file://$SANDBOX/missing-2.exe")
ensure_d3dx9 >/dev/null 2>&1; status=$?
check "no source works: a failure, the prefix keeps Wine's DLL" [ "$status" != 0 ] && grep -q 'Wine builtin' "$DLL"

if [ -n "${TEST_DXREDIST:-}" ]; then
  D3DX9_31_SHA256=84167b7df7e97c63f0cc15c1d272cdc7bba942f6f36a8801aec9840825891d0d
  DXREDIST_URLS=("file://$SANDBOX/missing.exe" "file://$TEST_DXREDIST")
  printf 'Wine builtin DLL\n' >"$DLL"; rm -rf "$CACHES/d3dx9"; override_reg
  ensure_d3dx9 >/dev/null 2>&1; status=$?
  check "real installer, first source missing: the second gives Microsoft's DLL" \
    [ "$status" = 0 ] && [ "$(sha256_of "$DLL")" = "$D3DX9_31_SHA256" ]
fi

[ "$failures" = 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
