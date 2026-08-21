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
start_xvfb

"$LINUX/whale" "$WMTCL" > "$HERE/wm-kbmove.log" 2>&1 &
WM=$!
wait_wm "$HERE/wm-kbmove.log" $WM

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 40 &
CA=$!
wait_client "$HERE/wm-kbmove.log" 'жертва'

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

import -display "$DISPLAY" -window root "$HERE/kbmove-test.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> $HERE/kbmove-test.png"

AX2=$(xwininfo -id "$AID" | awk '/Absolute upper-left X/ {print $NF}')
SZ2=$(xwininfo -id "$AID" | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')

# --- the mode RAISES what it is about. A window can be ACTIVE and
# buried: Lower keeps the focus where it is, which is what makes "drop
# it, look at what is under it, bring it back" work — and the ops menu
# on such a window is deliberately kept. Dragging one from the keyboard
# is the case that reads as broken, so the mode raises first, the way
# every MOUSE path already does.
#
# B is planted over the victim's lower half, leaving its top band clear
# to click: a click on the client is the ordinary way to focus and
# raise, and no pixel arithmetic on the decoration is needed for it.
"$LINUX/whale" "$HERE/client.tcl" "верхнее" 400x300+150+260 "#729fcf" "" "" 20 &
CB=$!
wait_client "$HERE/wm-kbmove.log" 'верхнее'
xdotool mousemove $((AX1 + 150)) $((AY1 + 20)) click 1   # focus and raise A
sleep 0.5
key alt+space
key l           # Lower: A is active, and now at the bottom
"$LINUX/whale-cli" "$TOOLS/probe-stack.tcl" "$DISPLAY" > "$HERE/kbmove-stack1.log"
key alt+space
key m           # keyboard move on the buried, still-active window
"$LINUX/whale-cli" "$TOOLS/probe-stack.tcl" "$DISPLAY" > "$HERE/kbmove-stack2.log"
import -display "$DISPLAY" -window root "$HERE/kbmove-raise.png" 2>/dev/null \
    && echo "DRIVER: screenshot (buried window, in the mode) -> $HERE/kbmove-raise.png"
key Escape
kill $CB 2>/dev/null
sleep 0.5
# Which rung of the stack a client's frame sits on, 1 = bottom.
stack_pos() {
    awk -v id="$1" '/^stack:/ { n++; for (i = 1; i <= NF; i++)
        if ($i == id) print n }' "$2"
}
# Against the NEIGHBOUR and not against the top of the stack: the
# compass puts nine override-redirect cells of its own up there for the
# length of the mode, and they are supposed to be above everything.
BID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-kbmove.log" \
    | sed -n 2p)
A_LOW=$(stack_pos "$AID" "$HERE/kbmove-stack1.log")
B_LOW=$(stack_pos "$BID" "$HERE/kbmove-stack1.log")
A_UP=$(stack_pos "$AID" "$HERE/kbmove-stack2.log")
B_UP=$(stack_pos "$BID" "$HERE/kbmove-stack2.log")

# a client with a REAL increment grid: the resize readout counts the
# client's own units (an xterm thinks in cells) beside the pixels,
# and the arrows walk that grid — one cell plain AND with Shift (a
# grid has nothing finer), the whole number of cells nearest 50 px
# with Ctrl. The grid used to overwrite the modifiers, pinning every
# gear to one cell. Last, so that the victim's numbers above are read
# before another window takes the focus the winops chord follows.
xterm -T грид -e sleep 30 &
XT=$!
sleep 2
XTID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-kbmove.log" \
    | sed -n 3p)
xterm_w() { xwininfo -id "$XTID" | awk '/Width:/ {print $2}'; }
W0=$(xterm_w)
key alt+space
key s
import -window root "$HERE/kbmove-cells.png" 2>/dev/null \
    && echo "DRIVER: screenshot (cells readout) -> $HERE/kbmove-cells.png"
key Right           # one grid cell
key Return
W1=$(xterm_w)
key alt+space
key s
key shift+Right     # fine gear: still one cell
key Return
W2=$(xterm_w)
key alt+space
key s
key ctrl+Right      # coarse gear: the on-grid stride nearest 50 px
key Return
W3=$(xterm_w)
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
INC=$((W1 - W0)); FINE=$((W2 - W1)); STRIDE=$((W3 - W2))
# what the WM computes as Ctrl's stride: round(50/inc) cells, at
# least one — Tcl's round() is half-away-from-zero, hence +INC/2
if [ "$INC" -gt 1 ]; then
    EXP=$(( (50 + INC/2) / INC * INC ))
    [ "$EXP" -lt "$INC" ] && EXP=$INC
    echo "OK: a plain arrow walked one grid cell ($INC px)"
else
    EXP=50
    echo "FAIL: a plain arrow grew the xterm by $INC px, want one real cell"
fi
if [ "$FINE" = "$INC" ]; then
    echo "OK: Shift stays one cell on a grid ($FINE px)"
else
    echo "FAIL: Shift step is $FINE px on a grid, want one cell ($INC)"
fi
if [ "$STRIDE" = "$EXP" ] && [ "$EXP" -gt "$INC" ]; then
    echo "OK: Ctrl strides the on-grid step nearest 50 px ($STRIDE px)"
else
    echo "FAIL: Ctrl stride is $STRIDE px, want $EXP (cell $INC)"
fi
if [ -n "$A_LOW" ] && [ -n "$B_LOW" ] && [ "$A_LOW" -lt "$B_LOW" ] \
        && [ "$A_UP" -gt "$B_UP" ]; then
    echo "OK: the keyboard mode raised the buried window it was about\
 (A/B rungs $A_LOW/$B_LOW lowered, $A_UP/$B_UP in the mode)"
else
    echo "FAIL: A/B rungs were $A_LOW/$B_LOW lowered and $A_UP/$B_UP in the\
 mode — want A under B, then A over B"
fi
if grep -q "WM: keyboard move $AID" "$HERE/wm-kbmove.log"; then
    echo "OK: ...and the mode was on the buried window, not on some other"
else
    echo "FAIL: no keyboard move on $AID — the leg measured another window"
fi
if grep -q 'handler error' "$HERE/wm-kbmove.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-kbmove.log"
fi
check_invariants "$HERE/wm-kbmove.log"
