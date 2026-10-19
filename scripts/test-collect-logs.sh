#!/bin/bash
# Test of Collect Logs (src/collect-logs.sh) and its crash reports in a sandbox: HOME and
# SWGL_HOME point into a temporary folder, so the logs, the settings and macOS's
# DiagnosticReports are the sandbox's (the real ones are never read or written), and the
# app's Resources are a fake app bundle with common.sh, collect-logs.sh and VERSIONS.
#
#   scripts/test-collect-logs.sh   prints a line per check; exits 1 if any fails
#
# The fake reports, from the newest: the game's, three large Wine ones (8.7 MB together), one
# over the 10 MB total, the launcher's (Java) over 3 MB, Metal's compiler for Wine and for
# another app, another app's Wine, Java and Safari, a .txt, then 20 small ones of the game,
# Wine, Java and the app's executables (only 15 fit in the 20 reports) and one 8 days old.
set -u
cd "$(dirname "$0")/.." || exit 1
SRC="$PWD/src"
SANDBOX="$(mktemp -d -t collect-logs-test)" || exit 1
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export SWGL_HOME="$HOME/Library/Application Support/SWGLonMac"
RES="$SANDBOX/Apps/SWGL on Mac.app/Contents/Resources"
DIAG="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$RES" "$DIAG" "$SWGL_HOME" "$HOME/Library/Logs/SWGLonMac" "$SANDBOX/out" "$SANDBOX/zip"
cp "$SRC/common.sh" "$SRC/collect-logs.sh" "$RES/"
printf 'wine test\njre test\nd9mt test\nsparkle test\napp 0.0.0-test\n' >"$RES/VERSIONS"

pass=0 fail=0
check() {  # description command...
  if "${@:2}" >/dev/null 2>&1; then
    pass=$((pass + 1)); echo "ok    $1"
  else
    fail=$((fail + 1)); echo "FAIL  $1"
  fi
}

# Every folder the scripts use is in the sandbox, or the test stops before running them.
paths="$(bash -c '. "$1/common.sh"; printf "%s\n" "$SUPPORT" "$LOGS" "$CACHES" "$DIAG_REPORTS"' _ "$RES")"
in_sandbox() { [ -n "$paths" ] && ! printf '%s\n' "$paths" | grep -v -q "^$SANDBOX/"; }
check "sandbox: Application Support, logs, caches and DiagnosticReports are the sandbox's" in_sandbox
in_sandbox || { echo "Not a sandbox; stopping"; exit 1; }

base=$(date +%s)
fake_report() {  # name minutes-ago [bytes (0: small)] [app] [responsibleProc]
  local f="$DIAG/$1" proc="${1%-2000-*}" pad
  printf '{"app_name":"%s","timestamp":"2000-01-01","incident":"FAKE-REPORT"}\n{\n  "procPath" : "%s/Applications/%s.app/Contents/MacOS/%s",\n  "responsibleProc" : "%s",\n  "crashReporterKey" : "SECRETKEY123",\n  "userEmail" : "player@example.com",\n  "path" : "/Users/%s/Desktop"\n}\n' \
    "$proc" "$HOME" "${4:-SWGL on Mac}" "$proc" "${5:-$proc}" "$(id -un)" >"$f"
  if [ "${3:-0}" -gt 0 ]; then
    pad=$(($3 - $(stat -f %z "$f")))
    LC_ALL=C awk -v n="$pad" 'BEGIN { l = "a line of a large crash report\n"
      for (; n >= length(l); n -= length(l)) printf "%s", l; printf "%s", substr(l, 1, n) }' >>"$f"
  fi
  touch -t "$(date -r $((base - $2 * 60)) +%Y%m%d%H%M.%S)" "$f"
}
# want: the reports expected in the zip, newest first
want=(SwgClient_r.exe-2000-01-01-120000.ips)
fake_report SwgClient_r.exe-2000-01-01-120000.ips 1
for i in 1 2 3; do
  fake_report "wine-2000-01-01-11000$i.ips" $((1 + i)) 2900000
  want+=("wine-2000-01-01-11000$i.ips")
