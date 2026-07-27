#!/bin/sh
# Regression for restart-in-place: a running WM, told to restart, must
# release its client, exec itself (same pid, same log fd) and adopt the
# client back — the client survives with its size and stays viewable.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:90
rm -f /tmp/.X90-lock /tmp/.X11-unix/X90
Xvfb :90 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-restart.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "переживи рестарт" 320x240 "#8ae234" \
    > "$HERE/restart-client.log" &
CA=$!
sleep 1.5
AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-restart.log" | head -1)
echo "--- actor: $AID, WM pid $WM"

"$LINUX/whale-cli" "$HERE/send-restart.tcl" :90
sleep 2.5

STATE=$(xwininfo -id "$AID" 2>/dev/null | awk '/Map State:/ {print $3}')
GEOM=$(xwininfo -id "$AID" 2>/dev/null | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
ALIVE=0; kill -0 $WM 2>/dev/null && ALIVE=1
kill $WM $CA 2>/dev/null

echo "--- verdict"
FAIL=0
if grep -q 'restart requested' "$HERE/wm-restart.log"; then
    echo "OK: restart accepted"
else
    echo "FAIL: no restart line in the log"; FAIL=1
fi
ARMED=$(grep -c 'redirect armed' "$HERE/wm-restart.log")
if [ "$ARMED" = "2" ]; then
    echo "OK: the log holds two lifetimes (redirect armed twice, same fd)"
else
    echo "FAIL: 'redirect armed' seen $ARMED times, want 2"; FAIL=1
fi
if grep -q "adopting existing window $AID" "$HERE/wm-restart.log"; then
    echo "OK: the new WM adopted $AID"
else
    echo "FAIL: $AID was not adopted after restart"; FAIL=1
fi
if [ "$ALIVE" = "1" ] && [ "$STATE" = "IsViewable" ] && [ "$GEOM" = "320x240" ]; then
    echo "OK: same pid alive, client viewable at $GEOM"
else
    echo "FAIL: pid alive=$ALIVE, client state=$STATE geom=$GEOM"; FAIL=1
fi
exit $FAIL
