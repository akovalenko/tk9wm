#!/bin/sh
# Regression for the live-mode race: a client maps BEFORE the WM starts —
# the WM must adopt it at startup (no MapRequest will ever come).
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$HERE/client.tcl" "дикий" 220x100 "#ad7fa8" &
C1=$!
sleep 2                                  # client is up and wild, no WM yet
"$LINUX/whale" "$WMTCL" &          # live mode: no timers, must adopt
WM=$!
sleep 3
import -display "$DISPLAY" -window root "$HERE/adopt-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/adopt-test.png"
wait $C1
kill $WM 2>/dev/null
