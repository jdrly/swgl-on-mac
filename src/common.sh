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
DEBUG=off         # on | off  (Debug Mode: much more logging from the game, see swgl_debug_env)
MOUSE_SPEED=1     # mouse-look speed: Windows mickeys per mouse count, 0.1 to 10 (1 = as on Windows)
[ -f "$SETTINGS" ] && . "$SETTINGS"
[ "$D3D9" = mtld3d ] && D3D9=d9mt   # settings written by the former mtld3d build
swgl_valid_mouse_speed() {
  [[ $1 =~ ^[0-9]{1,2}(\.[0-9]{1,2})?$ ]] && LC_ALL=C awk -v s="$1" 'BEGIN { exit !(s >= 0.1 && s <= 10) }'
}
swgl_valid_mouse_speed "$MOUSE_SPEED" || MOUSE_SPEED=1

swgl_settings() {
  printf 'D3D9=%s\nX87=%s\nRETINA=%s\nFPS_HUD=%s\nGAME_MODE=%s\nDEBUG=%s\nMOUSE_SPEED=%s\n' \
    "$D3D9" "$X87" "$RETINA" "$FPS_HUD" "$GAME_MODE" "$DEBUG" "$MOUSE_SPEED"
}

swgl_save_settings() {
  mkdir -p "$SUPPORT"
  swgl_settings >"$SETTINGS"
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
  SWGL_WINEDEBUG_GIVEN=${WINEDEBUG:+1}  # Debug Mode leaves channels given here alone
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
  D9MT_DEBUG_FILE="Z:$(printf '%s' "$HOME" | tr / '\\')\\Library\\Logs\\SWGLonMac\\d9mt-debug.txt"
  export D9MT_DEBUG_FILE
  if [ "$X87" = off ]; then
    export ROSETTA_X87_PATH=""
  else
    unset ROSETTA_X87_PATH
  fi
}

swgl_debug_env() {
  # Debug Mode (Settings window), for the game client only (the wine shim), so the registry and
  # DPAPI helpers stay quiet. Logging costs some performance and grows wine.log quickly, so it
  # is a bounded set aimed at what goes wrong on a Mac:
  #   Wine: timestamps and process ids to line the log up with d9mt's lines; errors and
  #   fixmes (Wine's own default); warn+seh, the exceptions Wine reports (a crash still gets
  #   Wine's backtrace); +loaddll, every DLL with native/builtin (which d3d9, mods); thread
  #   names. Left out: trace-level +seh (WoW64 unwinds every window callback, ~110 a second,
  #   each with a register dump: 99% of the log), and +dinput and +cursor, the mouse
  #   problems' channels, which log every mouse move; put them in $SUPPORT/winedebug instead.
  #   d9mt: its profiler (a PROF line every 256 frames, a HITCH line for every frame over
  #   50 ms, saying whether the time went to d9mt or the game) and memory statistics (a DIAG
  #   MEM line every 256 frames: the 32-bit game runs out of address space before RAM).
  # Channels from $SUPPORT/winedebug, debug.env or the environment win.
  [ "$DEBUG" = on ] || return 0
  [ -n "${SWGL_WINEDEBUG_GIVEN:-}" ] ||
    export WINEDEBUG=+timestamp,+pid,err+all,fixme+all,warn+seh,+loaddll,+threadname
  export D9MT_PROFILE="${D9MT_PROFILE:-1}" D9MT_HITCH_MS="${D9MT_HITCH_MS:-50}" D9MT_MEMSTATS="${D9MT_MEMSTATS:-1}"
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
  # Mouse-look moves come from GCMouse as device counts (patches/winemac-input.patch), like
  # Windows raw input, so 1 turns as fast as on Windows; the Settings window scales it.
  wine_cmd reg add "$key" /v RawMouseGameControllerScale /t REG_SZ /d "$MOUSE_SPEED" /f >/dev/null
}

