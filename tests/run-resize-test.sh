#!/bin/sh
# Regression for border/corner resize: drag the right edge (+40), the
# bottom-right corner (+30/+28), then the left edge (-20; the frame must
# MOVE so the right edge stays put). Client starts 300x200 and must end
# exactly 390x228 server-side — synthetic pointer moves are exact.
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-resize.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" \
    > "$HERE/resize-client.log" &
CA=$!
sleep 1.5

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-resize.log")
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$HERE/wm-resize.log")"
echo "--- actor: $AID frame at +$FX+$FY (312x232 expected with 6px borders)"

drag() { xdotool mousemove "$1" "$2" mousedown 1 mousemove "$3" "$4" mouseup 1; sleep 0.4; }
# right edge: cw 300 -> 340 (frame 312 -> 352 wide, position unchanged)
drag $((FX + 309)) $((FY + 120)) $((FX + 349)) $((FY + 120))
# bottom-right corner of the now-352x232 frame: 340x200 -> 370x228
drag $((FX + 349)) $((FY + 229)) $((FX + 379)) $((FY + 257))
# left edge of the now-382x260 frame: 370 -> 390 wide, frame slides left
drag $((FX + 2))   $((FY + 120)) $((FX - 18)) $((FY + 120))

# title drag: the frame (now at FX-20, FY) moves +10+15
drag $((FX + 130)) $((FY + 12)) $((FX + 140)) $((FY + 27))
# a drag STARTED on the root background must be a noop even when it
# crosses a title: press on empty root, drag onto the title, release.
# Before the fix the previous drag's stale state made this a pickup.
# NB the landing point must NOT be where the previous drag released —
# stale coordinates would "move" the frame exactly onto itself and hide
# the bug (which is how the first version of this scenario lied).
xdotool mousemove 650 450 mousedown 1 \
    mousemove $((FX + 190)) $((FY + 27)) mouseup 1
sleep 0.4

# top-left corner of the frame (now at FX-10, FY+15): grow by 10x20,
# the frame slides so the bottom-right corner stays — 390x228 -> 400x248
drag $((FX - 7)) $((FY + 27)) $((FX - 17)) $((FY + 7))
# north edge (the 2px strip) of the frame now at (FX-20, FY-5): push
# DOWN by 8 — the top edge follows, the bottom edge stays: ch 248 -> 240
drag $((FX + 180)) $((FY - 4)) $((FX + 180)) $((FY + 4))

import -display "$DISPLAY" -window root "$HERE/resize-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/resize-test.png"
GEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
POS=$(xwininfo -id "$AID" | awk '/Absolute upper-left X:/ {x=$4} /Absolute upper-left Y:/ {y=$4} END {print x "," y}')
kill $WM $CA 2>/dev/null

echo "--- last wm-resize lines:"
grep 'wm-resize' "$HERE/wm-resize.log" | tail -3
echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-resize.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ "$GEOM" = "400x240" ]; then
    echo "OK: client is $GEOM after e, se, w, nw and n drags"
else
    echo "FAIL: client is $GEOM, want 400x240"
fi
# frame walk: title drag put it at (FX-10, FY+15), the root-background
# drag must not move it, the nw drag slid it to (FX-20, FY-5), the n
# push moved the top edge down to FY+3. The client area is +6+top
# inside, where top is font-driven and printed by the WM.
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-resize.log" | head -1)
WANTPOS="$((FX - 14)),$((FY + 3 + TOP))"
if [ "$POS" = "$WANTPOS" ]; then
    echo "OK: client at +$POS — anchoring held and the root-background drag was a noop"
else
    echo "FAIL: client at +$POS, want +$WANTPOS"
fi
