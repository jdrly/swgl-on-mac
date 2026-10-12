#!/bin/bash
# Resources/bin/SWGLegendsLauncher.exe: after downloading a launcher update the
# Java launcher restarts itself by running "SWGLegendsLauncher.exe" and exiting.
# Java resolves that name through PATH, so it lands here: wait for the old
# launcher to exit, then reopen the app, which runs the freshly downloaded jar.
. "$(dirname "$0")/../common.sh"
parent=$PPID
(
  while kill -0 "$parent" 2>/dev/null; do sleep 0.5; done
  open "$APP_BUNDLE"
) >/dev/null 2>&1 </dev/null &
disown