ensure_d3dx9() {
  # SWG Legends' 64-bit client compiles its HLSL shaders with D3DX, and Wine's own d3dx9_31
  # (vkd3d-shader) rejects them ("unexpected KW_POINT": a variable named point). Microsoft's,
  # shipped in Resources/d3dx9 (build.sh), compiles them as on Windows: keep it in the prefix
  # (a Wine update's wineboot puts Wine's back) and have the game prefer it.
  local src="$RES/d3dx9/x86_64/d3dx9_31.dll" dst="$PREFIX/drive_c/windows/system32/d3dx9_31.dll"
  [ -f "$src" ] || return 0
  cmp -s "$src" "$dst" && return 0
  cp "$src" "$dst" || { echo "Could not install Microsoft's d3dx9_31 into the prefix"; return 0; }
  wine_cmd reg add 'HKCU\Software\Wine\AppDefaults\SwgClient_r.exe\DllOverrides' \
    /v d3dx9_31 /t REG_SZ /d native,builtin /f >/dev/null
  echo "Installed Microsoft's d3dx9_31 (64-bit) into the prefix"
}

apply_prefix_settings() {
  # Registry writes start Wine, so only redo them when the settings changed.
  local stamp="$PREFIX/.swgl-applied" want="retina=$RETINA baseline=d9mt-1 mouse=$MOUSE_SPEED" had
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
  echo "Saved the game password in legends.cfg (DPAPI)"
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
  # SwgClient_r.exe, or the 64-bit test client SwgClient_Latest-x64.exe; the bundle's
  # executable takes the client's name (Info.plist template: @EXE@).
  case "$exe" in SwgClient_*.exe) ;; *) return 0 ;; esac
  [ "$GAME_MODE" = on ] && [ -f "$RES/gamemode/Info.plist" ] || return 0
  src="$(stat -f '%i-%z-%m' "$lib/wine") $lib $exe $(md5 -q "$RES/gamemode/Info.plist")"
  if [ "$(cat "$gm/.source" 2>/dev/null)" != "$src" ] || [ ! -x "$gm/MacOS/$exe" ]; then
    rm -rf "${gm%/Contents}" && mkdir -p "$gm/MacOS" &&
      cp -c "$lib/wine" "$gm/MacOS/$exe" && { codesign --remove-signature "$gm/MacOS/$exe" 2>/dev/null || true; } &&
      ln -s "$lib/ntdll.so" "$gm/MacOS/ntdll.so" && sed "s/@EXE@/$exe/" "$RES/gamemode/Info.plist" >"$gm/Info.plist" &&
      echo "$src" >"$gm/.source" || { echo "Game Mode bundle not created"; return 0; }
    echo "Assembled the Game Mode bundle in ${gm%/Contents}"
  fi
  export WINEDLLPATH="$WINE_HOME/lib/wine"
  m="$(stat -f %Fm "$lib/wine")" || return 0
  dir="$(getconf DARWIN_USER_TEMP_DIR)winetemp-$(stat -f '%i-%z' "$lib/wine")-${m%.*}-$((10#${m#*.}))"
  # shellcheck disable=SC2174 # only winetemp-… is new; its parent is the user temp dir
  mkdir -p -m 700 "$dir" && ln -sfn "$gm/MacOS/$exe" "$dir/wine"
}

# Diagnostics for app.log and Collect Logs (Resources/collect-logs.sh). All cheap, and none of
# it runs while the game plays.
DISPLAYS_CACHE="$CACHES/displays.txt"  # swgl_displays at app start, for the game start blocks

swgl_versions() {  # "wine cx-26.3.0-8 jre … d9mt d0629b7 app 0.0.1"
  tr -s '\n ' '  ' <"$RES/VERSIONS" | sed 's/ $//'
}

# Whether this Mac runs x86_64 code, i.e. Wine (Rosetta installed and supported). For tests,
# SWGL_TEST_NO_ROSETTA=1 makes it fail.
swgl_x86_ok() {
  [ -z "${SWGL_TEST_NO_ROSETTA:-}" ] && /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null
}

