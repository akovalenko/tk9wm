#!/bin/sh
# Live playground: tk9wm inside a resizable Xephyr window on a real desktop.
# Usage: run-xephyr.sh [display]     (default :7; WHALE env overrides binary)
# No demo timers in this mode — the WM runs until Xephyr closes or Ctrl-C.
HERE="$(cd "$(dirname "$0")" && pwd)"
WHALE="${WHALE:-$HERE/../whalebuild/work/linux/whale}"
DPY="${1:-:7}"

Xephyr "$DPY" -resizeable -screen 1024x768 -title "tk9wm playground" &
XEPHYR=$!
trap 'kill $XEPHYR 2>/dev/null' EXIT INT TERM
sleep 1

DISPLAY="$DPY" "$WHALE" "$HERE/wm.tcl" &
echo "tk9wm live on $DPY — drag titles, click X, resize from inside clients"

# a couple of guinea pigs, when available
command -v xterm  >/dev/null && DISPLAY="$DPY" xterm  -geometry 80x24+20+20 &
command -v xclock >/dev/null && DISPLAY="$DPY" xclock -geometry 150x150+60+60 &

wait $XEPHYR
