#!/bin/bash
# Resources/collect-logs.sh: "Collect Logs…" (SWGL on Mac menu, src/native/swglmenus.m, and
# the maintenance menu). Zips what is needed to diagnose a problem into
# ~/Desktop/SWGL-on-Mac-logs-<YYYY-MM-DD-HHMM>.zip (the logs folder if the Desktop cannot be
# written) and prints the zip's path.
#   collect-logs.sh [folder]   write the zip into folder instead
#
# In the zip: app.log, launcher.log and wine.log (their last few MB, continuing into the
# .old file when short), d9mt's debug flags and log, settings.conf, VERSIONS, a fresh
# system-info.txt, this app's crash reports of the last 7 days, and the game's options.cfg
# and custom.cfg. Never legends.cfg or launchersettings.ini (the account password), nor
# anything from the Wine prefix but its two stamp files' contents (system-info.txt).
# Every file is redacted on the way in: home folder → ~, user and full name → USER and NAME,
# account names → ACCOUNT, e-mail addresses → EMAIL, password/user name/ID settings dropped
# or REDACTED, and serial numbers and device identifiers left out.
set -u
. "$(dirname "$0")/common.sh"

name="SWGL-on-Mac-logs-$(date +%Y-%m-%d-%H%M)"
dest="${1:-$HOME/Desktop}"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
out="$work/$name"
mkdir -p "$out/crash-reports" "$out/game"

# The account names to hide, read from the files that are never copied.
accounts="$(
  awk '{ sub(/\r$/, "") } /^[ \t]*loginClientID=/ { sub(/^[^=]*=/, ""); print }' "$GAME/legends.cfg" 2>/dev/null
  awk '{ sub(/\r$/, "") } /^[ \t]*(username|accountname)[ \t]*=/ { sub(/^[^=]*=[ \t]*/, ""); print }' \
    "$GAME/launchersettings.ini" 2>/dev/null
)"

redact() {  # stdin → stdout
  SWGL_HOME_PATH="$HOME" SWGL_USER="$(id -un)" SWGL_NAME="$(id -F 2>/dev/null)" SWGL_ACCOUNTS="$accounts" \
  LC_ALL=C awk '
    # Replace w with r in s, ignoring case; only where w is a whole word if whole is set.
    function rep(s, w, r, whole,    ls, lw, res, p, n, before, after, last) {
      if (w == "") return s
      ls = tolower(s); lw = tolower(w); n = length(lw); res = ""; last = ""
      while ((p = index(ls, lw)) > 0) {
        before = p > 1 ? substr(ls, p - 1, 1) : last
        after = substr(ls, p + n, 1)
        if (!whole || (before !~ /[a-z0-9_]/ && after !~ /[a-z0-9_]/))
          res = res substr(s, 1, p - 1) r
        else
          res = res substr(s, 1, p - 1 + n)
        last = substr(ls, p + n - 1, 1)
        s = substr(s, p + n); ls = substr(ls, p + n)
      }
      return res s
    }
    # key=value, key: value, "key":"value" with a secret or identifying key: value → REDACTED.
    function secrets(s,    ls, res, p) {
      ls = tolower(s); res = ""
      while (match(ls, secret_key)) {
        p = RSTART + RLENGTH - 1
        res = res substr(s, 1, p); s = substr(s, p + 1); ls = substr(ls, p + 1)
        if (match(ls, secret_value)) {
          res = res "REDACTED"; s = substr(s, RLENGTH + 1); ls = substr(ls, RLENGTH + 1)
        }
      }
      return res s
    }
    BEGIN {
      secret_key = "(password|passwd|pwd|loginclientid|username|accountname|email|token|crashreporterkey|" \
        "deviceidentifierforvendor|bootsessionuuid|sleepwakeuuid)[\"\047]?[ \t]*[:=][ \t]*[\"\047]?"
      secret_value = "^[^\"\047&,; \t}]+"
      home = ENVIRON["SWGL_HOME_PATH"]; user = ENVIRON["SWGL_USER"]; fullname = ENVIRON["SWGL_NAME"]
      # A user name that is a common word is only replaced in paths, not everywhere.
      split("admin user users mac test game wine java guest root home apple swg shared", w, " ")
      for (i in w) common[w[i]] = 1
      n = split(ENVIRON["SWGL_ACCOUNTS"], accounts, "\n")
    }
    {
      line = tolower($0)
      if (line ~ /^[ \t]*(loginclientid|loginclientenchashedpassword|password|username|convertedpassword|accountname)[ \t]*=/) next
      if (line ~ /serial number|hardware uuid|provisioning udid/) next
      s = rep($0, home, "~", 0)
      s = rep(s, "/Users/" user, "/Users/USER", 1)
      s = rep(s, "\\users\\" user, "\\users\\USER", 1)
      if (length(user) >= 2 && !(tolower(user) in common)) s = rep(s, user, "USER", 1)
      if (length(fullname) >= 3) s = rep(s, fullname, "NAME", 1)
      for (i = 1; i <= n; i++) if (length(accounts[i]) >= 2) s = rep(s, accounts[i], "ACCOUNT", 1)
      s = secrets(s)
      gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z][A-Za-z]+/, "EMAIL", s)
      print s
    }'
}

