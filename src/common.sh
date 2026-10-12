# Shared paths and environment for SWGL on Mac.
# Sourced by Resources/main.sh and the shims in Resources/bin.

RES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$(cd "$RES/../.." && pwd)"

SUPPORT="${SWGL_HOME:-$HOME/Library/Application Support/SWGLonMac}"
GAME="$SUPPORT/Game"
PREFIX="$SUPPORT/Prefix"
SETTINGS="$SUPPORT/settings.conf"
LOGS="$HOME/Library/Logs/SWGLonMac"
CACHES="$HOME/Library/Caches/SWGLonMac"

# Builds before the rename kept everything in "SWGLegends" folders: move them over once.
for dir in "Application Support" Logs Caches; do
  [ "$dir" = "Application Support" ] && [ -n "${SWGL_HOME:-}" ] && continue
  [ -d "$HOME/Library/$dir/SWGLegends" ] && [ ! -e "$HOME/Library/$dir/SWGLonMac" ] &&
    mv "$HOME/Library/$dir/SWGLegends" "$HOME/Library/$dir/SWGLonMac"
done

WINE_HOME="$RES/wine"
# The official launcher, downloaded on first run (SWGL allows using this URL).
LAUNCHER_ZIP_URL=https://backup.swglegends.com/SWGLegendsLauncher.zip
JAVA_HOME="$RES/jre/Contents/Home"
GAME_DRIVE="s:"

# User-tweakable settings (also written by the maintenance menu).
D3D9=d9mt         # d9mt (Metal) | wined3d (OpenGL)
X87=on            # on | off  (x87sidecar Rosetta acceleration)
RETINA=on         # on | off  (render at full Retina resolution)
FPS_HUD=off       # on | off  (Apple's Metal performance HUD over the game)
GAME_MODE=on      # on | off  (macOS Game Mode while the game is full screen)
[ -f "$SETTINGS" ] && . "$SETTINGS"
[ "$D3D9" = mtld3d ] && D3D9=d9mt   # settings written by the former mtld3d build

swgl_save_settings() {
  mkdir -p "$SUPPORT"
  printf 'D3D9=%s\nX87=%s\nRETINA=%s\nFPS_HUD=%s\nGAME_MODE=%s\n' "$D3D9" "$X87" "$RETINA" "$FPS_HUD" "$GAME_MODE" >"$SETTINGS"
}

swgl_wine_env() {
  export WINEPREFIX="$PREFIX"
  # Drop Wine debug channels into $SUPPORT/winedebug to trace the next game launch,
  # and extra exports (VAR=value lines) into $SUPPORT/debug.env.
  if [ -s "$SUPPORT/winedebug" ]; then
    WINEDEBUG="$(head -1 "$SUPPORT/winedebug")"
  fi
  if [ -s "$SUPPORT/debug.env" ]; then
    set -a; . "$SUPPORT/debug.env"; set +a
  fi
  export WINEDEBUG="${WINEDEBUG:--all}"
  if [ "$FPS_HUD" = on ]; then
    export MTL_HUD_ENABLED=1
  else
    unset MTL_HUD_ENABLED
  fi
  export WINEDLLOVERRIDES="winemenubuilder.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
  # dxgi stays off DXMT's tree: its own winemetal.dll would shadow the d9mt bridge.
  if [ "$D3D9" = wined3d ]; then
    export WINE_COMPATDB=$'v=5\nname=swgl;exe=*;d3d9=wined3d;dxgi=wined3d'
  else
    export WINE_COMPATDB=$'v=5\nname=swgl;exe=*;dxgi=wined3d'
  fi
  # d9mt: config, and caches/debug flags apart from other d9mt users on this Mac.
  export DXVK_CONFIG_FILE="$RES/d9mt.conf"
  export D9MT_AIR_CACHE="$CACHES/d9mt/air-cache.sqlite3"
  export D9MT_PSO_ARCHIVE_DIR="$CACHES/d9mt/pso"
  export D9MT_DEBUG_FILE="Z:$(printf '%s' "$HOME" | tr / '\\')\\Library\\Logs\\SWGLonMac\\d9mt-debug.txt"
  if [ "$X87" = off ]; then
    export ROSETTA_X87_PATH=""
  else
    unset ROSETTA_X87_PATH
  fi
}

wine_cmd() {
  ( swgl_wine_env; "$WINE_HOME/bin/wine" "$@" )
}

