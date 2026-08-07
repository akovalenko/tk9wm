#!/bin/sh
# Regression for honest size interpretation:
#  A. a raw client that maps at 500x400 without any ConfigureRequest is
#     framed at 500x400, not at a default (the kitty case);
#  B. a client declaring a 200x150 WM_NORMAL_HINTS minimum cannot be
#     dragged smaller than that;
#  C. a client asking 900x300 on an 800x600 screen is shrunk to fit —
#     no edge starts out beyond the screen (the emacs case).
. "$(dirname "$0")/common.sh"
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-size.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-size.log" $WM

# --- A: the kitty case ---
"$LINUX/whale" "$HERE/client-size.tcl" "$DISPLAY" 500x400 > "$HERE/size-raw.log" &
CA=$!
sleep 2

# --- B: declared minimum vs a shrinking drag ---
"$LINUX/whale" "$HERE/client.tcl" "минимум" 300x200 "#fce94f" "" 200x150 \
    > "$HERE/size-min.log" &
CB=$!
wait_client "$HERE/wm-size.log" 'минимум'
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-size.log" | sed -n 2p)
eval "$(awk '/frame \.f[0-9]+ for/ {
    if (match($0, /\+(-?[0-9]+)\+(-?[0-9]+)$/)) {
        split(substr($0, RSTART + 1), a, "+")
        print "FX=" a[1] "; FY=" a[2]
    }
}' "$HERE/wm-size.log" | sed -n 2p)"
echo "--- min-size actor: $BID frame at +$FX+$FY"
# grab the bottom-right corner, try to shrink by 250x120 — the declared
# 200x150 minimum must win
xdotool mousemove $((FX + 309)) $((FY + 229)) mousedown 1 \
    mousemove $((FX + 59)) $((FY + 109)) mouseup 1
sleep 0.5

# --- C: the emacs case ---
"$LINUX/whale" "$HERE/client.tcl" "широкое" 900x300 "#ad7fa8" \
    > "$HERE/size-wide.log" &
CC=$!
wait_client "$HERE/wm-size.log" 'широкое'

RAWID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-size.log" | sed -n 1p)
WIDEID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-size.log" | sed -n 3p)
RAWGEOM=$(xwininfo -id "$RAWID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
MINGEOM=$(xwininfo -id "$BID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
WIDEGEOM=$(xwininfo -id "$WIDEID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')
kill $WM $CA $CB $CC 2>/dev/null

echo "--- verdict"
FAIL=0
if [ "$RAWGEOM" = "500x400" ]; then
    echo "OK: raw no-ConfigureRequest client framed at $RAWGEOM"
else
    echo "FAIL: raw client is $RAWGEOM, want 500x400"; FAIL=1
fi
if [ "$MINGEOM" = "200x150" ]; then
    echo "OK: shrink drag stopped at the declared minimum $MINGEOM"
else
    echo "FAIL: min-size client is $MINGEOM, want 200x150"; FAIL=1
fi
if [ "$WIDEGEOM" = "788x300" ]; then
    echo "OK: 900-wide client shrunk to $WIDEGEOM on the 800-wide screen"
else
    echo "FAIL: wide client is $WIDEGEOM, want 788x300"; FAIL=1
fi
exit $FAIL
