#!/bin/bash
# Resources/settings.sh: read or change the app settings (the launcher's Features menu
# uses this; the maintenance menu shares the same settings.conf).
#   settings.sh              print the effective settings as KEY=value lines
#   settings.sh KEY VALUE    change one setting and save (on|off, D3D9=d9mt|wined3d,
#                            MOUSE_SPEED=one of MOUSE_SPEEDS in common.sh)
. "$(dirname "$0")/common.sh"
if [ $# -eq 2 ]; then
  case "$1=$2" in
    X87=on|X87=off|RETINA=on|RETINA=off|FPS_HUD=on|FPS_HUD=off|GAME_MODE=on|GAME_MODE=off|DEBUG=on|DEBUG=off) printf -v "$1" %s "$2" ;;
    D3D9=d9mt|D3D9=wined3d) D3D9=$2 ;;
    MOUSE_SPEED=*)
      case " $MOUSE_SPEEDS " in
        *" $2 "*) MOUSE_SPEED=$2 ;;
        *) echo "unsupported setting: $1=$2 (one of: $MOUSE_SPEEDS)" >&2; exit 2 ;;
      esac ;;
    *) echo "unsupported setting: $1=$2" >&2; exit 2 ;;
  esac
  swgl_save_settings
fi
swgl_settings