swgl_system_info() {  # the Mac, power and settings, one line each (sysctl and pmset are fast)
  local mode
  echo "Mac: $(sysctl -n hw.model), $(sysctl -n machdep.cpu.brand_string)" \
    "($(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null)+$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null) cores)," \
    "$(($(sysctl -n hw.memsize) / 1073741824)) GB, macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  mode="$(pmset -g 2>/dev/null | awk '
    $1 == "lowpowermode" && $2 == 1 { print "Low Power Mode" }
    $1 == "powermode" { print ($2 == 1 ? "Low Power Mode" : $2 == 2 ? "High Power Mode" : "power mode automatic") }' | head -1)"
  echo "Power: $(pmset -g ps 2>/dev/null | sed -n "1s/.*'\(.*\)'.*/\1/p")${mode:+, $mode};" \
    "Rosetta $([ -e /Library/Apple/usr/libexec/oah/libRosettaRuntime ] && echo installed || echo "not installed")," \
    "x86 translation $(swgl_x86_ok && echo works || echo fails)"
  echo "Settings: $(swgl_settings | tr '\n' ' ')"
}

swgl_displays() {  # one "Display:" line per screen; system_profiler takes a moment
  system_profiler SPDisplaysDataType 2>/dev/null | awk '
    function out() {
      if (name != "") {
        s = "Display: " name (type != "" ? " (" type ")" : "") ", " res
        if (ui != "") {
          split(res, r, " "); split(ui, u, " ")
          s = s ", looks like " ui (u[1] > 0 ? sprintf(" (scale %g)", r[1] / u[1]) : "")
        }
        print s (main ? ", main" : "") (mirror ? ", mirrored" : "")
      }
      name = type = res = ui = ""; main = mirror = 0
    }
    /^ *$/ { next }
    { i = match($0, /[^ ]/); line = substr($0, i) }
    line == "Displays:" { out(); d = i; next }
    d && i <= d { out(); d = 0 }
    d && line ~ /:$/ { out(); name = substr(line, 1, length(line) - 1); next }
    d && sub(/^Display Type: /, "", line) { type = line }
    d && sub(/^Resolution: /, "", line) { sub(/ \(.*\)$/, "", line); res = line }
    d && sub(/^UI Looks like: /, "", line) { ui = line }
    d && line == "Main Display: Yes" { main = 1 }
    d && line == "Mirror: On" { mirror = 1 }
    END { out() }'
}

# Crash reports macOS wrote for this app's processes, newest first (find tests narrow them
# down, e.g. -newer FILE or -mtime -7): the game, and Wine, Java and Metal's shader compiler
# when they ran for SWGL on Mac (other apps' reports stay out).
swgl_crash_reports() {
  local f
  find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f \( -name 'SwgClient*' -o -name '*wine*' \
    -o -name '*java*' -o -name 'SWGLonMac*' -o -name 'MTLCompilerService*' \) "$@" -print0 2>/dev/null |
    xargs -0 ls -t 2>/dev/null | while IFS= read -r f; do
      case "${f##*/}" in
        SwgClient*) ;;
        MTLCompilerService*) LC_ALL=C grep -q -E '"responsibleProc" : "(SwgClient|wine)' "$f" || continue ;;
        *) LC_ALL=C grep -q -i -E 'swglonmac|SWGL on Mac' "$f" || continue ;;
      esac
      echo "$f"
    done
}

game_exit_note() {
  # After the game: how long it ran, its exit status, and any crash report macOS or the game
  # (a minidump) wrote since it started. macOS writes its report shortly after the process is
  # gone, so after an abnormal exit look again for a few seconds.
  local exe=$1 status=$2 since=$3 secs=$4 how reports i
  how="status $status"
  [ "$status" -gt 128 ] && how+=" (signal $(kill -l $((status - 128)) 2>/dev/null), unless the game's own exit code)"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    reports="$(swgl_crash_reports -newer "$since"; find "$GAME" -maxdepth 1 -name '*.mdmp' -newer "$since" 2>/dev/null)"
    [ -n "$reports" ] || [ "$status" = 0 ] || [ "$i" = 10 ] || { sleep 1; continue; }
    break
  done
  echo "=== $(date '+%F %T') game exit: $exe, $how after $((secs / 3600))h$(printf '%02dm%02ds' $((secs / 60 % 60)) $((secs % 60)))"
  if [ -n "$reports" ]; then
    printf '%s\n' "$reports" | sed 's|.*/||' |
      awk 'NR <= 5 { print "Crash report: " $0 } END { if (NR > 5) print "Crash report: and " NR - 5 " more" }'
  else
    echo "No new crash report"
  fi
}

swgl_notify() {
  osascript -e "display notification \"$1\" with title \"SWGL on Mac\"" >/dev/null 2>&1 || true
}

swgl_alert() {
  osascript -e "display alert \"SWGL on Mac\" message \"$1\" as critical" >/dev/null 2>&1 || true
}
