#!/bin/bash
# Resources/main.sh, run by the app's launcher (Contents/MacOS/SWGLonMac, src/native/launcher.c):
# prepares the Wine prefix and game folder, then runs
# the official SWGL Java launcher natively. The launcher starts the game
# by running `wine SwgClient_r.exe`, which resolves to Resources/bin/wine.
set -u
. "$(dirname "$0")/common.sh"

mkdir -p "$LOGS" "$GAME"
for log in app launcher wine; do
  # Keep logs from growing forever: start fresh once they pass 20 MB.
  f="$LOGS/$log.log"
  [ -f "$f" ] && [ "$(stat -f %z "$f")" -gt 20000000 ] && mv -f "$f" "$f.old"
done
exec >>"$LOGS/app.log" 2>&1
echo "=== $(date '+%F %T') ${1:-starting} ($(cat "$RES/VERSIONS" | tr '\n' ' '))"
swgl_system_info
# The displays take system_profiler a moment: list them in the background, and keep the
# list for the game start blocks (Resources/bin/wine).
mkdir -p "$CACHES"
( swgl_displays >"$DISPLAYS_CACHE.tmp" && mv -f "$DISPLAYS_CACHE.tmp" "$DISPLAYS_CACHE" && cat "$DISPLAYS_CACHE" ) </dev/null &

option_held() {
  [ "$(osascript -l JavaScript -e 'ObjC.import("AppKit"); ($.NSEvent.modifierFlags & 0x80000) ? "1" : "0"' 2>/dev/null)" = 1 ]
}

ensure_rosetta() {
  # Wine is x86_64, so it needs Rosetta, which macOS 27 drops on an upgrade. Install it
  # (softwareupdate needs no admin rights for it; the welcome window says that this accepts
  # Apple's licence). If that fails, open the Intel-only helper: macOS then offers the
  # installation in its own dialog, which a script running Wine never gets.
  swgl_x86_ok && return 0
  echo "x86 translation does not work on macOS $(sw_vers -productVersion); installing Rosetta"
  [ "${1:-}" = --prepare ] || swgl_notify "Installing Rosetta for the game, this takes a minute…"
  /usr/sbin/softwareupdate --install-rosetta --agree-to-license 2>&1 | tr '\r' '\n' | grep -v '^Installing: ' | sed 's/^/  softwareupdate: /'
  swgl_x86_ok && { echo "Rosetta installed"; return 0; }
  echo "Still no x86 translation; asking macOS to install Rosetta"
  open -W "$APP_BUNDLE/Contents/Helpers/SWGL on Mac Rosetta Check.app" 2>&1 | sed 's/^/  open: /'
  for _ in $(seq 10); do
    swgl_x86_ok && { echo "Rosetta installed"; return 0; }
    sleep 1
  done
  echo "Rosetta is not available; giving up"
  if [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 28 ]; then
    # Apple: from macOS 28, Rosetta remains only for certain older games (#20).
    swgl_alert "SWGL on Mac doesn't run on this version of macOS yet. A version for macOS 28 is in the works."
  else
    swgl_alert "SWGL on Mac couldn't install Rosetta, which it needs to run the game. Check your internet connection, then open SWGL on Mac again."
  fi
  return 1
}

