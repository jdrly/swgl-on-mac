#!/bin/bash
# Resources/bin/wine: the Java launcher runs `wine SwgClient_r.exe` (and
# `wine SwgClientSetup_r.exe`) from the game folder. Route that to the bundled
# Wine with the app's prefix and settings. Output goes to a log file because the
# launcher never drains the child's stdout, which would otherwise stall the game.
. "$(dirname "$0")/../common.sh"
swgl_wine_env
mkdir -p "$LOGS"
# Settings changed from the Settings window since the app started.
apply_prefix_settings >>"$LOGS/app.log" 2>&1
case "$1" in
  *SwgClient_*) ;;
  *)
    echo "=== $(date '+%F %T') wine $* (cwd $PWD, D3D9=$D3D9 X87=$X87)" >>"$LOGS/wine.log"
    exec "$WINE_HOME/bin/wine" "$@" >>"$LOGS/wine.log" 2>&1 </dev/null ;;
esac

# The game client. The launcher drops the process it starts (it never waits for it, reads
# from it or stops it), so instead of exec'ing Wine the shim waits for it, idle, to log how
# the game ended. Nothing of the shim's own may reach the launcher's pipe either.
exec 2>>"$LOGS/app.log"
exe="$(basename "${1//\\//}")"
{
  fix_game_password
  enable_game_mode "$exe"
} >>"$LOGS/app.log" 2>&1
swgl_debug_env
{
  echo "=== $(date '+%F %T') game start: $exe ($(swgl_versions))"
  swgl_system_info
  cat "$DISPLAYS_CACHE" 2>/dev/null
  [ "$DEBUG" = on ] && echo "Debug Mode: WINEDEBUG=$WINEDEBUG D9MT_PROFILE=$D9MT_PROFILE" \
    "D9MT_HITCH_MS=$D9MT_HITCH_MS D9MT_MEMSTATS=$D9MT_MEMSTATS"
} >>"$LOGS/app.log" 2>&1
since="$(mktemp)"
trimmer=
if [ "$DEBUG" = on ]; then
  # Debug Mode logs a lot: past 100 MB, wine.log moves to wine.log.old and starts afresh
  # (Wine appends, so emptying the file under it is safe). Checked once a minute.
  ( while sleep 60; do
      [ "$(stat -f %z "$LOGS/wine.log" 2>/dev/null || echo 0)" -gt 100000000 ] || continue
      { cp -c "$LOGS/wine.log" "$LOGS/wine.log.old" 2>/dev/null || cp "$LOGS/wine.log" "$LOGS/wine.log.old"; } &&
        : >"$LOGS/wine.log" && echo "=== $(date '+%F %T') wine.log passed 100 MB, the earlier part is in wine.log.old" >>"$LOGS/wine.log"
    done ) </dev/null >/dev/null 2>&1 &
  trimmer=$!
fi
echo "=== $(date '+%F %T') wine $* (cwd $PWD, D3D9=$D3D9 X87=$X87 DEBUG=$DEBUG)" >>"$LOGS/wine.log"
start=$SECONDS
"$WINE_HOME/bin/wine" "$@" >>"$LOGS/wine.log" 2>&1 </dev/null
status=$?
[ -n "$trimmer" ] && { kill "$trimmer"; wait "$trimmer"; } 2>/dev/null
game_exit_note "$exe" "$status" "$since" $((SECONDS - start)) 2>&1 | tee -a "$LOGS/wine.log" >>"$LOGS/app.log"
rm -f "$since"
exit "$status"
