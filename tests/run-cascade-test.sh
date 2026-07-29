#!/bin/sh
# Regression for the live report (2026-07-27): "all new windows have
# finally walked off the screen". The cascade marched forever, so on a
# long session every next frame was placed further down-right until the
# windows left the screen entirely — with no titlebar left to drag them
# back. Map many windows in a row; every single frame must stay inside.
. "$(dirname "$0")/common.sh"
export DISPLAY=:84
rm -f /tmp/.X84-lock /tmp/.X11-unix/X84
Xvfb :84 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-cascade.log" 2>&1 &
WM=$!
sleep 1.5

i=1
while [ $i -le 12 ]; do
    "$LINUX/whale" "$HERE/client.tcl" "окно-$i" 200x120 "#8ae234" &
    i=$((i + 1))
    sleep 0.35
done
sleep 4
import -display :84 -window root "$HERE/cascade-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/cascade-test.png"
sleep 6                  # clients self-exit; a bare `wait` would also wait for Xvfb
kill $WM 2>/dev/null

echo "--- placements:"
# see run-dialog-test.sh: a display still owned by an earlier WM would
# make every check below pass on frames that are not ours
if grep -q 'BadAccess request=2' "$HERE/wm-cascade.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
grep -cE 'frame \.f[0-9]+ for' "$HERE/wm-cascade.log" | sed 's/^/frames placed: /'
awk '
/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART), a, "+")
        x = a[2]; y = a[3]
        # frame is 204x148 for a 200x120 client
        if (x < 0 || y < 0 || x + 204 > 800 || y + 148 > 600)
            { print "FAIL: frame off-screen at +" x "+" y; bad = 1 }
    }
}
END { print (bad ? "VERDICT: cascade walks off the screen" \
                 : "OK: every frame of the whole cascade stayed on-screen") }
' "$HERE/wm-cascade.log"