done
fake_report wineserver-2000-01-01-110004.ips 5 2900000
fake_report java-2000-01-01-110005.ips 6 3500000
fake_report MTLCompilerService-2000-01-01-110006.ips 7 0 "SWGL on Mac" wine
want+=(MTLCompilerService-2000-01-01-110006.ips)
fake_report MTLCompilerService-2000-01-01-110007.ips 8 0 Xcode Xcode
fake_report wine-2000-01-01-110008.ips 9 0 Whisky
fake_report java-2000-01-01-110009.ips 10 0 Minecraft
fake_report Safari-2000-01-01-110010.ips 11 0 Safari
fake_report SwgClient_r.exe-2000-01-01-110011.txt 12
small=(SwgClient_Latest-x64.exe-2000-01-01-100000.ips SwgClient_r.exe-2000-01-01-100001.crash
  wine64-preloader-2000-01-01-100002.crash SWGLonMac-2000-01-01-100003.hang
  SWGLonMacSetup-2000-01-01-100004.spin SWGLonMacSettings-2000-01-01-100005.diag
  SWGLonMacRosettaCheck-2000-01-01-100006.ips "SWGL on Mac-2000-01-01-100007.hang"
  java-2000-01-01-100008.ips wineserver-2000-01-01-100009.diag)
for i in 10 11 12 13 14 15 16 17 18 19; do small+=("wine-2000-01-01-0900$i.ips"); done
n=20
for f in "${small[@]}"; do
  fake_report "$f" "$n"
  [ "$n" -ge 35 ] || want+=("$f")
  n=$((n + 1))
done
fake_report wine-2000-01-01-080000.ips $((8 * 24 * 60))

zip="$(/bin/bash "$RES/collect-logs.sh" "$SANDBOX/out" 2>"$SANDBOX/collect.err")"
check "logs: the zip is in the folder asked for" test -f "$zip" -a "${zip#"$SANDBOX/out/"}" != "$zip"
[ -f "$zip" ] && unzip -q "$zip" -d "$SANDBOX/zip"
CR=$(echo "$SANDBOX"/zip/*/crash-reports) SI=$(echo "$SANDBOX"/zip/*/system-info.txt)

same_set() { [ "$(cd "$CR" && printf '%s\n' * | sort)" = "$(printf '%s\n' "${want[@]}" | sort)" ]; }
check "crash reports: the newest 20 of the game, Wine, Java and the app, within 3 MB each and 10 MB together" same_set
only_fakes() { [ -d "$CR" ] && ! grep -L -e FAKE-REPORT "$CR"/* | grep -q .; }
check "crash reports: only the sandbox's fakes, nothing from the real DiagnosticReports" only_fakes
redacted() {
  ! grep -rq -e "$HOME" -e "/Users/$(id -un)/" -e SECRETKEY123 -e player@example.com "$SANDBOX/zip" &&
    grep -q '"procPath" : "~/Applications/SWGL on Mac.app/Contents/MacOS/SwgClient_r.exe"' \
      "$CR/SwgClient_r.exe-2000-01-01-120000.ips"
}
check "crash reports: redacted (home, user name, crash reporter key, e-mail)" redacted
listed() {  # the names in system-info.txt's list that are in the zip, in order
  sed -n '/^Crash reports of the last 7 days/,/^$/p' "$SI" | sed -n 's/^  \([^l].*\) ([0-9-]* [0-9:]*, [0-9]* KB)$/\1/p'
}
check "system info: lists the 20 in the zip, the newest first" test "$(listed)" = "$(printf '%s\n' "${want[@]}")"
left_out() {
  local s
  s="$(sed -n '/^Crash reports of the last 7 days/,/^$/p' "$SI" | grep '^  left out: ')"
  printf '%s\n' "$s" | grep -q -x '  left out: wineserver-2000-01-01-110004.ips (over 10 MB together)' &&
    printf '%s\n' "$s" | grep -q -x '  left out: java-2000-01-01-110005.ips (3500 KB, too large)' &&
    [ "$(printf '%s\n' "$s" | grep -c ' (more than 20 reports)$')" = 5 ] &&
    printf '%s\n' "$s" | grep -q -x '  left out: wine-2000-01-01-090019.ips (more than 20 reports)' &&
    [ "$(printf '%s\n' "$s" | wc -l | tr -d ' ')" = 7 ]
}
check "system info: names the ones left out and why (other apps', .txt and old ones not at all)" left_out

# game_exit_note (common.sh) right after the game: the reports newer than the game's start.
touch -t "$(date -r $((base - 150)) +%Y%m%d%H%M.%S)" "$SANDBOX/game-start"
exit_note() {
  [ "$(bash -c '. "$1/common.sh"; game_exit_note SwgClient_r.exe 0 "$2" 61' _ "$RES" "$SANDBOX/game-start" |
    grep '^Crash report: ')" = "$(printf 'Crash report: %s\n' SwgClient_r.exe-2000-01-01-120000.ips wine-2000-01-01-110001.ips)" ]
}
check "game exit note: the reports since the game started, newest first" exit_note

[ -s "$SANDBOX/collect.err" ] && { echo "collect-logs.sh wrote to stderr:"; sed 's/^/  /' "$SANDBOX/collect.err"; }
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
