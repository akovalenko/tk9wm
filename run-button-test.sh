#!/bin/sh
# Regression for the titlebar buttons: maximize toggles to the workarea
# and back (fvwm semantics — restore returns the saved geometry), close
# delivers a polite WM_DELETE_WINDOW. Button geometry is derived from
# the font-driven metrics the WM prints, nothing is hardcoded.
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:87
rm -f /tmp/.X87-lock /tmp/.X11-unix/X87
Xvfb :87 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-button.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "кнопки" 300x200 "#fce94f" \
    > "$HERE/button-client.log" &
CA=$!
sleep 1.5

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-button.log")
TH=$(sed -n 's/^WM: titlebar h=\([0-9]*\) .*/\1/p' "$HERE/wm-button.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-button.log" | head -1)
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$HERE/wm-button.log")"
BY=$((FY + 2 + TH / 2))
echo "--- actor: $AID frame at +$FX+$FY, titlebar h=$TH top=$TOP"

# maximize: the Cmax column is the second-from-right TH-wide slice
xdotool mousemove $((FX + 6 + 300 - TH - TH / 2)) $BY click 1
sleep 0.6
MAXGEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

# restore: the frame now sits at the workarea origin, 788 wide
xdotool mousemove $((6 + 788 - TH - TH / 2)) $((2 + TH / 2)) click 1
sleep 0.6
RESTGEOM=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
RESTPOS=$(xwininfo -id "$AID" | awk '/Absolute upper-left X:/ {x=$4} /Absolute upper-left Y:/ {y=$4} END {print x "," y}')

# close: rightmost button on the restored frame
xdotool mousemove $((FX + 6 + 300 - TH / 2)) $BY click 1
sleep 0.8
kill $WM 2>/dev/null

echo "--- verdict"
FAIL=0
WANTMAX="788x$((600 - TOP - 6))"
if [ "$MAXGEOM" = "$WANTMAX" ]; then
    echo "OK: maximize filled the workarea ($MAXGEOM)"
else
    echo "FAIL: maximized client is $MAXGEOM, want $WANTMAX"; FAIL=1
fi
if [ "$RESTGEOM" = "300x200" ] && [ "$RESTPOS" = "$((FX + 6)),$((FY + TOP))" ]; then
    echo "OK: second toggle restored 300x200 at +$RESTPOS"
else
    echo "FAIL: restored client is $RESTGEOM at +$RESTPOS"; FAIL=1
fi
if grep -q "got WM_DELETE_WINDOW" "$HERE/button-client.log"; then
    echo "OK: close button delivered WM_DELETE_WINDOW"
else
    echo "FAIL: client never saw WM_DELETE_WINDOW"; FAIL=1
fi
if grep -q 'handler error' "$HERE/wm-button.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-button.log"
    FAIL=1
fi
exit $FAIL