add() {  # file [name in the zip]
  [ -f "$1" ] && redact <"$1" >"$out/${2:-${1##*/}}"
}

add_log() {  # log max-bytes: the end of the log, continuing into its .old file when short
  local f="$LOGS/$1" size=0 part
  [ -f "$f" ] || [ -f "$f.old" ] || return 0
  for part in "$f.old" "$f"; do
    [ -f "$part" ] && size=$((size + $(stat -f %z "$part")))
  done
  if [ "$size" -gt "$2" ]; then
    { echo "[SWGL on Mac: only the last $(($2 / 1000000)) MB of $1 and $1.old]"
      cat "$f.old" "$f" 2>/dev/null | tail -c "$2" | awk 'NR > 1'; } | redact >"$out/$1"
  else
    cat "$f.old" "$f" 2>/dev/null | redact >"$out/$1"
  fi
}

add_log app.log 5000000
add_log launcher.log 5000000
add_log wine.log 20000000
add "$LOGS/d9mt-debug.txt"
add_log d9mt-debug.log 5000000
add "$SETTINGS"
add "$RES/VERSIONS"
add "$GAME/options.cfg" game/options.cfg
add "$GAME/custom.cfg" game/custom.cfg
swgl_crash_reports -mtime -7 | head -10 | while IFS= read -r f; do
  add "$f" "crash-reports/${f##*/}"
done

{
  echo "SWGL on Mac logs, collected $(date '+%F %T %z')"
  echo "Versions: $(swgl_versions)"
  echo "App: $APP_BUNDLE"
  swgl_system_info
  swgl_displays
  echo "Free space: $(df -h "$SUPPORT" 2>/dev/null | awk 'NR == 2 { print $4 " of " $2 }')"
  # The Wine prefix's state: the Wine it was made for and the settings applied to it.
  echo "Prefix: $(cat "$PREFIX/.swgl-wine-version" 2>/dev/null || echo "not created"), $(cat "$PREFIX/.swgl-applied" 2>/dev/null)"
  echo "Game Mode bundle: $(cat "$SUPPORT/GameMode/SWGLGame.app/Contents/.source" 2>/dev/null || echo "not assembled")"
  for hook in winedebug debug.env; do
    [ -f "$SUPPORT/$hook" ] && { echo "Developer hook $hook:"; sed 's/^/  /' "$SUPPORT/$hook"; }
  done
  echo
  echo "Game programs:"
  find "$GAME" -maxdepth 1 -iname '*.exe' -exec stat -f '  %Sm  %12z  %N' {} + 2>/dev/null | sed "s|$GAME/||"
  echo "Mods:"
  find "$GAME/mods" -mindepth 1 -maxdepth 2 -exec stat -f '  %Sm  %12z  %N' {} + 2>/dev/null | sed "s|$GAME/mods/||"
  echo "Game crash dumps of the last 7 days (not included):"
  find "$GAME" -maxdepth 1 -name '*.mdmp' -mtime -7 -exec stat -f '  %Sm  %12z  %N' {} + 2>/dev/null | sed "s|$GAME/||"
  echo
  echo "Running processes:"
  ps -ax -o pid,etime,rss,command 2>/dev/null | awk 'NR == 1 || /wine|SwgClient|SWGL on Mac|SWGLonMac/' | grep -v -E 'awk|collect-logs'
  echo
  system_profiler SPHardwareDataType SPDisplaysDataType 2>/dev/null | grep -v -i -E 'serial|uuid|udid|activation lock'
} 2>&1 | redact >"$out/system-info.txt"

mkdir -p "$dest" 2>/dev/null
zip="$dest/$name.zip"
( cd "$work" && zip -q -r -X "$name.zip" "$name" ) || { echo "Could not create the zip" >&2; exit 1; }
if ! mv -f "$work/$name.zip" "$zip" 2>/dev/null; then
  # No access to the Desktop (privacy settings): leave it with the logs instead.
  zip="$LOGS/$name.zip"
  mv -f "$work/$name.zip" "$zip" || exit 1
fi
echo "$zip"
