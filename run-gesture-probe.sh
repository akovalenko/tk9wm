#!/bin/sh
# PROBE: the same window operation by MOUSE and by KEYBOARD must leave
# the desk in the same state. Owner's report: iconifying by keyboard
# activates the window below, iconifying by mouse leaves the desk with
# no focus at all. Two clients, one gesture per run, and the WM's own
# focus lines are the measurement.
#
#   $1 = mouse | key     which gesture to use
HERE="$(cd "$(dirname "$0")" && pwd)"
LINUX="${LINUX:-$HERE/../whalebuild/work/linux}"
MODE="${1:-key}"
LOG="$HERE/wm-gesture-$MODE.log"
export DISPLAY=:88
rm -f /tmp/.X88-lock /tmp/.X11-unix/X88
Xvfb :88 -screen 0 900x700x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$HERE/wm.tcl" > "$LOG" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" сосед 300x200 "#729fcf" "" "" 40 &
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" жертва 320x200 "#fce94f" "" "" 40 &
sleep 2

# the victim is the second frame; its geometry comes from the WM's log
VID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 2p)
NID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$LOG" | sed -n 1p)
B=6
TOP=$(sed -n 's/^WM: titlebar h=[0-9]* top=\([0-9]*\).*/\1/p' "$LOG" | head -1)
TH=$(sed -n 's/^WM: titlebar h=\([0-9]*\).*/\1/p' "$LOG" | head -1)
CX=$(xwininfo -id "$VID" | awk '/Absolute upper-left X/ {print $NF}')
CY=$(xwininfo -id "$VID" | awk '/Absolute upper-left Y/ {print $NF}')
FX=$((CX - B)); FY=$((CY - TOP))
echo "--- victim $VID frame at +$FX+$FY (border $B, decotop $TOP, titleh $TH); neighbour $NID"

# make sure the victim really holds the focus first: click its client area
xdotool mousemove $((CX + 100)) $((CY + 100)) click 1
sleep 1
echo "--- before: X focus=$(xdotool getwindowfocus)  (victim=$((VID)) neighbour=$((NID)))"

if [ "$MODE" = key ]; then
    xdotool key alt+space; sleep 0.6
    xdotool key i;         sleep 1.2
else
    # the titlebar's own menu button: first column, one button wide
    xdotool mousemove $((FX + B + 10)) $((FY + B + TH / 2)) click 1
    sleep 0.8
    import -window root "$HERE/gesture-$MODE-menu.png" 2>/dev/null
    # the popup sits at the frame's top-left, under the titlebar; its
    # rows are itemheight tall and "minimize" is the eighth
    IH=$TH   # popup rows are itemheight = the titlebar's own height
    xdotool mousemove $((FX + B + 40)) $((FY + TOP + 7 * IH + IH / 2)) click 1
    sleep 1.2
fi

echo "--- after:  X focus=$(xdotool getwindowfocus)"
import -window root "$HERE/gesture-$MODE-after.png" 2>/dev/null \
    && echo "DRIVER: screenshot -> gesture-$MODE-after.png"
kill $WM 2>/dev/null
echo "--- WM saw:"
grep -E 'winops|iconif|focus ->|parking|refused' "$LOG"