apply_mac_driver_settings() {
  local key='HKCU\Software\Wine\Mac Driver' v=n
  [ "$RETINA" = on ] && v=y
  wine_cmd reg add "$key" /v RetinaMode /t REG_SZ /d "$v" /f >/dev/null || return
  # Stock Mac driver behaviour otherwise: drop values earlier builds experimented with.
  for value in RawMouseWhenCursorHidden IgnoreStaleCursorWarps UseConfinementCursorClipping CaptureDisplaysForFullscreen; do
    wine_cmd reg delete "$key" /v "$value" /f >/dev/null 2>&1
  done
  # SWG applies Windows pointer acceleration to each mouse-look input event, and Wine batches
  # mouse moves differently from Windows, so the turn speed would vary. Without acceleration
  # mouse-look is a constant 1:1.
  wine_cmd reg add 'HKCU\Control Panel\Mouse' /v MouseSpeed /t REG_SZ /d 0 /f >/dev/null
}

apply_prefix_settings() {
  # Registry writes start Wine, so only redo them when the settings changed.
  local stamp="$PREFIX/.swgl-applied" want="retina=$RETINA baseline=d9mt-1" had
  had="$(cat "$stamp" 2>/dev/null)"
  [ "$had" = "$want" ] && return
  apply_mac_driver_settings || return
  case "$had" in
    "retina=on "*|"retina=off "*) [ "${had%% *}" = "retina=$RETINA" ] || scale_game_resolution ;;
  esac
  echo "$want" >"$stamp"
}

scale_game_resolution() {
  # Retina mode changes what a screen pixel is to the game (device pixels vs points), so the
  # resolution and UI scale saved in options.cfg would no longer fit the display: scale them
  # by the display's backing scale factor to keep the same picture size.
  local cfg="$GAME/options.cfg" scale
  [ -f "$cfg" ] || return 0
  scale="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.mainScreen.backingScaleFactor' 2>/dev/null)"
  case "$scale" in ""|1) return 0 ;; esac
  awk -v f="$scale" -v up="$([ "$RETINA" = on ] && echo 1 || echo 0)" '
    BEGIN { if (!up) f = 1 / f }
    {
      line = $0; cr = sub(/\r$/, "", line)
      if (line ~ /^[ \t]*(screenWidth|screenHeight)=[0-9]+$/) {
        split(line, kv, "="); line = kv[1] "=" int(kv[2] * f + 0.5)
      } else if (line ~ /^[ \t]*uiScalingFactor=[0-9.]+$/) {
        split(line, kv, "="); line = sprintf("%s=%f", kv[1], kv[2] * f)
      }
      printf "%s%s\n", line, (cr ? "\r" : "")
    }' "$cfg" >"$cfg.swgl-tmp" && mv "$cfg.swgl-tmp" "$cfg"
  echo "Scaled the game resolution in options.cfg for RETINA=$RETINA (x$scale)"
}