ensure_prefix() {
  ensure_rosetta "${1:-}" || exit 1
  local stamp="$PREFIX/.swgl-wine-version" want
  want="$(head -1 "$RES/VERSIONS")"
  if [ ! -f "$PREFIX/system.reg" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$want" ]; then
    echo "Initialising Wine prefix at $PREFIX for $want"
    [ "${1:-}" = --prepare ] || swgl_notify "Getting everything ready, this takes a moment…"
    mkdir -p "$PREFIX"
    wine_cmd wineboot -u || {
      [ "${1:-}" = --prepare ] || swgl_alert "Could not initialise Wine. See ~/Library/Logs/SWGLonMac/app.log"
      exit 1
    }
    ( swgl_wine_env; "$WINE_HOME/bin/wineserver" -w )
    echo "$want" >"$stamp"
  fi
  # The game lives outside the prefix; expose it as drive S: so the client sees S:\ as its folder.
  ln -sfn "$GAME" "$PREFIX/dosdevices/$GAME_DRIVE"
  apply_prefix_settings
  ensure_d3dx9
}

ensure_launcher() {
  # First run: the welcome window downloads the official launcher from SWGL and runs the
  # first-time prefix setup (this script with --prepare). After that the launcher
  # updates itself in place, so the window never shows again.
  [ -f "$GAME/SWGLegendsLauncher.exe" ] && return
  "$APP_BUNDLE/Contents/Helpers/SWGL on Mac Setup.app/Contents/MacOS/SWGLonMacSetup" "$LAUNCHER_ZIP_URL" "$GAME" /bin/bash "$0" --prepare || exit 0
}

choose() {
  osascript - "$@" <<'EOF'
on run argv
  set picked to choose from list argv with title "SWGL on Mac" with prompt "Maintenance options:" default items {item 1 of argv} OK button name "Run" cancel button name "Quit"
  if picked is false then return ""
  return item 1 of picked
end run
EOF
}

maintenance_menu() {
  while :; do
    local other_d3d9=wined3d other_x87=off other_retina=on other_hud=on other_debug=on
    [ "$D3D9" = wined3d ] && other_d3d9=d9mt
    [ "$X87" = off ] && other_x87=on
    [ "$RETINA" = on ] && other_retina=off
    [ "$FPS_HUD" = on ] && other_hud=off
    [ "$DEBUG" = on ] && other_debug=off
    local c zip
    c="$(choose \
      "Play" \
      "Open game folder" \
      "Open logs folder" \
      "Collect logs (zip on the Desktop)" \
      "D3D9 renderer: $D3D9 → switch to $other_d3d9" \
      "x87 acceleration: $X87 → turn $other_x87" \
      "Retina resolution: $RETINA → turn $other_retina" \
      "FPS overlay: $FPS_HUD → turn $other_hud" \
      "Debug Mode (detailed logs): $DEBUG → turn $other_debug" \
      "Wine configuration (winecfg)" \
      "Stop all running Wine processes" \
      "Reset Wine environment (keeps game files)")"
    case "$c" in
      "") exit 0 ;;
      "Play") return ;;
      "Open game folder") open "$GAME" ;;
      "Open logs folder") open "$LOGS" ;;
      "Collect logs"*)
        if zip="$("$RES/collect-logs.sh" | tail -1)" && [ -f "$zip" ]; then
          open -R "$zip"; swgl_notify "Logs saved as ${zip##*/}"
        else
          swgl_alert "Could not collect the logs. See ~/Library/Logs/SWGLonMac/app.log"
        fi ;;
      "D3D9 renderer"*) D3D9=$other_d3d9; swgl_save_settings ;;
      "x87 acceleration"*) X87=$other_x87; swgl_save_settings ;;
      "Retina resolution"*) RETINA=$other_retina; swgl_save_settings; ensure_prefix ;;
      "FPS overlay"*) FPS_HUD=$other_hud; swgl_save_settings ;;
      "Debug Mode"*) DEBUG=$other_debug; swgl_save_settings ;;
      "Wine configuration"*) ensure_prefix; wine_cmd winecfg ;;
      "Stop all"*) ( swgl_wine_env; "$WINE_HOME/bin/wineserver" -k ) ;;
      "Reset Wine environment"*)
        ( swgl_wine_env; "$WINE_HOME/bin/wineserver" -k )
        rm -rf "$PREFIX"; ensure_prefix; swgl_notify "Wine environment reset." ;;
    esac
  done
}

if [ "${1:-}" = --prepare ]; then  # run by the welcome window
  ensure_prefix --prepare
  exit
fi

option_held && maintenance_menu
ensure_launcher
ensure_prefix

# macOS waits only a short while for an app it launched to check in; a launcher that starts
# later (after the welcome window, a prefix update or the maintenance menu) runs without the
# app's identity ("java" in the menu bar, no SWGL on Mac menus). Start the app afresh
# instead: everything is ready now, so the new instance checks in at once. Only once.
if [ "$SECONDS" -gt 3 ] && [ -z "${SWGL_RELAUNCHED:-}" ]; then
  echo "Relaunching after ${SECONDS}s of setup so the launcher keeps the app's identity"
  open -n --env SWGL_RELAUNCHED=1 ${SWGL_HOME:+--env "SWGL_HOME=$SWGL_HOME"} "$APP_BUNDLE"
  exit 0
fi

cd "$GAME" || exit 1
export PATH="$RES/bin:$PATH"
# Debug Mode leaves the launcher's own debug switch (a "SWGlauncherdebug" file here) off: it
# also changes what the launcher asks SWGL's servers ("relog-testing" for test accounts).
echo "Launching Java launcher in $GAME (D3D9=$D3D9 X87=$X87 RETINA=$RETINA DEBUG=$DEBUG)"
exec "$JAVA_HOME/bin/java" \
  -Xdock:name="SWGL on Mac" -Xdock:icon="$RES/AppIcon.icns" \
  -Dfile.encoding=UTF-8 -Dswgl.res="$RES" -Dswgl.game="$GAME" \
  -cp "$RES/java:SWGLegendsLauncher.exe" Launcher SWGLegendsLauncher.exe >>"$LOGS/launcher.log" 2>&1
