#!/bin/sh
# Regression for keyboard move/resize (the winops entries): arrows
# step the frame / the size, Enter commits, Escape cancels and
# restores. The victim is a plain Tk client (its PResizeInc is the
# degenerate 1x1, so resize steps land on the 10 px default).
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
export DISPLAY=:98
rm -f /tmp/.X98-lock /tmp/.X11-unix/X98
Xvfb :98 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$HERE/wm-kbmove.log" 2>&1 &
WM=$!
sleep 1.5

"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 40 &
CA=$!
sleep 1

key() { xdotool key "$@"; sleep 0.4; }

key alt+space   # winops on the victim
key m           # keyboard MOVE mode
key Right
key Right
key Down        # 10 px per arrow: +110+80 -> +130+90
key shift+Right # 1 px fine step   -> +131+90
key Return      # commit

key alt+space
key s           # keyboard RESIZE mode
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
if grep -q 'handler error' "$HERE/wm-kbmove.log"; then
    echo "FAIL: handler errors present:"; grep 'handler error' "$HERE/wm-kbmove.log"
fi