fix_game_password() {
  # The game reads its saved password from legends.cfg (loginClientEncHashedPassword) with
  # Windows DPAPI. On macOS the launcher cannot encrypt it: it writes plain base64, and it
  # loads the setting back from a different key, so the next save writes it empty. Encrypt
  # the password with DPAPI in this prefix instead (Resources/tools/swgl-dpapi.exe), taking
  # it from the launcher's Settings or, if that is empty, from its "Remember me" login for
  # the same account.
  local cfg="$GAME/legends.cfg" ini="$GAME/launchersettings.ini"
  local dpapi="$RES/tools/swgl-dpapi.exe" marker start i stored id pw enc
  [ -f "$cfg" ] && [ -f "$dpapi" ] || return 0

  # Play saves legends.cfg while the game is being started: let that write land first.
  marker="$(mktemp)"; start="$(stat -f %Fm "$marker")"; rm -f "$marker"
  for i in $(seq 20); do
    awk -v a="$(stat -f %Fm "$cfg")" -v b="$start" 'BEGIN { exit !(a >= b) }' && break
    sleep 0.1
  done

  cfg_value() { awk -v k="$1" '{ sub(/\r$/, "") } $0 ~ "^[ \t]*" k "=" { sub(/^[^=]*=/, ""); print; exit }' "$cfg"; }
  ini_value() { awk -v s="[$1]" -v k="$2" '
    { sub(/\r$/, "") } /^\[/ { in_s = ($0 == s); next }
    in_s && $0 ~ "^[ \t]*" k "[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); print; exit }' "$ini" |
    sed 's/\\\(.\)/\1/g'; }  # ini4j escapes "=" (base64 padding) as "\="
  dpapi() { "$WINE_HOME/bin/wine" "$dpapi" "$1" 2>/dev/null; }

  stored="$(cfg_value loginClientEncHashedPassword)"
  [ -n "$stored" ] && printf %s "$stored" | dpapi check && return 0
  id="$(cfg_value loginClientID)"
  [ -n "$id" ] || return 0
  # Plain base64 from the launcher's Settings; anything else (a blob from an older prefix) is unusable.
  pw="$(printf %s "$stored" | base64 -D 2>/dev/null)"
  if [ -z "$pw" ] || [ "$(printf %s "$pw" | base64)" != "$stored" ] || printf %s "$pw" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    pw=""
    if [ -f "$ini" ] && [ "$(ini_value login remember)" = true ] &&
       [ "$(printf %s "$(ini_value login username)" | tr '[:upper:]' '[:lower:]')" = "$(printf %s "$id" | tr '[:upper:]' '[:lower:]')" ]; then
      pw="$(ini_value login password | base64 -D 2>/dev/null)"
    fi
  fi
  [ -n "$pw" ] || return 0
  enc="$(printf %s "$pw" | dpapi protect)" && [ -n "$enc" ] || { echo "Could not encrypt the game password"; return 0; }
  awk -v v="$enc" '{ cr = sub(/\r$/, "") }
    /^[ \t]*loginClientEncHashedPassword=/ { sub(/=.*/, "=" v) }
    { printf "%s%s\n", $0, (cr ? "\r" : "") }' "$cfg" >"$cfg.swgl-tmp" && mv "$cfg.swgl-tmp" "$cfg"
  echo "Saved the game password for $id in legends.cfg (DPAPI)"
}

enable_game_mode() {
  # macOS turns Game Mode on only for a process whose executable is the executable of a bundle
  # declaring itself a game (LSSupportsGameMode). Wine runs every process from its loader, but
  # it can start one from a link in $TMPDIR/winetemp-<loader ino>-<size>-<mtime s>-<mtime ns>/
  # (CrossOver hack 22144, active when WINEDLLPATH is set) and reuses whatever exists there.
  # The program a `wine` command starts (the game, here) gets the link named "wine"; pointing
  # it at a game bundle's clone of the loader runs the game from that bundle.
  #
  # The loader finds ntdll.so next to its resolved path, so the bundle needs an ntdll.so link
  # to the app's Wine. A signed app cannot contain a link leaving a bundle, so the bundle is
  # assembled here, outside the app, and refreshed whenever the app's Wine changes or moves.
  # The loader copy is unsigned, like Wine's loader as released: in the signed app it carries
  # the app's signature and entitlements, which macOS rejects inside a bundle they were not
  # made for (the process is killed with "Code Signature Invalid").
  local exe="$1" lib="$WINE_HOME/lib/wine/x86_64-unix" gm="$SUPPORT/GameMode/SWGLGame.app/Contents" m dir src
  [ "$GAME_MODE" = on ] && [ -f "$RES/gamemode/Info.plist" ] && [ "$exe" = SwgClient_r.exe ] || return 0
  src="$(stat -f '%i-%z-%m' "$lib/wine") $lib $(md5 -q "$RES/gamemode/Info.plist")"
  if [ "$(cat "$gm/.source" 2>/dev/null)" != "$src" ] || [ ! -x "$gm/MacOS/$exe" ]; then
    rm -rf "${gm%/Contents}" && mkdir -p "$gm/MacOS" &&
      cp -c "$lib/wine" "$gm/MacOS/$exe" && { codesign --remove-signature "$gm/MacOS/$exe" 2>/dev/null || true; } &&
      ln -s "$lib/ntdll.so" "$gm/MacOS/ntdll.so" && cp "$RES/gamemode/Info.plist" "$gm/Info.plist" &&
      echo "$src" >"$gm/.source" || { echo "Game Mode bundle not created"; return 0; }
    echo "Assembled the Game Mode bundle in ${gm%/Contents}"
  fi
  export WINEDLLPATH="$WINE_HOME/lib/wine"
  m="$(stat -f %Fm "$lib/wine")" || return 0
  dir="$(getconf DARWIN_USER_TEMP_DIR)winetemp-$(stat -f '%i-%z' "$lib/wine")-${m%.*}-$((10#${m#*.}))"
  mkdir -p -m 700 "$dir" && ln -sfn "$gm/MacOS/$exe" "$dir/wine"
}

swgl_notify() {
  osascript -e "display notification \"$1\" with title \"SWGL on Mac\"" >/dev/null 2>&1 || true
}

swgl_alert() {
  osascript -e "display alert \"SWGL on Mac\" message \"$1\" as critical" >/dev/null 2>&1 || true
}
