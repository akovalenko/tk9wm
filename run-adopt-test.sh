#!/bin/sh
# Regression for the live-mode race: a client maps BEFORE the WM starts —
# the WM must adopt it at startup (no MapRequest will ever come).
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:79
rm -f /tmp/.X79-lock /tmp/.X11-unix/X79
Xvfb :79 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/client.tcl" "дикий" 220x100+50+50 "#ad7fa8" &
C1=$!
sleep 2                                  # client is up and wild, no WM yet
"$LINUX/whale" "$HERE/wm.tcl" &          # live mode: no timers, must adopt
WM=$!
sleep 3
import -display :79 -window root "$HERE/adopt-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/adopt-test.png"
wait $C1
kill $WM 2>/dev/null
