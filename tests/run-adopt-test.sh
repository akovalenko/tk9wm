#!/bin/sh
# Regression for the live-mode race: a client maps BEFORE the WM starts —
# the WM must adopt it at startup (no MapRequest will ever come).
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$HERE/client.tcl" "дикий" 220x100 "#ad7fa8" &
C1=$!
sleep 2                                  # client is up and wild, no WM yet
"$LINUX/whale" "$WMTCL" > "$HERE/wm-adopt.log" 2>&1 &
WM=$!                                    # live mode: no timers, must adopt
sleep 3
import -display "$DISPLAY" -window root "$HERE/adopt-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/adopt-test.png"
wait $C1
CST=$?
kill $WM 2>/dev/null

echo "--- what the WM logged:"
grep -E 'managed 0x|adopt' "$HERE/wm-adopt.log" | head -5
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-adopt.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
# The scene had only a screenshot for a verdict; the battery reads
# OK/FAIL, so the driver says the two things the screenshot showed —
# this suite predated the dialect and read as forever-red (2026-08-11).
if grep -q 'managed 0x' "$HERE/wm-adopt.log"; then
    echo "OK: the wild client was adopted at startup (no MapRequest ever came)"
else
    echo "FAIL: nothing was managed — the adoption path never ran"
fi
if [ "$CST" = 0 ]; then
    echo "OK: the client outlived the adoption and left on its own terms"
else
    echo "FAIL: the client died under the WM (exit $CST)"
fi
