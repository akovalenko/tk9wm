#!/bin/sh
# PROBE: is the keyboard-after-restore loss ours or wine's? Same
# scenario under a REFERENCE window manager (fvwm3 by default, $REFWM
# to pick another): notepad plus a neighbour, iconify, restore, type.
# fvwm's own Iconify/Restore are driven by FvwmCommand-less means here:
# the WM_CHANGE_STATE route (xdotool windowminimize) and EWMH
# activation, which is exactly what a client would send.
HERE="$(cd "$(dirname "$0")" && pwd)"
WINESH="${WINESH:-$HERE/../../../tools/sandbox/wine.sh}"
REFWM="${REFWM:-fvwm3}"
export DISPLAY=:90
rm -f /tmp/.X90-lock /tmp/.X11-unix/X90
Xvfb :90 -screen 0 900x700x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null; "$WINESH" server -k >/dev/null 2>&1' EXIT
sleep 1

$REFWM > "$HERE/refwm.log" 2>&1 &
WM=$!
sleep 2
"$WINESH" server -k >/dev/null 2>&1
WINEDEBUG="${WINEDEBUG:-}" "$WINESH" notepad > "$HERE/refwm-client.log" 2>&1 &
sleep 6
xterm -T сосед -e sleep 120 &
sleep 3

WID=$(xdotool search --class -- notepad.exe | head -1)
[ -z "$WID" ] && WID=$(xdotool search --name Notepad | head -1)
echo "--- reference WM: $REFWM   notepad: $WID"
xdotool windowactivate "$WID"; sleep 1
xdotool mousemove 300 200 click 1; sleep 1
xdotool type --delay 60 'BEFORE'
sleep 1
import -window root "$HERE/refwm-1-before.png" 2>/dev/null

xdotool windowminimize "$WID"      # WM_CHANGE_STATE, the client's own route
sleep 2
echo "--- iconic: X focus=$(xdotool getwindowfocus 2>/dev/null)"
xdotool windowactivate "$WID"      # _NET_ACTIVE_WINDOW request = "restore me"
sleep 2
echo "--- restored: X focus=$(xdotool getwindowfocus 2>/dev/null)"
xdotool type --delay 60 'AFTER'
sleep 1
import -window root "$HERE/refwm-2-after.png" 2>/dev/null \
    && echo "DRIVER: screenshots -> refwm-1-before.png / refwm-2-after.png"
kill $WM 2>/dev/null
"$WINESH" server -k >/dev/null 2>&1
