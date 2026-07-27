#!/bin/sh
# tk9wm step-2 demo driver: Xvfb + WM + two clients + screenshot — all in
# ONE sandbox Bash call (namespaces are per-call).
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:78
rm -f /tmp/.X78-lock /tmp/.X11-unix/X78   # stale lock from a killed Xvfb
Xvfb :78 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" demo &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "клиент-A" 240x120 "#fce94f" 300x150 &
C1=$!
sleep 0.7
"$LINUX/whale" "$HERE/client.tcl" "клиент-B" 200x90 "#8ae234" &
C2=$!
sleep 3
import -display :78 -window root "$HERE/first-frame.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/first-frame.png"
# click INSIDE client A's body: the WM's sync grab must focus A and replay
command -v xdotool >/dev/null && xdotool mousemove 145 190 click 1 \
    && echo "DRIVER: clicked inside клиент-A"
sleep 1.8
import -display :78 -window root "$HERE/after-resize.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/after-resize.png"
wait $C1
wait $C2
wait $WM
