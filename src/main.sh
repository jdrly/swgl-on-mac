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

option_held() {
  [ "$(osascript -l JavaScript -e 'ObjC.import("AppKit"); ($.NSEvent.modifierFlags & 0x80000) ? "1" : "0"' 2>/dev/null)" = 1 ]
}

ensure_prefix() {
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
    local other_d3d9=wined3d other_x87=off other_retina=on other_hud=on
    [ "$D3D9" = wined3d ] && other_d3d9=d9mt
    [ "$X87" = off ] && other_x87=on
    [ "$RETINA" = on ] && other_retina=off
    [ "$FPS_HUD" = on ] && other_hud=off
    local c
    c="$(choose \
      "Play" \
      "Open game folder" \
      "Open logs folder" \
      "D3D9 renderer: $D3D9 → switch to $other_d3d9" \
      "x87 acceleration: $X87 → turn $other_x87" \
      "Retina resolution: $RETINA → turn $other_retina" \
      "FPS overlay: $FPS_HUD → turn $other_hud" \
      "Wine configuration (winecfg)" \
      "Stop all running Wine processes" \
      "Reset Wine environment (keeps game files)")"
    case "$c" in
      "") exit 0 ;;
      "Play") return ;;
      "Open game folder") open "$GAME" ;;
      "Open logs folder") open "$LOGS" ;;
      "D3D9 renderer"*) D3D9=$other_d3d9; swgl_save_settings ;;
      "x87 acceleration"*) X87=$other_x87; swgl_save_settings ;;
      "Retina resolution"*) RETINA=$other_retina; swgl_save_settings; ensure_prefix ;;
      "FPS overlay"*) FPS_HUD=$other_hud; swgl_save_settings ;;
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
echo "Launching Java launcher in $GAME (D3D9=$D3D9 X87=$X87 RETINA=$RETINA)"
exec "$JAVA_HOME/bin/java" \
  -Xdock:name="SWGL on Mac" -Xdock:icon="$RES/AppIcon.icns" \
  -Dfile.encoding=UTF-8 -Dswgl.res="$RES" -Dswgl.game="$GAME" \
  -cp "$RES/java:SWGLegendsLauncher.exe" Launcher SWGLegendsLauncher.exe >>"$LOGS/launcher.log" 2>&1
