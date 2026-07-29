#!/bin/sh
# Probe for the owner's report (2026-07-29): the maximized flag seems to
# survive a KEYBOARD resize but not a MOUSE one. Maximize, shrink by
# each means, then hit the maximize toggle and watch which way it goes —
# back to the workarea means the flag was cleared, back to 300x200 means
# it was not.
. "$(dirname "$0")/common.sh"
export DISPLAY=:93
rm -f /tmp/.X93-lock /tmp/.X11-unix/X93
Xvfb :93 -screen 0 800x600x24 >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null' EXIT
sleep 1

"$LINUX/whale" "$WMTCL" > "$HERE/wm-maxflag.log" 2>&1 &
WM=$!
sleep 1.5
"$LINUX/whale" "$HERE/client.tcl" "жертва" 300x200 "#fce94f" "" "" 90 &
CA=$!
sleep 1.5

VID=$(sed -n 's/^WM: managed \(0x[0-9a-f]*\):.*/\1/p' "$HERE/wm-maxflag.log" | head -1)
key() { xdotool key "$@"; sleep 0.4; }
drag() { xdotool mousemove "$1" "$2" mousedown 1 mousemove "$3" "$4" mouseup 1; sleep 0.5; }
geom() {
    xwininfo -id "$VID" | awk '
        /Absolute upper-left X/ {x=$NF} /Absolute upper-left Y/ {y=$NF}
        /Width:/ {w=$2} /Height:/ {h=$2}
        END {print w "x" h "+" x "+" y}'
}

echo "start:              $(geom)"
key alt+space; key x                       # Maximize
echo "maximized:          $(geom)"

# MOUSE: pull the bottom-right corner in by 100x80
eval "$(xwininfo -id "$VID" | awk '
    /Absolute upper-left X/ {print "FX=" $NF} /Absolute upper-left Y/ {print "FY=" $NF}
    /Width:/ {print "W=" $2} /Height:/ {print "H=" $2}')"
drag $((FX + W + 3)) $((FY + H + 3)) $((FX + W - 97)) $((FY + H - 77))
echo "after mouse:        $(geom)"
key alt+space; key x                       # the toggle
echo "toggle after mouse: $(geom)"

key alt+space; key x                       # ...and back to maximized
echo "re-maximized:       $(geom)"

# KEYBOARD: the same shrink, se handle, 10 px a step
key alt+space; key s
i=0; while [ $i -lt 10 ]; do xdotool key Left; i=$((i + 1)); done
i=0; while [ $i -lt 8 ];  do xdotool key Up;   i=$((i + 1)); done
sleep 0.4
key Return
echo "after keyboard:     $(geom)"
key alt+space; key x                       # the toggle
echo "toggle after kbd:   $(geom)"

kill $WM $CA 2>/dev/null
echo "--- log:"
grep -E 'wm-resize|winops .* Maximize|keyboard resize' "$HERE/wm-maxflag.log"
