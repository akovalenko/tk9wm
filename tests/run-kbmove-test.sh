#!/bin/sh
# Regression for keyboard move/resize (the winops entries): arrows
# step the frame / the size, Enter commits, Escape cancels and
# restores. The victim is a plain Tk client (its PResizeInc is the
# degenerate 1x1, so resize steps land on the 10 px default).
#
# The mode must also SHOW itself — a modal grab with no sign of itself
# reads as a wedged desktop. The frame wears amber for the duration,
# so the border is sampled at rest, in the mode and after it; the
# titlebar readout that rides along is for the eye (kbmove-mode.png).
. "$(dirname "$0")/common.sh"
export DISPLAY=:98
rm -f /tmp/.X98-lock /tmp/.X11-unix/X98
Xvfb :98 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-kbmove.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 40 &
CA=$!
sleep 1

key() { xdotool key "$@"; sleep 0.4; }

# The frame's left border, 20 px below the client's top edge: past the
# corner grip's arm, so the pixel is the frame background and nothing
# else. Reported the way ImageMagick names colors: srgb(r,g,b).
VID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-kbmove.log" | head -1)
border_color() {
    vx=$(xwininfo -id "$VID" | awk '/Absolute upper-left X/ {print $NF}')
    vy=$(xwininfo -id "$VID" | awk '/Absolute upper-left Y/ {print $NF}')
    import -window root png:- 2>/dev/null \
        | convert png:- -format "%[pixel:p{$((vx - 3)),$((vy + 20))}]" info:-
}
CLR_REST=$(border_color)

key alt+space   # winops on the victim
key m           # keyboard MOVE mode
CLR_MOVE=$(border_color)
import -window root "$HERE/kbmove-mode.png" 2>/dev/null \
    && echo "DRIVER: screenshot (in the mode) -> $HERE/kbmove-mode.png"
key Right
key Right
key Down        # 10 px per arrow: +110+80 -> +130+90
key shift+Right # 1 px fine step   -> +131+90
key Return      # commit
CLR_DONE=$(border_color)

key alt+space
key s           # keyboard RESIZE mode
CLR_RESIZE=$(border_color)
key Right
key Right
key Down        # 10 px per arrow: 300x200 -> 320x210
key Return      # commit

AID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-kbmove.log" | head -1)
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$HERE/wm-kbmove.log" | head -1)
AX1=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF}')
AY1=$(xwininfo -id "$AID" | awk '/Absolute upper-left Y/ {print $NF}')
SZ1=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

key alt+space
key m           # move again...
key Left
key Left
key Left        # -> would land at +101+90
key Escape      # ...but CANCEL: back to +131+90

key alt+space
key s           # resize again...
key Left
key Left        # -> would shrink to 300x210
key Escape      # ...cancelled: stays 320x210

import -display :98 -window root "$HERE/kbmove-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/kbmove-test.png"

AX2=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF}')
SZ2=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

# a client with a REAL increment grid: the resize readout counts the
# client's own units (an xterm thinks in cells) beside the pixels.
# Last, so that the victim's numbers above are read before another
# window takes the focus the winops chord follows.
xterm -T грид -e sleep 30 &
XT=$!
sleep 2
key alt+space
key s
import -window root "$HERE/kbmove-cells.png" 2>/dev/null \
    && echo "DRIVER: screenshot (cells readout) -> $HERE/kbmove-cells.png"
key Escape
kill $XT 2>/dev/null

kill $WM $CA 2>/dev/null

echo "--- actor: A=$AID (deco top=$TOP)"
echo "--- keyboard lines:"
grep -E 'keyboard|winops 0x' "$HERE/wm-kbmove.log"

echo "--- verdict"
if grep -q 'BadAccess request=2' "$HERE/wm-kbmove.log"; then
    echo "FAIL: another WM owns this display — this run measured nothing"
fi
if [ -z "$AID" ]; then
    echo "FAIL: no actor id"
fi
# cascade slot +110+80, moved by 10+10+1 right and 10 down, border 6
if [ "$AX1" = 137 ] && [ "$AY1" = "$((90 + TOP))" ]; then
    echo "OK: arrows moved the client to +137+$((90 + TOP)) (10 px steps, 1 px with Shift)"
else
    echo "FAIL: client at +$AX1+$AY1 after the move, want +137+$((90 + TOP))"
fi
if [ "$SZ1" = "320x210" ]; then
    echo "OK: arrows resized the client to 320x210 (10 px steps)"
else
    echo "FAIL: client is $SZ1 after the resize, want 320x210"
fi
if [ "$AX2" = 137 ]; then
    echo "OK: Escape cancelled the second move (still at x=137)"
else
    echo "FAIL: client at x=$AX2 after the cancelled move, want 137"
fi
if [ "$SZ2" = "320x210" ]; then
    echo "OK: Escape cancelled the second resize (still 320x210)"
else
    echo "FAIL: client is $SZ2 after the cancelled resize, want 320x210"
fi
if grep -q 'keyboard move .* cancelled' "$HERE/wm-kbmove.log" \
        && grep -q 'keyboard resize .* cancelled' "$HERE/wm-kbmove.log"; then
    echo "OK: both cancels logged"
else
    echo "FAIL: cancel lines missing"
fi
echo "--- frame border: rest=$CLR_REST move=$CLR_MOVE done=$CLR_DONE resize=$CLR_RESIZE"
AMBER="srgb(193,125,17)"
if [ "$CLR_MOVE" = "$AMBER" ] && [ "$CLR_RESIZE" = "$AMBER" ]; then
    echo "OK: both keyboard modes wear the amber frame"
else
    echo "FAIL: the mode is invisible (move=$CLR_MOVE resize=$CLR_RESIZE, want $AMBER)"
fi
if [ "$CLR_DONE" = "$CLR_REST" ] && [ "$CLR_REST" != "$AMBER" ]; then
    echo "OK: committing gave the frame its focus color back ($CLR_REST)"
else
    echo "FAIL: frame stuck at $CLR_DONE after the commit (rest was $CLR_REST)"
fi
if grep -q 'keyboard resize .* — resize [0-9]*x[0-9]* ([0-9]* x [0-9]*)' \
        "$HERE/wm-kbmove.log"; then
    echo "OK: the xterm's readout counts cells as well as pixels"
    grep -o 'resize [0-9]*x[0-9]* ([0-9]* x [0-9]*)' "$HERE/wm-kbmove.log" \
        | sed 's/^/    /' | tail -1
else
    echo "FAIL: no cells in the resize readout for the xterm"
fi
if grep -q 'handler error' "$HERE/wm-kbmove.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-kbmove.log"
fi
