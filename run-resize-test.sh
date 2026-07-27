#!/bin/sh
# Regression for border/corner resize: drag the right edge (+40), the
# bottom-right corner (+30/+28), then the left edge (-20; the frame must
# MOVE so the right edge stays put). Client starts 300x200 and must end
# exactly 390x228 server-side — synthetic pointer moves are exact.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:74
rm -f /tmp/.X74-lock /tmp/.X11-unix/X74
Xvfb :74 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-resize.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200+30+30 "#fce94f" \
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
xdotool mousemove 650 450 mousedown 1 \
    mousemove $((FX + 140)) $((FY + 27)) mouseup 1
sleep 0.4

import -display :74 -window root "$HERE/resize-test.png" 2>/dev/null \
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
if [ "$GEOM" = "390x228" ]; then
    echo "OK: client is $GEOM after edge, corner and left-edge drags"
else
    echo "FAIL: client is $GEOM, want 390x228"
fi
# after the title drag the frame sits at (FX-10, FY+15); the client area
# is +6+26 inside it. The root-background drag must not have moved it.
WANTPOS="$((FX - 4)),$((FY + 41))"
if [ "$POS" = "$WANTPOS" ]; then
    echo "OK: client at +$POS after title drag; root-background drag was a noop"
else
    echo "FAIL: client at +$POS, want +$WANTPOS (root-background drag moved it?)"
fi
