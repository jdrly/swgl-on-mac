#!/bin/bash
# Resources/bin/wine: the Java launcher runs `wine SwgClient_r.exe` (and
# `wine SwgClientSetup_r.exe`) from the game folder. Route that to the bundled
# Wine with the app's prefix and settings. Output goes to a log file because the
# launcher never drains the child's stdout, which would otherwise stall the game.
. "$(dirname "$0")/../common.sh"
swgl_wine_env
mkdir -p "$LOGS"
# Settings changed from the launcher's Features menu since the app started.
apply_prefix_settings >>"$LOGS/app.log" 2>&1
case "$1" in
  *SwgClient_*)
    fix_game_password >>"$LOGS/app.log" 2>&1
    enable_game_mode "$(basename "${1//\\//}")" >>"$LOGS/app.log" 2>&1 ;;
esac
echo "=== $(date '+%F %T') wine $* (cwd $PWD, D3D9=$D3D9 X87=$X87)" >>"$LOGS/wine.log"
exec "$WINE_HOME/bin/wine" "$@" >>"$LOGS/wine.log" 2>&1 </dev/null
